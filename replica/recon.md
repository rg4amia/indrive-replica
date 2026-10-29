# Recon map: inDrive (iOS / Android) — clone en Flutter + GetX + Supabase

Scope: boucle principale VTC (passager propose son prix, chauffeurs acceptent ou contre-proposent, course suivie en direct, paiement, notes). Hors périmètre : interurbain, fret, coursier/livraison, courses planifiées.
For: produit à vendre (white-label possible pour des opérateurs de taxi locaux)
Date: 2026-10-29
Méthode: sources publiques uniquement, aucun compte utilisé, aucune API privée. Les écrans passager sont maintenant **observés** sur 27 captures (`replica/screens/`, marché Abidjan, FCFA, app v5.175.0). Les écrans chauffeur et la fin de course restent **inférés**.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | centre d'aide (catégories) | https://indrive.com/en/help | Passengers, Drivers, Couriers, App issues, Support and Safety |
| 2 | aide passagers (titres) | https://indrive.com/help/passengers | commande, annulation, paiement, historique, notes, Comfort/XL, animaux, reçus |
| 3 | aide chauffeurs (titres) | https://indrive.com/help/drivers | inscription, vérification véhicule/photo, solde, commission, notes |
| 4 | calcul des tarifs | https://indrive.com/help/passengers/how-fares-are-calculated | prix minimum recommandé, pas de formule publiée |
| 5 | fiche Google Play | https://play.google.com/store/apps/details?id=sinet.startup.inDriver | contenu non récupéré, à relire à la main |
| 6 | TechCrunch (arrivée US) | https://techcrunch.com/2023/07/20/indrive-brings-its-bid-based-ride-hail-app-to-the-us/ | modèle par enchères, commission ~10 % |
| 7 | Out of Town Blog | https://outoftownblog.com/how-does-indrive-work/ | parcours passager décrit pas à pas (source tierce) |
| 9 | aide chauffeur : devenir chauffeur (Maroc) | https://indrive.com/fr-ma/help/drivers/how-to-become-a-driver | « Mode chauffeur » puis « Inscription en ligne » |
| 10 | aide chauffeur : frais et paiements (CI) | https://indrive.com/fr-ci/help/drivers/what-are-the-charges-and-service-payments | règle de prélèvement et remboursement |
| 11 | aide chauffeur : vérification (CI) | https://indrive.com/fr-ci/help/drivers/what-are-the-steps-for-driver-and-vehicle-verification | motifs de rejet, nouvelle soumission |
| 12 | aide chauffeur : véhicule, gains, recharge, photo | https://indrive.com/fr-ci/help/drivers | critères voiture, priorité, solde |
| 13 | page chauffeur | https://indrive.com/fr-ci/driver | avantages : contre-offre, ignorer sans pénalité |
| 14 | sécurité chauffeur et passager (CI) | https://indrive.com/fr-ci/safety/drivers | numéro masqué, selfie passager, contacts d'urgence |
| 8 | Wikipedia | https://en.wikipedia.org/wiki/InDrive | commission, historique |

Lacunes : les articles eux-mêmes n'ont pas été lus (titres seulement), la fiche Play est vide, les règles de contre-offre (bande autour du prix recommandé) et la commission varient selon le pays.

## Core loop

Le passager fixe son prix, les chauffeurs proches l'acceptent ou contre-proposent, le passager choisit, et la plateforme prélève une commission sur la course.

## Screens

