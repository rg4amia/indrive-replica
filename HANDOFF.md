# Passation du projet (clone VTC à prix proposé)

Écrit le 2026-10-30 pour un autre outil ou une autre personne qui reprend le travail. Tout l'état du projet est dans des fichiers : lisez-les dans l'ordre ci-dessous avant de modifier quoi que ce soit.

## Le produit

Une application de VTC où le passager propose son prix, les chauffeurs proches l'acceptent ou font une contre-offre, le passager choisit, la course se déroule, la plateforme prélève une commission sur le solde du chauffeur. Marché de départ : Abidjan (FCFA). Destiné à être **vendu** à des exploitants.
Il s'inspire du fonctionnement d'inDrive. C'est une reconstruction de fonctionnalités, pas une copie.

## Règles à respecter (clean room)

- **Aucun code, texte, icône, image ni illustration de l'original.** Tous les libellés sont écrits à neuf. Les captures dans `replica/screens/` sont de la référence, elles ne vont jamais dans l'app.
- **Pas d'API privée de l'original.** Seulement des API publiques avec les clés de l'utilisateur.
- **Aucun compte externe créé par l'assistant, aucune clé saisie.** Les clés sont créées par le propriétaire du projet et mises dans `.env.local` (ignoré par Git). `.env.example` ne contient que des noms.
- **Jetons de design uniquement** : pas de couleur ni de taille en dur dans les composants (voir `replica/design/`). La couleur d'accent est un bleu provisoire, à remplacer au moment de la marque.
- **Sécurité** : aucune écriture directe du client sur l'argent, les courses, les offres, les notes. Tout passe par les fonctions SQL.

## À lire, dans cet ordre

| fichier | contenu |
| --- | --- |
| `replica/recon.md` | écrans (S01 à S27), parcours, composants, modèle de données, taille. Les écrans passager sont observés ; les écrans chauffeur sont inférés des pages d'aide publiques. |
| `replica/features.csv` | 67 fonctionnalités avec priorité (`must`, `should`, `could`) et colonne `clone` (`no`, `partial`, `skip`). **Aucune n'est `fait` : tout repose encore sur des données factices ou n'est pas branché.** |
| `replica/architecture.md` | pile, API, points difficiles, ordre de construction |
| `replica/backend.md` | état du backend, ce qui est testé, ce qui manque, liste de sécurité |
| `replica/build-log.md` | écran par écran : fait, partiel, non fait, défauts trouvés |
| `replica/design/components.md` | spécifications des composants |
| `replica/schema.sql` | document de conception du schéma (la source de vérité exécutable est `supabase/migrations/`) |

## Code

