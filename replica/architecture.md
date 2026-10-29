# Architecture: clone VTC à prix proposé (refonte des fonctions de base d'inDrive)

Pour : produit à vendre, marché de départ Abidjan (FCFA). Sources : `recon.md`, `features.csv` (67 lignes), `schema.sql`.
Principe : une seule base, pas de microservices, toute la logique d'argent et d'appariement dans Postgres.

## Stack

| layer | choice | why |
| --- | --- | --- |
| mobile (2 apps ou 1 app à 2 modes) | Flutter + GetX | votre choix ; une seule app avec « Mode conducteur » comme l'original évite deux publications aux stores |
| cartes (affichage) | `flutter_map` (ou `maplibre` si vous voulez des cartes vectorielles) avec un fournisseur de tuiles derrière une URL configurable | la carte s'affiche sans SDK propriétaire ; les serveurs de tuiles publics d'OpenStreetMap interdisent l'usage intensif : prendre un fournisseur de tuiles commercial (MapTiler, Stadia, etc.) ou héberger ses tuiles ; choix et prix à valider avant le lancement |
| adresses | Photon (géocodage et recherche en saisie, données OpenStreetMap), appelé par une Edge Function, avec en secours votre table `saved_places` et les lieux déjà utilisés | mesuré sur Abidjan et Bonoua : adresses retrouvées à 0,3 à 2,5 km, rues L98 et L155 connues ; un lieu précis a échoué (CHU d'Angré, 6,5 km d'écart) |
| itinéraires | OSRM (distance, durée, tracé), appelé par une Edge Function | distances plausibles sur 3 trajets ; durées sans trafic (48 min vers Bonoua contre 1 h 39 sur l'original) |
| position | `geolocator` + `flutter_background_service` | suivi écran éteint, service au premier plan sur Android |
| base | Postgres sur Supabase + PostGIS | géodonnées, verrous de ligne, RLS, tout dans un service géré |
| auth | Supabase Auth, téléphone + OTP SMS | l'original est par téléphone ; le coût SMS est un poste à surveiller |
| temps réel | Supabase Realtime (Postgres changes) pour offres et courses, Broadcast pour les positions | évite d'écrire chaque point GPS en base |
| logique métier | fonctions SQL `security definer` appelées par `rpc()` | un chemin d'écriture unique, atomique, testable en SQL |
| fonctions serveur | Supabase Edge Functions (Deno) | clés cartes, push, paiement, appels masqués, administration |
| push | Firebase Cloud Messaging (APNs côté iOS) | réveille le chauffeur quand l'app est en arrière-plan |
| paiements | recharge du solde via un fournisseur local de mobile money et carte derrière une interface unique (CinetPay, Flutterwave ou Wave : à comparer) | Stripe n'est pas disponible dans tous les pays africains, à vérifier pour votre marché ; les courses restent en espèces au départ |
| appels masqués | fournisseur de téléphonie (Twilio ou Africa's Talking, à valider) | le numéro ne doit jamais être exposé ; phase 2 |
| tâches | `pg_cron` | expiration des demandes, remboursements, purge, contrôle du solde |
| fichiers | Supabase Storage, bucket privé `driver-docs` | documents chauffeur, URL signées, jamais publics |
| back-office | Supabase Studio au départ, puis Flutter Web | validation des chauffeurs, taux de commission, zones, blocages |
| hébergement | Supabase (région la plus proche) | un projet Supabase par exploitant si vous vendez en marque blanche (voir plus bas) |

## Schéma

Tables : 21. Contrôle d'accès : RLS partout, écriture client interdite sauf profil, véhicules, contacts, lieux, jetons, notes et documents. Tout le reste passe par les fonctions. Voir [schema.sql](schema.sql). Testé sur PostGIS 16 avec des simulations de `auth` et `pg_cron` : flux complet, droits, double choix simultané. Non testé : `pg_cron`, Realtime et le vrai JWT Supabase. Le solde chauffeur peut devenir négatif après une commission ; `driver_min_balance` empêche seulement de repasser en ligne.

| groupe | tables |
| --- | --- |
| paramètres | `app_settings`, `zones`, `zone_traffic`, `commission_rates`, `ride_categories` |
| comptes | `profiles`, `driver_profiles`, `vehicles`, `driver_documents`, `emergency_contacts`, `saved_places`, `device_tokens`, `notifications` |
| boucle principale | `ride_requests`, `offers`, `rides`, `ride_positions`, `ratings` |
| argent | `wallet_entries`, `payments`, `payment_events` |

Contraintes qui portent le métier :
- Un passager ne peut avoir qu'une demande ouverte (`ride_requests_one_open_uq`).
- Un chauffeur et un passager ne peuvent avoir qu'une course active chacun (`rides_one_active_*_uq`). Deux choix simultanés échouent en base, pas dans l'app.
- Une commission et un remboursement par course, un événement de paiement une seule fois (`wallet_one_per_ride_kind_uq`, `wallet_external_ref_uq`).
- Le solde mis en cache (`driver_profiles.balance`) suit le journal par trigger. `balance_drift()` détecte tout écart.
- Le téléphone reste dans `auth.users`, jamais dans `profiles` : la contrepartie d'une course ne le voit pas.

### Règles métier configurables (non publiques chez l'original)

Elles sont dans `app_settings` et `zones`, pas dans le code :

| paramètre | valeur de départ | source |
| --- | --- | --- |
| taux de commission par zone | à vous (table `commission_rates`) | l'original ne publie pas de taux |
| solde minimum pour passer en ligne | 0 | non publié |
| annulation chauffeur : perte de priorité | 5 points | l'original dit que la priorité baisse |
| annulation chauffeur : remboursement | non, sauf passager absent | non publié ; règle à fixer |
| délai de remboursement | 72 h | l'original : 7 à 30 jours ouvrés |
| fréquence de la vérification photo | 30 jours | non publié |
| prix minimum proposé | 70 % du recommandé | à ajuster |
| bande de contre-offre | 30 % au-dessus | l'original : bande variable par pays |

## API

Le client Flutter parle à Supabase : fonctions `rpc()`, API REST protégée par RLS, Edge Functions. Total : 39 routes (19 RPC, 9 Edge Functions, 11 ressources REST).

### Fonctions RPC (17 écrites, 2 à écrire)

| route | rôle | qui | entrée | sortie | flux |
| --- | --- | --- | --- | --- | --- |
| `create_ride_request` | crée la demande, vérifie zone et prix minimum | passager | départ, arrivée, catégorie, prix, options | `ride_requests` | F01 |
| `recommended_price` | prix recommandé d'une zone, catégorie, distance | passager | zone, catégorie, distance | entier | F01 |
| `raise_request_price` | +100 pendant la recherche, invalide les acceptations à l'ancien prix | passager | demande | `ride_requests` | F01 |
| `cancel_request` | annule une demande ouverte | passager | demande, motif | vide | F06 |
| `list_offers` | cartes d'offres (chauffeur, voiture, ETA, note) | passager | demande | lignes | F01 |
| `choose_offer` | choisit une offre, crée la course | passager | offre | `rides` | F01 |
| `reject_offer` | « Refuser » | passager | offre | vide | F01 |
| `passenger_on_way` | signale « je viens » | passager | course | vide | F06 |
| `cancel_ride` | annule une course acceptée, remboursement et pénalités | passager ou chauffeur | course, motif | `rides` | F06 |
| `set_driver_online` | passe en ligne si approuvé et solde suffisant | chauffeur | booléen | vide | F02 |
| `update_driver_location` | position courante | chauffeur | lng, lat | vide | F02 |
| `nearby_open_requests` | demandes ouvertes dans le rayon, infos passager | chauffeur | — | jusqu'à 30 lignes | F02 |
| `submit_offer` | accepte au prix ou contre-offre dans la bande | chauffeur | demande, prix, ETA, voiture | `offers` | F02, F03 |
| `withdraw_offer` | retire une offre | chauffeur | offre | vide | F03 |
| `driver_arrived` | « Je suis là », débite la commission | chauffeur | course | `rides` | F02 |
| `start_ride` | démarre la course | chauffeur | course | `rides` | F02 |
| `complete_ride` | termine, crée le paiement | chauffeur | course, prix final | `rides` | F02 |
| `submit_driver_application` (à écrire) | passe `draft` à `pending` si les documents sont complets | chauffeur | — | vide | F05 |
| `my_commission_rate` (à écrire) | taux de la zone, réservé au chauffeur vérifié | chauffeur | — | entier | F02 |

### Edge Functions

| route | rôle | qui | flux |
| --- | --- | --- | --- |
| `POST /places-autocomplete` | suggestions d'adresses via Photon, biaisées autour de la zone ; fusionne `saved_places` et les lieux récents ; cache des réponses | tout connecté | F01 |
| `POST /route-estimate` | distance, durée et tracé via OSRM ; applique un coefficient de trafic configurable à la durée ; le serveur recalcule aussi la distance en ligne droite (voir `create_ride_request`) | passager | F01 |
| `POST /push-dispatch` | envoie les notifications FCM, déclenchée par un webhook de base sur `ride_requests`, `offers`, `rides` | système | F01, F02 |
| `POST /topup-create` | crée la session de paiement de recharge | chauffeur | F07 |
| `POST /psp-webhook` | reçoit le paiement, écrit `payment_events` puis `wallet_entries`, idempotent | fournisseur | F07 |
| `POST /masked-call` | ouvre une session d'appel masqué ; appelle `_charge_commission` comme l'original | passager, chauffeur | F02 |
| `POST /admin-review-driver` | approuve ou rejette un document ou un chauffeur, avec motif | administrateur | F05 |
| `POST /photo-verify` | compare le selfie à la photo de profil via un fournisseur | système | F05 |
| `POST /delete-account` | anonymise le profil, supprime documents et positions | utilisateur | RGPD |

### REST (PostgREST, protégé par RLS)

`profiles` (lire, modifier nom, photo, langue), `vehicles` (CRUD du chauffeur), `driver_documents` (insérer), `emergency_contacts`, `saved_places`, `device_tokens`, `notifications` (lire, marquer lu), `rides` (historique), `wallet_entries` (journal du chauffeur), `payments` (reçus), `ratings` (insérer, contrôlé par RLS).

### Webhooks et tâches

- **Webhooks entrants :** fournisseur de paiement (recharge), fournisseur de vérification photo, fournisseur de téléphonie (état des appels). **Sortants :** base vers `push-dispatch`.
- **Tâches `pg_cron` :** `expire_requests` toutes les 30 s (nécessite pg_cron 1.5 ou plus, sinon toutes les minutes avec un `expires_at` vérifié à chaque lecture), `settle_refunds` chaque heure, `purge_old_positions` chaque nuit, `balance_drift` chaque nuit avec alerte si une ligne ressort.
- Aucune API privée de l'original n'est utilisée.

## Les points qui mordent

- **Fuseaux horaires :** tout est en `timestamptz` UTC. Les totaux « par jour » de « Mes revenus » se calculent dans le fuseau de la zone (`zones.timezone`), sinon les courses de 23 h tombent le mauvais jour.
- **Idempotence :** webhook de paiement reçu deux fois, `driver_arrived` appelé deux fois et appel masqué qui déclenche aussi la commission sont couverts par les index uniques du journal.
- **Concurrence :** deux passagers pour un chauffeur, ou deux clics sur « Accepter », sont arbitrés par `for update` et par les index de course active. Le deuxième reçoit une erreur claire que Flutter doit traduire (« offre plus disponible »). Cas à tester : le chauffeur est choisi par deux passagers au même instant.
- **Limites de débit :** la position part toutes les 4 à 5 s en course, 15 à 30 s en attente ; `update_driver_location` doit être limité côté serveur. `create_ride_request` est limité par la contrainte d'une demande ouverte. Les appels de recherche d'adresses sont limités : saisie différée de 300 ms et cache des réponses.
- **Temps réel :** les chauffeurs ne s'abonnent pas à `ride_requests` (évaluer la RLS pour chaque chauffeur est coûteux). Ils reçoivent un push puis appellent `nearby_open_requests`, ou rafraîchissent par minuteur de quelques secondes quand l'app est ouverte. Ajouter un canal Broadcast privé par zone est la suite logique. Les positions passent par Broadcast sur un canal par course.
- **Hors ligne et arrière-plan :** les positions du chauffeur sont mises en file locale et renvoyées à la reconnexion. Android exige une notification permanente, iOS le mode « Location updates » et une justification claire pour la permission « toujours » ; sinon refus des stores.
- **Livraison des notifications :** FCM en priorité haute, canal Android dédié, notification de type « data » pour réveiller l'app ; sur iOS le délai n'est pas garanti. Prévoir le sondage de secours ci-dessus.
- **Fichiers :** documents limités à 5 Mo, JPEG ou PNG, bucket privé, URL signées de courte durée ; consignes de l'original à reprendre : document physique, lisible, pas de photo d'une photo.
- **Cartes, adresses et itinéraires (Photon, OSRM, tuiles) :**
  - *Services publics de démonstration :* `photon.komoot.io` et `router.project-osrm.org` n'ont aucune garantie de disponibilité ni de débit, et leurs conditions d'usage limitent l'usage intensif. Ils ont servi au test de couverture, pas à la production. Avant le lancement : héberger votre propre OSRM (fichier OpenStreetMap de la Côte d'Ivoire) et votre propre Photon, ou prendre un fournisseur payant. Prévoir la maintenance : mise à jour des données de carte, mémoire du serveur, supervision.
  - *Couverture mesurée (outils dans `tools/`) :* 13 réussites sur 15 au premier passage. Adresses de Cocody, Bonoua, Treichville, Yopougon et Gare de Bassam retrouvées. Échec : le CHU d'Angré (6,5 km d'écart), à couvrir par `saved_places` et par une liste de lieux fréquents que vous alimentez. Les 3 distances par la route sont plausibles, mais mes références sont des estimations, pas des mesures. À refaire sur vos vrais lieux de départ et d'arrivée avant de vous engager.
  - *Durées :* OSRM ignore la circulation. Le coefficient est dans le schéma : `zones.traffic_factor` (défaut) et `zone_traffic` (plages par jour et heure locale, la plus forte valeur l'emporte). `route-estimate` appelle `adjusted_duration_s(zone, durée OSRM)`. Les valeurs de départ sont à mesurer sur le terrain (chronométrer des trajets réels aux heures de pointe) : je n'ai aucune donnée de trafic d'Abidjan. Sinon, prendre un fournisseur avec trafic.
  - *Suivi du chauffeur :* le tracé et la position viennent de vos propres données (`ride_positions`, Broadcast), pas d'un SDK de carte. Aucun service tiers ne reçoit la position des chauffeurs, ce qui évite aussi les restrictions d'usage pour le suivi de transport.
  - *Sortie :* tout passe par l'interface `MapService` de GetX (affichage, recherche d'adresses, itinéraire) ; changer de fournisseur ne touche pas les écrans.
  - *Yandex :* écarté pour l'instant. La clé disponible est refusée (403) et la couverture d'Abidjan n'a pas pu être vérifiée ; sa version gratuite exclut aussi le suivi de transport. Il reste possible derrière `MapService` si une clé valide et une licence adaptée sont obtenues, après le test de `tools/yandex_coverage.py`.
  - *Recherche d'adresses :* saisie différée de 300 ms, cache, lieux récents et enregistrés en base pour réduire les appels.