Passager (P) et chauffeur (D). Tous les écrans sont inférés sauf mention contraire.

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Splash / choix de rôle | lancement | entrer comme passager ou chauffeur | logo, 2 boutons | loading |
| S02 | Connexion par téléphone | S01 | saisir le numéro | champ pays + numéro, bouton | erreur numéro, loading |
| S03 | Code OTP | S02 | vérifier le numéro | 6 champs, renvoi du code | erreur, expiré, renvoi |
| S04 | Profil passager (création) | S03 premier accès | nom, photo | formulaire, avatar | erreur |
| S05 | Accueil carte (passager) | après connexion | choisir départ/arrivée | carte, barre de recherche, positions récentes | GPS refusé, hors ligne, chargement |
| S06 | Recherche d'adresse | S05 | départ / arrivée | champ, liste de résultats, épingle sur carte | vide, aucun résultat |
| S07 | Proposer son prix | S05 après les deux points | prix + options | prix recommandé, champ prix, notes, mode de paiement, type (Comfort/XL), bouton « Trouver un chauffeur » | prix sous le minimum, paiement manquant |
| S08 | Attente des offres | S07 | voir les offres arriver | liste d'offres (prix, voiture, ETA, note, nb de courses), décompte, « modifier mon prix », annuler | aucune offre, expiré, plusieurs offres |
| S09 | Course acceptée / chauffeur en route | S08 | suivre l'arrivée | carte en direct, fiche chauffeur, plaque, appeler/chat, annuler | chauffeur arrivé, annulé par le chauffeur |
| S10 | Course en cours | S09 | suivre le trajet | carte, partage du trajet, SOS, prix | perte de réseau |
| S11 | Fin de course et notation | S10 | payer et noter | prix final, étoiles, commentaire, pourboire (guess) | erreur de paiement |
| S12 | Historique des courses | menu | revoir les courses | liste, détail, reçu | vide |
| S13 | Annulation avec motif | S08 / S09 | annuler | liste de motifs | confirmation |
| S14 | Moyens de paiement | menu / S07 | choisir espèces / carte (selon marché) | liste, ajout de carte | vide |
| S15 | Profil et paramètres | menu | compte, langue, suppression | formulaire, boutons | — |
| S16 | Assistance et sécurité | menu | aide, signalement, contacts de confiance | liste d'articles, formulaire | — |
| S17 | Inscription chauffeur | S01 (rôle chauffeur) | devenir chauffeur | étapes, téléversement documents, photo du véhicule | en cours de vérification, refusé, approuvé |
| S18 | Vérification photo du chauffeur | S17 | contrôle d'identité | caméra, consignes | échec, réessayer |
| S19 | Accueil chauffeur (en ligne) | après approbation | recevoir les demandes | carte, interrupteur en ligne, solde | hors ligne, solde insuffisant |
| S20 | Liste des demandes | S19 | voir les demandes proches | cartes de demande (trajet, prix, note passager, notes), accepter, contre-offre, ignorer | aucune demande |
| S21 | Contre-offre | S20 | proposer un autre prix | sélecteur de prix borné | hors bande |
| S22 | Course chauffeur (approche / en cours) | S20 | aller chercher puis conduire | navigation, boutons « arrivé » / « démarrer » / « terminer » | passager annule |
| S23 | Fin de course et note passager | S22 | noter le passager | étoiles | — |
| S24 | Solde et recharge | menu chauffeur | voir et recharger le solde | solde, historique des commissions, recharge | solde bas |
| S25 | Gains | menu chauffeur | revenus | totaux par jour/semaine | vide |
| S26 | Profil véhicule et documents | menu chauffeur | mettre à jour | formulaire, documents | document expiré |
| S27 | Notes et avis (chauffeur) | menu chauffeur | voir sa note | note moyenne, avis | vide |

## Mise à jour : ce que montrent les captures (2026-10-29)

27 captures, toutes côté passager. Elles remplacent les hypothèses ci-dessus quand elles les contredisent.

### Écrans observés (passager)

