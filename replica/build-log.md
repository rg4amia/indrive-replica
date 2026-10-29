# Journal de construction

App Flutter + GetX dans `../app`. Couche de données **factice** (`lib/data/fake_ride_repository.dart`) qui applique les règles de `schema.sql` ; contrat dans `lib/data/ride_repository.dart` (une méthode par fonction SQL). Remplacer par Supabase ne touchera pas les écrans.
Captures dans `clone-screens/` : générées par un test avec la police Roboto, **sans tuiles de carte** (fond gris), donc elles ne montrent pas la carte réelle. Rien n'a été lancé sur un téléphone ni un émulateur.
Pas de dépôt Git dans ce dossier : aucun commit fait.

Tests : 18 passent (`flutter test`) : 11 sur les règles du dépôt (une demande ouverte, prix minimum, bande de contre-offre, choix unique, commission idempotente, remboursement, expiration, acceptation automatique) et 7 sur les écrans à 390 px.

## Écrans

| ID | écran | date | état | ce qui manque | plus dur que prévu |
| --- | --- | --- | --- | --- | --- |
| S05 | Accueil passager | 2026-10-29 | partiel | pas de GPS (départ simulé), pas de lieux favoris, pas de bouton de recentrage | |
| S05b | Confirmer le point de départ | | non fait | épingle déplaçable | |
| S06 | Recherche d'itinéraire | 2026-10-29 | partiel | 8 lieux factices ; pas de choix sur la carte, pas d'arrêt ajouté ; Photon non branché | |
| S07 | Catégorie, prix, options | 2026-10-29 | partiel | pas de saisie libre du prix (S07b) ; modes de paiement absents | |
| S08a/b | Recherche et offres | 2026-10-29 | partiel | pas de nombre de chauffeurs qui consultent, pas de badge de niveau, offres refusées sans animation | la feuille couvre 75 % de l'écran avec 2 offres : la carte devient invisible sur petit écran |
| S09/S10 | Chauffeur en route, course | 2026-10-29 | partiel | pas de suivi en direct sur la carte, pas d'appel ni de message, pas de partage de trajet | |
| S11 | Fin de course, note | 2026-10-29 | partiel | pas de reçu, pas de pourboire, le chauffeur ne note pas le passager | |
| S12 | Historique | 2026-10-29 | partiel | pas de filtres, pas de détail d'une course | |
| S13 | Annulation avec motif | 2026-10-29 | fait | | |
| S-menu | Menu latéral | 2026-10-29 | partiel | pastille de notifications fixe, profil non modifiable | |
| S-notif | Notifications | | ébauche | écran « en préparation » | |
| S15 | Paramètres | | ébauche | apparence, unités, langue, suppression de compte | |
| S16 | Sécurité | 2026-10-29 | partiel | l'appel au 112 n'est qu'un dialogue ; contacts d'urgence et assistance non faits | |
| S19 | Accueil chauffeur | 2026-10-29 | partiel | solde minimum non appliqué à l'écran | |
| S20/S21 | Demandes, contre-offre | 2026-10-29 | partiel | rafraîchissement par sondage toutes les 3 s | |
| S22a/b/c | Course chauffeur, annulation | 2026-10-29 | partiel | pas de navigation ni d'appel masqué | |
| S23 | Note du passager | | non fait | | |
| S24 | Solde et commissions | 2026-10-29 | partiel | pas de recharge (bouton désactivé) | |
| S25 | Revenus | | ébauche | | |
| S02-S04 | Connexion téléphone, OTP, profil | | non fait | dépend de `/replica-backend` | |
| S17, S18, S26, S27 | Inscription chauffeur, photo, véhicule, avis | | non fait | dépend de `/replica-backend` et du back-office de validation | |

## Défauts trouvés en construisant (et corrigés)

- **Feuille inférieure sans `Material` :** les interrupteurs dedans auraient affiché un écran d'erreur rouge en mode debug sur un appareil.
- **Prix qui débordent** avec une police large ou une grande taille de texte système : adaptés (`FittedBox`).
- **Flux de course du chauffeur** abonné à l'identité courante, qui change quand on bascule de mode : le chauffeur ne voyait jamais sa course. Corrigé dans la version factice ; avec Supabase l'identité viendra de la session.
- **Repères de carte cachés** sous la feuille (marge fixe) : marge proportionnelle à l'écran.
- **Données factices fausses** (durée de 3 h pour 6 km), vues seulement sur les captures.

## À savoir

- **Le rôle chauffeur de démonstration** a un solde de 5 000 F CFA et une voiture fixes. Le « passager » et le « chauffeur » partagent un seul appareil.
- **Aucune dépendance à un serveur de tuiles pour les tests.** En production, `AppConfig.tileUrl` doit pointer vers un fournisseur de tuiles ; le serveur public d'OpenStreetMap n'est pas fait pour cela.
- **Textes :** tous écrits à neuf, aucun copié de l'original.
- **Accessibilité :** libellés sémantiques, cibles de 48 dp et prix annoncés sont en place ; **le test au clavier seul et avec un lecteur d'écran n'a pas été fait.** Le mode sombre est défini dans les jetons mais n'a pas été capturé.
- **Largeur 1440 px :** sans objet, l'app est mobile.