- **Multi-tenance :** pour vendre le produit à plusieurs exploitants, le plus simple en v1 est un projet Supabase par client avec le même schéma. Si vous préférez une seule base partagée, il faudra ajouter `tenant_id` à presque toutes les tables et à toutes les policies ; à décider avant d'écrire les migrations.
- **RGPD et suppression :** `delete-account` anonymise le profil et efface documents, positions et jetons ; les courses et le journal financier restent pour la comptabilité. Positions conservées 30 jours. Vérifier la loi ivoirienne sur les données personnelles avec la politique de confidentialité.
- **Fraude et sécurité :** passagers qui annulent après avoir vu l'offre, chauffeurs qui réclament plus que le prix de l'app (blocage par un administrateur), fausses positions GPS. Prévoir un signalement et un statut `blocked` dès la v1.
- **Argent :** XOF n'a pas de décimales ; les montants sont des entiers en unité mineure. Remboursement différé de 72 h par défaut ; à communiquer aux chauffeurs.

## Ordre de construction

1. **Tranche verticale** (le cœur, le plus risqué) :
   - Écrans : S02-S03 connexion, S05 accueil, S06 itinéraire, S07 tarif, S08a/b recherche et offres, S19-S20 côté chauffeur (en ligne, demandes), S22a-S22b course, S11 fin de course.
   - Tables : `profiles`, `zones`, `ride_categories`, `driver_profiles`, `vehicles`, `ride_requests`, `offers`, `rides`, `wallet_entries`, `commission_rates`.
   - Routes : `create_ride_request`, `list_offers`, `choose_offer`, `set_driver_online`, `update_driver_location`, `nearby_open_requests`, `submit_offer`, `driver_arrived`, `start_ride`, `complete_ride`, `places-autocomplete`, `route-estimate`.
   - Preuve visée : deux téléphones, un passager et un chauffeur approuvé à la main en base, une course complète en espèces avec la commission écrite dans le journal.
2. **Indispensables** (30 lignes `must` de la matrice) :
   - Inscription chauffeur et validation (S17, S18, `driver_documents`, `admin-review-driver`).
   - Annulation et motifs (S13), notation (`ratings`), « Je suis là », remboursement.
   - Taux de commission par zone, solde (S24), recharge (`topup-create`, `psp-webhook`).
   - Suivi GPS en arrière-plan et carte en direct, numéro masqué (`masked-call`), appel d'urgence local.
3. **Souhaitables** (18 lignes) : options de course, acceptation automatique, minuteur d'offres, historique et reçus, notifications dans l'app, partage de trajet, priorité chauffeur, modification d'itinéraire.
4. **Optionnelles** (15 lignes) : arrêts multiples, niveaux chauffeur, selfie passager, mode sombre, changement de numéro.
5. **Corrections issues de `replica-entrepreneur`**, une fois lancé.

Hors périmètre : « Ville en Ville », livraison, courses planifiées (lignes marquées `skip`).