| ID | écran réel | ce qu'on y voit | captures |
| --- | --- | --- | --- |
| S05 | Accueil carte | carte Google, bouton menu, carte « D'où » (adresse de départ), onglets de catégorie **Course / Confort / Un Clic (New) / Ville en Ville**, champ « Où et pour combien ? », adresses récentes et favorites, bouton de recentrage | WhatsApp 9.17.11, capture17 |
| S05b | Confirmer le lieu de prise en charge | épingle déplaçable, distance (29 m), « Mon emplacement », bouton Appliquer | capture7 |
| S06 | Indiquer votre itinéraire | champs De / À, historique avec distance en km, résultats de recherche (icône horloge = récent, épingle = lieu), bouton « choisir sur la carte », clavier | capture13, WhatsApp 9.17.12, 9.17.12 (1), 9.17.13 (1) |
| S07 | Choix de catégorie et du tarif | itinéraire sur la carte, ligne de départ avec **« Porte d'entrée »**, destination avec durée, ajout d'arrêt (+), feuille avec Course (4 places, 3 min, « Prix abordables »), stepper − / + sur le **tarif recommandé**, Confort (~12 000), Un Clic (11 000), interrupteur « Accepter automatiquement l'offre de X », bouton **Chercher des offres**, bouton options | capture8, capture10, capture12, capture15, WhatsApp 9.17.13 (2) |
| S07b | Proposez votre prix (saisie libre) | champ XOF, message « Veuillez remplir ce champ », mode de paiement **Espèces**, interrupteur d'acceptation automatique du conducteur le plus proche, résumé départ/arrivée | capture9 |
| S07c | Options de course | « Plus de 4 passagers », « Siège pour enfant », champ Commentaires, bouton Fermer | capture11 |
| S08a | Recherche en cours | minuteur (0:52 puis 0:43), message « Bon tarif. Votre demande est prioritaire », barre de progression, boutons −100 / +100, **Augmenter le prix**, « 5 conducteurs consultent votre demande », voitures autour sur la carte, interrupteur d'acceptation automatique | WhatsApp 9.17.13 (3), 9.17.13 (4) |
| S08b | Choisir un conducteur | titre, case « Tous les conducteurs sont vérifiés », cartes d'offre : prix, ETA (3 min), photo, nom, note, nombre de courses, modèle de voiture, badge « Votre prix », badge **Conducteur Platine**, boutons **Refuser** et **Accepter** (le bouton Accepter se remplit comme un minuteur) | WhatsApp 9.17.14, capture6 |
| S13a | Annuler votre demande ? | « Continuer la recherche » / « Annuler la commande » | WhatsApp 9.17.14 (1) |
| S13b | Motif d'annulation | Les conducteurs sont trop loin, Prix élevés, Demande accidentelle, Point de prise en charge ou de destination incorrect, Aucune offre des conducteurs, Une autre raison, Ignorer | capture5 |
| S12 | Historique des commandes | filtres Tout / Courses en ville, liste groupée par date, destination, heure, prix en FCFA, mention rouge **« Le conducteur a annulé »** avec 0 FCFA | capture3 |
| S-menu | Menu latéral | profil avec note passager (4.96, 11 avis), Ville, Historique des commandes, Ville en Ville, Notifications (pastille), Sécurité, Paramètres, Aide, Assistance, bouton **Mode conducteur** | capture16 |
| S-notif | Notifications | messages groupés par jour : alerte sécurité (« activité inhabituelle lors de votre course »), promotion avec bouton d'action | capture4 |
| S16 | Sécurité | Assistance, Contacts d'urgence, bouton rouge **Appeler 112**, section « Comment nous vous protégeons » (5 sujets) | capture2 |
| S15 | Paramètres de l'appli | Apparence, Unités de distance, Langue, Appels dans l'application (Nouveau), Documents juridiques, Version, Se déconnecter, Supprimer le compte, Changer de numéro de téléphone | capture18 |
| S06b | Choisir le point sur la carte | carte plein écran, étiquette d'adresse au-dessus de l'épingle, bouton retour, recentrage, bouton **« Terminé »** (ce n'est pas la fin d'une course) | capture14, WhatsApp 9.17.13 |

### Corrections au modèle

- **Pas de saisie obligatoire du prix** : un tarif recommandé est préchargé avec − / + (palier de 100 FCFA). La saisie libre existe en secondaire.
- **Catégories réelles** : Course (économique), Confort, Un Clic (nouveau, prix intermédiaire), Ville en Ville (interurbain). Ma liste « Standard/Comfort/XL » était fausse.
- **Offres chauffeur** : les offres arrivent en cartes empilées avec un minuteur sur le bouton Accepter. Un chauffeur peut accepter au « Votre prix » sans contre-offre ; le niveau du chauffeur (Platine) est affiché.
- **Montée du prix en cours de recherche** : le passager peut augmenter son prix de 100 en 100 pendant le décompte, et le message indique si la demande est « prioritaire ».
- **Acceptation automatique** : le passager peut accepter d'avance le conducteur le plus proche au prix proposé.
- **Annulation par le chauffeur** visible dans l'historique, avec un prix de 0.
- **Point de prise en charge** : un indicateur « Porte d'entrée » (précision du lieu) accompagne l'adresse.
- **Appels dans l'application** : appel intégré dans l'app (fonction « Nouveau »).
- **Paiement** : seul « Espèces » est visible, devise XOF.

### Toujours inconnu (aucune capture)

