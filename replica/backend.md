# Backend : état, décisions et reste à faire

Pile : Supabase (Postgres 17 + PostGIS, Auth par téléphone, Storage, Realtime, `pg_cron`, Edge Functions Deno). Code dans `supabase/`.
Testé en local contre la vraie pile Supabase (`supabase/tests/run.sh`). **Rien n'est déployé et aucun compte externe n'a été créé.**

## Ce qui existe

| domaine | contenu | fichier |
| --- | --- | --- |
| Base | 21 tables, RLS sur toutes, fonctions métier `security definer`, 3 tâches `pg_cron` | `supabase/migrations/20261029000001_core_schema.sql` |
| Serveur | profil automatique, dossier chauffeur, validation admin, position, anonymisation, recharge idempotente, confidentialité des colonnes, bucket privé | `supabase/migrations/20261029000002_backend_features.sql` |
| Données locales | zone « Abidjan et Bonoua » (rectangle approximatif), taux de démonstration 10 % | `supabase/seed.sql` |
| Fonctions | `places-autocomplete` (Photon), `route-estimate` (OSRM + coefficient de trafic), `psp-webhook`, `delete-account`, `push-dispatch` | `supabase/functions/` |
| Config | auth par SMS avec numéros de test, webhooks sans JWT | `supabase/config.toml` |
| Tests | 11 étapes d'intégration (vrais comptes, JWT, stockage, fonctions) | `supabase/tests/` |

## Auth