- `app/` : Flutter + GetX. Une seule app, deux modes (passager et chauffeur, comme un bouton « Mode conducteur »).
  - `lib/data/ride_repository.dart` : le contrat de données. **Une méthode par fonction SQL**, nommée entre crochets dans les commentaires.
  - `lib/data/fake_ride_repository.dart` : version hors ligne qui applique les mêmes règles que le SQL et simule des chauffeurs et des passagers.
  - `lib/services/map_service.dart` : carte, adresses et itinéraire derrière une interface (version factice pour l'instant).
  - `lib/core/` : jetons générés, primitives, composants communs. `lib/modules/` : contrôleurs GetX et écrans.
- `supabase/` : migrations, fonctions Edge, seed, tests d'intégration.
- `replica/tools/` : `osm_coverage.py` (adresses Photon et itinéraires OSRM) et `yandex_coverage.py`.

## Commandes

```bash
# Tests de l'app (18 tests, aucun serveur nécessaire)
cd app && flutter analyze && flutter test

# Backend : prérequis Docker démarré et `supabase start` déjà lancé
supabase/tests/run.sh          # remet la base à zéro, sert les fonctions, lance 11 étapes (≈ 1 min)

# Captures d'écran (génère replica/clone-screens/*.png)
cd app && SHOTS=1 flutter test --update-goldens test/screenshots_test.dart

# Régénérer les jetons après modification de replica/design/tokens*.json
python3 replica/design/gen_tokens.py   # puis copier flutter/app_tokens.dart vers app/lib/core/
```

**Dernière vérification (2026-10-30) :** `flutter test` passe (18). Les tests Supabase ont passé le 2026-10-29 (11 étapes sur 11) ; je ne les ai pas relancés depuis.
Les tests Supabase utilisent des numéros de téléphone fictifs déclarés dans `supabase/config.toml` (`22507000001` à `…04`, code `123456`). **Ils ne doivent jamais exister en production.**

## Décisions prises

- **Carte :** Yandex écarté (clé refusée, couverture d'Abidjan non vérifiée, version gratuite exclut le suivi de transport). On utilise **Photon** (adresses) et **OSRM** (itinéraires), derrière `MapService`. Test de couverture : 13 réussites sur 15 au premier passage, avec une référence de distance qui était fausse et que j'ai corrigée ensuite. Les références de distance sont mes estimations, pas des mesures. Les serveurs publics Photon et OSRM sont **pour les essais seulement**.
- **Commission :** prélevée au moment du « Je suis là » (arrivée au point de prise en charge), pas à l'acceptation. Idempotente. Remboursée (en attente 72 h) si le passager annule avant d'avoir signalé qu'il vient, ou s'il est absent.
- **Solde chauffeur :** journal en écriture seule (`wallet_entries`) ; le solde en cache suit par trigger ; `balance_drift()` contrôle l'écart. Le solde peut devenir négatif après une commission.
- **Paiement des courses :** espèces seulement. Seule la recharge du solde du chauffeur passe par un fournisseur.
- **Multi-exploitants :** un projet Supabase par client avec le même schéma, plutôt qu'une base partagée avec `tenant_id`.
- **Confidentialité :** le numéro de téléphone reste dans `auth.users`, jamais dans `profiles`. Les contreparties d'une course ne voient ni solde, ni priorité, ni commission.

## Décisions encore ouvertes (c'est au propriétaire du projet de trancher)

1. **Fournisseur SMS** pour la connexion (Twilio, Vonage, autre).
2. **Fournisseur de paiement** pour la recharge. Candidats évoqués : CinetPay, Flutterwave, Wave. Le webhook (`psp-webhook`) attend un format neutre ; sa fonction `parse()` est à adapter. `topup-create` n'est pas écrite.
3. **Fournisseur de tuiles de carte** et **hébergement de Photon et OSRM** (ou service payant).
4. **Contour réel de la zone desservie** : le seed utilise un rectangle.
5. **Taux de commission, solde minimum, pénalité d'annulation du chauffeur, délai de remboursement** : valeurs de départ dans `app_settings`, non publiées par l'original.
6. **Plages de trafic** pour corriger les durées d'OSRM : aucune mesure d'Abidjan, table vide.
7. **Nom et marque** : à faire avec `/replica-brand` avant toute publication.

## Prochaine tâche recommandée

Brancher l'app au serveur :

1. Ajouter `supabase_flutter` ; lire `SUPABASE_URL` et `SUPABASE_ANON_KEY` via `--dart-define` (jamais en dur).
2. Écran de connexion par téléphone et code (S02, S03) et création du profil (S04).
3. Écrire `SupabaseRideRepository implements RideRepository` : une méthode par fonction SQL (`create_ride_request`, `raise_request_price`, `cancel_request`, `list_offers`, `choose_offer`, `reject_offer`, `passenger_on_way`, `cancel_ride`, `set_driver_online`, `nearby_open_requests`, `submit_offer`, `withdraw_offer`, `driver_arrived`, `start_ride`, `complete_ride`, `my_balance`).
4. Realtime pour `offers`, `rides`, `ride_requests` ; les chauffeurs reçoivent un push puis appellent `nearby_open_requests` (ne pas leur ouvrir `ride_requests` en direct).
5. Brancher `MapService` sur `places-autocomplete` et `route-estimate`.
6. Inscription chauffeur (S17, S26) et téléversement des documents dans le bucket privé `driver-docs`, dans un dossier au nom de l'utilisateur.
7. Écrire les tests au fur et à mesure ; garder `FakeRideRepository` pour les tests d'écran.

## Pièges connus

- Avec les droits par colonne, `select=*` est refusé sur `driver_profiles`, `rides`, `profiles` : **nommez les colonnes**. L'état privé du chauffeur (solde, priorité, taux) se lit par `my_driver_state()`, pas par la table.
- `watchDriverRide` de la version factice vise le chauffeur de démonstration, pas l'identité courante ; avec Supabase l'identité vient de la session.
- Réinitialiser la base (`supabase db reset`) arrête le serveur de fonctions : relancez-le (`supabase/tests/run.sh` le fait).
- Les tests d'écran fixent la largeur à 390 px ; la feuille inférieure couvre environ 75 % de l'écran avec deux offres.
- Les captures générées n'ont pas de tuiles de carte (fond gris). Elles ne montrent pas la carte réelle.

## Ce qui n'a jamais été fait ou vérifié

- Aucun lancement sur un téléphone ou un émulateur.
- `push-dispatch` n'a jamais été exécuté (il demande un projet Firebase).
- Accessibilité au clavier seul et au lecteur d'écran : non testée. Mode sombre : défini, jamais capturé.
- Appel masqué, vérification photo, partage de trajet, suivi en direct sur la carte : non faits.
- Politique de confidentialité et conformité à la loi ivoirienne sur les données personnelles : non écrites.
- Sauvegardes et supervision : à activer sur le projet hébergé.

## État de Git

Un seul commit initial (`first commit`). De nombreux fichiers sont ajoutés ou modifiés sans commit. **Faites un commit avant de reprendre.** Les fichiers `.env`, `.env.*` et `supabase/.env.local` sont ignorés ; ne les ajoutez jamais.

## Sécurité : à faire tout de suite

La clé Yandex Geocoder `e8411c6c-…` a été collée dans une conversation et est écrite en dur dans une autre app (`APP YANGO`, fichiers `AppDelegate.swift` et `MainApplication.kt`). **Révoquez-la dans le cabinet développeur Yandex.** Elle est déjà refusée par Yandex (403), mais elle reste une clé exposée.