- Tout le côté chauffeur (S17 à S27).
- Course en cours (S09, S10), fin de course et notation (S11), reçu, moyens de paiement détaillés (S14), inscription par téléphone et OTP (S02-S04), « Ville en Ville », « Un Clic », chat/appel.
- Pour finir le recon avec rigueur, il faudrait des captures de ces écrans.

### Nouveaux composants repérés

| component | variants | states | used on |
| --- | --- | --- | --- |
| Feuille de catégories | Course, Confort, Un Clic | sélectionnée, prix estimé | S07 |
| Stepper de prix | − / +, palier 100 | minimum atteint (bouton grisé) | S07, S08a |
| Bouton à minuteur | Accepter | se remplit jusqu'à expiration | S08b |
| Carte d'offre enrichie | badge Votre prix, badge Platine, photo | chargement de la photo | S08b |
| Interrupteur | acceptation automatique, options | on, off | S07, S07b, S07c |
| Pastille de notification | nombre | — | menu |
| Bannière « Appeler 112 » | danger | — | S16 |

## Mise à jour : côté chauffeur, depuis les pages d'aide officielles (2026-10-29)

Pas de captures chauffeur. Tout ce qui suit vient de pages publiques ; les écrans restent **inférés**, les règles sont **sourcées**.

### Règles confirmées