- [x] Connexion par téléphone et code (OTP), profil créé par un trigger. Pas d'e-mail ni de mot de passe : l'original n'en a pas.
- [x] Rôles : passager, chauffeur (table `driver_profiles`, validation admin), administrateur (`app_metadata.role = 'admin'`, posé côté serveur seulement ; `user_metadata` n'est jamais lu).
- [x] Suppression de compte réelle : fonction `delete-account` (anonymise, efface documents et positions, supprime l'identité). Courses et journal financier conservés sans données personnelles. Bloquée pendant une course active ou avec un solde positif.
- [ ] **Fournisseur SMS réel** : à créer par vous (Twilio, Vonage…). Le fichier de configuration contient des valeurs factices qui n'envoient rien. Les numéros de test (`22507000001` à `…04`, code `123456`) ne doivent jamais exister en production.
- [ ] Déconnexion de tous les appareils : disponible dans l'API Auth (`scope=global`), pas encore appelée par l'app.
- [ ] Rôle administrateur en production : se pose avec la clé service_role, depuis un script que vous lancez.

## Base de données

- [x] Migrations versionnées, appliquées par `supabase db reset` ; **testées sur Postgres 17 réel**.
- [x] Second utilisateur n'obtient rien : testé (profil, demande, offres, course, tracé, journal, stockage).
- [x] Écriture client interdite sur argent, courses, offres, notes sans passer par les fonctions. Colonnes sensibles (`balance`, `priority_score`, `commission`) illisibles des tiers.
- [x] Catégorie de véhicule (Confort…) imposée côté serveur : un chauffeur ne peut pas se l'attribuer.
- [ ] **Sauvegardes** : à activer dans le projet Supabase hébergé (quotidiennes sur l'offre payante). Rien à vérifier en local.
- [ ] **Contour réel de la zone** : le seed utilise un rectangle. À remplacer par le polygone de la zone desservie, sinon des courses hors zone seront acceptées.
- [ ] **Taux de commission, solde minimum, pénalités** : valeurs de départ dans `app_settings`, à décider (l'original ne publie pas de taux).
- [ ] **Plages de trafic** : table vide. Aucune mesure d'Abidjan disponible ; sans elles, les durées sont optimistes.

## Paiements

L'original encaisse les courses en espèces ; seul le **solde chauffeur** se recharge.
- [x] Webhook de recharge : signature HMAC obligatoire en temps constant, événement enregistré avant le crédit, rejeu sans double crédit, charge invalide et montant négatif refusés. Testé.
- [ ] **Fournisseur de paiement : non choisi.** Candidats évoqués : CinetPay, Flutterwave, Wave. Il faut vérifier leurs conditions pour votre marché. Le code attend un format neutre ; la fonction `parse()` de `psp-webhook` est à adapter au format du fournisseur retenu, avec sa propre méthode de signature.
- [ ] Création de session de paiement (`topup-create`) : non écrite, dépend du fournisseur.
- [ ] Mode test du fournisseur, puis clés réelles créées par vous.
- Pas de Stripe : non retenu (disponibilité sur votre marché à vérifier).

## Tâches planifiées

- [x] `expire-requests` toutes les 30 s : **testé** avec le vrai `pg_cron`. `settle-refunds` (horaire) et `purge-positions` (nuit) planifiées ; `settle-refunds` testée en l'appelant directement.
- [ ] `balance_drift()` : existe, **pas encore planifiée** avec alerte. À brancher sur une notification à l'administrateur.
- [ ] Pas de relance automatique ni de journal des échecs (dead-letter) : à ajouter avec le premier traitement asynchrone réel (push).

## Intégrations

| service | API officielle | portée | revue / coût | état |
| --- | --- | --- | --- | --- |
| Adresses | Photon (OpenStreetMap) | aucune | serveur public : usage limité, sans garantie | testé ; **à héberger** pour la production |
| Itinéraires | OSRM | aucune | idem | testé ; **à héberger** |
| Tuiles de carte | fournisseur à choisir | aucune | payant à l'usage | non choisi |
| SMS de connexion | à choisir | envoi de SMS | coût par SMS ; sender ID par pays parfois soumis à enregistrement | non fait |
| Notifications push | Firebase Cloud Messaging v1 | `firebase.messaging` | gratuit ; APNs requis pour iOS (compte développeur Apple payant) | `push-dispatch` écrit, **jamais exécuté** |
| Appel masqué | à choisir (Twilio, Africa's Talking…) | voix | coût à la minute ; numéros locaux à vérifier | non fait |
| Vérification photo | à choisir | — | — | non fait |

Aucun service ne demande de vérification OAuth type Google Calendar. Les stores demandent en revanche une justification de la permission de localisation « toujours » (voir `replica/architecture.md`).

## Liste de sécurité

- [x] Secrets dans les variables d'environnement ; `.env`, `.env.*` ignorés ; `.env.example` sans valeurs. **La clé Yandex collée dans cette conversation doit être révoquée** ; elle est aussi en dur dans l'app APP YANGO.
- [x] Entrées validées côté serveur : fonctions SQL (prix, bande, coordonnées, zone) et Edge Functions (longueur, bornes, UUID, entiers).
- [x] Autorisation testée avec un second utilisateur sur lecture et écriture.
- [~] Limites de débit : **en place** pour les Edge Functions (par utilisateur, en mémoire du worker, donc non partagée entre instances), la position GPS (2 s) et l'envoi de SMS (5 s par numéro, géré par Supabase). **Manquantes** : création de demandes (limitée seulement par « une demande ouverte »), recherche de comptes. Pas de captcha.
- [x] Webhooks : signature vérifiée (paiement), secret partagé (push).
- [x] Envois de fichiers : 5 Mo, JPEG/PNG, bucket privé, dossier par utilisateur, accès public refusé. **Pas d'analyse antivirus** et le type MIME déclaré n'est pas vérifié sur le contenu.
- [~] Données personnelles dans les URL et journaux : aucune dans les URL ; les erreurs de fonctions n'impriment pas les numéros. **Non audité** sur l'hébergement réel.
- [ ] `npm audit` : sans objet (aucun package npm ; les fonctions importent `@supabase/supabase-js@2` à la volée par Deno). Épingler la version exacte avant le déploiement.
- [ ] **Politique de confidentialité** : à écrire ; elle doit citer chaque sous-traitant (hébergeur, fournisseur SMS, paiement, push, cartes, téléphonie). Vérifier la loi ivoirienne sur la protection des données personnelles.
- [ ] CORS des fonctions : `*` pour l'instant ; inutile pour une app mobile, à restreindre si une interface web est ajoutée.

## Défauts trouvés en construisant

- Une contrepartie de course pouvait lire le **solde du chauffeur** et la **commission de la plateforme** par l'API de table : colonnes retirées des droits de lecture, état privé servi par `my_driver_state()`.
- Un chauffeur pouvait s'attribuer la catégorie **Confort** : neutralisé par trigger.
- Un profil référencé par des courses empêchait la suppression de l'identité : la clé étrangère vers `auth.users` est supprimée, le profil est anonymisé.
- Avec les droits de colonne, `select=*` est refusé par l'API : l'app doit nommer ses colonnes.

## Ce qui reste avant `/replica-test` complet

1. Brancher l'app Flutter (`RideRepository` Supabase), avec `supabase_flutter` et les clés passées par `--dart-define`.
2. Ordre conseillé côté app : connexion par SMS, puis `SupabaseRideRepository`, puis téléversement des documents, puis Realtime.
3. Décisions à prendre : fournisseur SMS, fournisseur de paiement, hébergement de Photon/OSRM, tuiles de carte, contour de zone, taux de commission.