- **Passage en mode chauffeur :** depuis le menu passager, bouton « Mode conducteur », puis « Inscription en ligne » : on envoie des photos de documents et ses informations personnelles. Après validation de l'équipe, le chauffeur peut accepter des demandes. Les documents exacts dépendent du pays.
- **Vérification :** documents lisibles, à jour, cohérents avec le profil, photographie du document physique (pas une photo d'une photo). Motifs de rejet : photo floue, document expiré, informations incorrectes, mauvaise photo. En cas de rejet, on consulte la raison dans « Inscription en ligne », on corrige et on soumet à nouveau. Notifications utiles pour suivre l'avancement.
- **Vérification photo régulière** du profil chauffeur (déclencheur et conséquences non publiés).
- **Véhicule :** à son nom ou loué à son nom, au moins 4 portes, 5 à 8 places conducteur compris, pas de véhicule accidenté non réparable. Âge maximum selon le pays. Aucun modèle précis imposé. Sinon, proposer le rôle de coursier.
- **Commission (« paiement de service ») :** un pourcentage du prix de chaque course, taux variable selon le lieu, visible seulement pour un chauffeur vérifié. Elle est **débitée automatiquement du solde** quand le chauffeur : arrive au point de prise en charge, ou appelle le passager via l'app, ou appuie sur **« Je suis là »**. **Ce n'est pas au moment de l'acceptation**, contrairement à ce que disait une source tierce.
- **Remboursement :** si le passager n'arrive pas au point de départ, ou annule avant d'avoir signalé qu'il est en route. Le chauffeur annule et choisit le motif. Crédit sur le solde de l'app en 7 à 30 jours ouvrés (variable). Silence sur les annulations faites par le chauffeur.
- **Solde dans l'app :** sert à payer la commission, rechargeable. Moyens de recharge, délais, solde minimum : non publiés.
- **Priorité du chauffeur :** monte avec les courses terminées et les bonnes notes, baisse avec les annulations de courses acceptées. Elle conditionne les demandes reçues.
- **Interdictions :** réclamer plus que le prix de l'app expose au blocage du compte.
- **Gains :** « Mes revenus » (menu Ville), revenus par jour et par semaine, mise à jour 24 h après la course.
- **Demandes :** le chauffeur voit le trajet, le nom, la photo et la note du passager avant d'accepter ; il accepte, fait une contre-offre ou ignore sans pénalité.
- **Sécurité :** numéro masqué dans les deux sens pour les appels et messages, selfie de vérification du passager, surveillance des demandes à risque, blocage des utilisateurs à risque, partage du trajet avec des proches, appel d'urgence depuis l'app, contacts d'urgence prévenus, assistance 24 h sur 24. Le chauffeur peut indiquer des sièges enfants et l'acceptation des animaux.
- **Passager :** peut modifier l'itinéraire ou la destination (le tarif peut changer), signaler un objet oublié depuis le menu, noter la course.
- **Reçus :** les deux côtés ont un article « reçus et factures ».

### Écrans inférés, mis à jour (chauffeur)

| ID | écran | accès | ce qu'il contient |
| --- | --- | --- | --- |
| S17 | Inscription en ligne | menu, Mode conducteur | liste des documents demandés par pays, envoi photo par document, statut global |
| S17b | Motif de rejet | S17 | raison par document, bouton pour renvoyer |
| S18 | Vérification photo | déclenchée par l'app | consignes, caméra, résultat |
| S19 | Accueil chauffeur | Mode conducteur | carte, état en ligne/hors ligne, accès aux demandes, solde |
| S20 | Liste des demandes | S19 | cartes : trajet, prix proposé, nom, photo, note du passager, notes (siège enfant, etc.), boutons accepter / contre-offre / ignorer |
| S21 | Contre-offre | S20 | prix modifiable dans une bande |
| S22a | En route vers le passager | acceptation | navigation, appel et message masqués, bouton **« Je suis là »** (déclenche la commission) |
| S22b | Course en cours | après prise en charge | navigation, bouton terminer, contacts d'urgence, partage |
| S22c | Annulation chauffeur | S22 | choix du motif, effet sur remboursement et priorité |
| S23 | Fin de course et note passager | S22b | prix, étoiles, commentaire |
| S24 | Solde et recharge | menu | solde, historique des prélèvements, recharge |
| S25 | Mes revenus | menu Ville | jour, semaine |
| S26 | Profil et véhicule | menu | détails, documents, remplacement de document |
| S27 | Note et avis | menu | note moyenne, avis |
| S-pr | Frais et paiements | liste des demandes, Paiement | taux de commission du lieu (si vérifié) |
| S-recu | Reçus et factures | menu | liste, téléchargement |

### Nouvelles entités et champs

```
DriverProfile  + priority_score, verification_status (pending | approved | rejected), rejection_reason, last_photo_check_at
               evidence: aide « gains », « vérification », « vérification photo »
               confidence: medium

Ride           + driver_arrived_at (« Je suis là »), commission_charged_at, passenger_signalled_on_way_at
               evidence: aide « frais et paiements »
               confidence: high

WalletEntry    kind ajoute refund_pending ; refund délai 7 à 30 jours
               confidence: medium

Commission rate par zone : CommissionRate  zone_id, rate_pct, effective_from
               evidence: aide « frais » (taux dépend de la position)
               confidence: medium

ContactMasking : appels et messages via l'app (proxy téléphonique)
               confidence: high (fonction), guess (technique)
```

## Flows

```
F01 Le passager commande une course
    S05 -> S06 -> S07 -> S08 -> S09 -> S10 -> S11
    happy path clics: ~9 (point d'arrivée, prix, trouver, choisir une offre, puis suivi sans action, noter)
    edge: aucune offre avant l'expiration, prix sous le minimum, chauffeur annule, GPS refusé, passager annule après acceptation

F02 Le chauffeur accepte une demande
    S19 -> S20 -> S22 -> S23
    happy path clics: ~5 (en ligne, accepter, arrivé, démarrer, terminer)
    edge: un autre chauffeur est choisi, solde insuffisant, passager annule, demande expirée

F03 Le chauffeur fait une contre-offre
    S20 -> S21 -> (passager S08) -> S09
    edge: contre-offre hors bande, plusieurs contre-offres simultanées, offre retirée

F04 Inscription passager
    S01 -> S02 -> S03 -> S04 -> S05
    happy path clics: 4 + saisie

F05 Inscription chauffeur
    S01 -> S02 -> S03 -> S17 -> S18 -> (attente) -> S19
    edge: document refusé, photo échouée, délai de vérification, modèle de voiture non accepté

F06 Annulation
    S08/S09 -> S13
    edge: annulation tardive (pénalité ? à confirmer), annulation chauffeur (commission perdue d'après une source tierce)

F07 Recharge du solde chauffeur
    S24 -> paiement -> S19
    edge: échec de paiement
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Button | primary, secondary, ghost, danger | default, pressed, disabled, loading | tous |
| Champ téléphone | avec préfixe pays | focus, erreur | S02 |
| Champ OTP | 6 cases | focus, erreur, expiré | S03 |
| Carte (map view) | passager, chauffeur | chargement, GPS refusé, hors ligne | S05, S09, S10, S19, S22 |
| Barre de recherche d'adresse | départ, arrivée | vide, résultats, aucun résultat | S05, S06 |
| Sélecteur de prix | stepper, saisie | sous le minimum, valide | S07, S21 |
| Carte d'offre | prix, voiture, ETA, note | sélectionnée, expirée | S08 |
| Carte de demande | trajet, prix, notes | nouvelle, expirée | S20 |
| Fiche chauffeur / passager | avec photo, plaque | — | S08, S09, S20 |
| Étoiles de notation | 1 à 5 | vide, remplie | S11, S23, S27 |
| Bottom sheet | trajet, offres, annulation | repliée, dépliée | S05 à S10 |
| Toast / bandeau d'erreur | info, erreur | — | tous |
| Liste d'historique | course, commission | vide | S12, S24 |
| Interrupteur en ligne | on/off | — | S19 |

## Inferred data model

```
User         id, phone, name, avatar_url, role (rider | driver | both), locale, rating_avg, rating_count, status (active | blocked)
             evidence: S02-S04, S15, aide « Unblock an account », « Check my rating »
             confidence: high

DriverProfile  user_id, status (pending | approved | rejected), city, verified_at, online, location (geography), balance_cents
             evidence: S17-S19, S24, aide drivers (vérification, solde)
             confidence: high

Vehicle      id, driver_id, make, model, year, color, plate, category (standard | comfort | xl), photo_url
             evidence: S17, S26, « Which car model does inDrive accept? », « special ride types »
             confidence: high

Document     id, driver_id, type, file_url, status, expires_at
             evidence: S17, S26
             confidence: medium

RideRequest  id, rider_id, pickup (geo + address), dropoff (geo + address), offered_price_cents, recommended_price_cents,
             category, payment_method, note, status (open | matched | cancelled | expired), expires_at
             evidence: S07, S08, page « How fares are calculated »
             confidence: high

Offer        id, request_id, driver_id, price_cents, eta_seconds, kind (accept | counter), status (pending | chosen | withdrawn | expired)
             evidence: S08, S20, S21
             confidence: high

Ride         id, request_id, rider_id, driver_id, vehicle_id, agreed_price_cents, status (to_pickup | arrived | in_progress | completed | cancelled),
             started_at, ended_at, cancel_reason, cancelled_by, final_price_cents
             evidence: S09-S11, S13, S22
             confidence: high

RidePosition  id, ride_id, location, recorded_at
             evidence: S09, S10 (suivi en direct)
             confidence: medium

Rating       id, ride_id, from_user_id, to_user_id, stars, comment
             evidence: S11, S23, S27, aide « Rating and reviews »
             confidence: high

Payment      id, ride_id, method (cash | card | wallet), amount_cents, status
             evidence: S14, aide « Payment methods », « receipts/invoices »
             confidence: medium (les moyens dépendent du marché)

WalletEntry  id, driver_id, kind (topup | commission | refund | penalty), amount_cents, ride_id
             evidence: S24, source tierce (commission prélevée du solde à l'acceptation)
             confidence: medium

Message      id, ride_id, sender_id, body, created_at
             evidence: S09 (chat, guess)
             confidence: guess

SafetyContact  id, user_id, name, phone
             evidence: S16 (guess)
             confidence: guess
```

Relationships: User 1-1 DriverProfile, DriverProfile 1-n Vehicle, DriverProfile 1-n Document, User 1-n RideRequest, RideRequest 1-n Offer, RideRequest 1-0..1 Ride, Ride 1-n RidePosition, Ride 1-n Rating, Ride 1-n Payment, DriverProfile 1-n WalletEntry.

## Feature matrix

Voir `features.csv`. Must: 30, should: 18, could: 15, skip: 4.

## Out of scope (cannot or should not be cloned)

- Les données et le réseau d'inDrive : la base de chauffeurs et de passagers, la liquidité par ville.
- Les partenariats de paiement locaux et les licences de transport par pays (à obtenir par marché).
- La logique de prix recommandé : aucune formule publique. À concevoir soi-même (distance × tarif par ville).
- Fonctions sécurité internes (modération, détection de fraude, vérification d'identité par un tiers) : à rebrancher via un fournisseur.
- Le nom, la marque, les illustrations et la charte graphique d'inDrive.

## Size

Screens 27, flows 7, entities 12. Hard parts: appariement en temps réel (offres et contre-offres), suivi GPS en direct côté chauffeur (arrière-plan Flutter), commission et solde chauffeur (cohérence financière), vérification des chauffeurs, paiements selon le marché. Size: L (un trimestre pour la boucle principale des deux apps).
