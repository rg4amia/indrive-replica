# Composants (Flutter + GetX)

Tokens : `tokens.json` (clair), `tokens-dark.json` (sombre), générés dans `flutter/app_tokens.dart` et `tokens.css`. Les composants lisent `Theme.of(context).extension<AppPalette>()`, jamais une valeur hexadécimale.
Mesures prises sur `replica/screens/` (540 px de large, soit 1,5 × les dp). Tous les libellés sont écrits par nous ; les icônes viennent d'un jeu ouvert (Lucide ou Phosphor), pas de celles de l'original.
Cible tactile minimale 48 dp. Chaque composant a un `Semantics` explicite.

## Button
  variants  primary (accent), secondary (surface), ghost, danger (danger-soft + danger)
  sizes     md 48, lg 56 (bouton principal en bas d'écran, pleine largeur moins 16 de marge)
  states    default, pressed, focus (anneau 2 dp accent), disabled (opacité .4, reste annoncé), loading (le libellé reste lisible par le lecteur d'écran, indicateur à la place de l'icône)
  tokens    radius md, texte label, hauteur 56 pour l'action principale
  a11y      rôle bouton, état désactivé annoncé, `loading` annoncé « en cours »
  used on   S02, S07, S11, S13, S17, S21, S24

## PriceStepper
  variants  stepper (− / +), saisie libre
  states    default, minimum atteint (− désactivé), erreur « sous le minimum », verrouillé pendant la recherche
  tokens    montant en `price`, boutons ronds 48, palier `zones.price_step` (50) ou `raise_step` (100) pendant la recherche
  a11y      valeur annoncée « 3 450 francs », boutons nommés « Baisser de 100 » / « Monter de 100 », montant formaté avec séparateur d'espace insécable
  used on   S07, S08a, S21

## CategoryTabs
  variants  Course, Confort, Un Clic
  states    sélectionné (accent-soft), prix estimé affiché, indisponible
  a11y      onglets, état sélectionné annoncé
  used on   S05, S07

## RouteSheet (feuille inférieure)
  variants  repliée, mi-hauteur, dépliée (max 85 % de l'écran)
  states    glissement, verrouillée pendant une course
  tokens    radius sheet 24, shadow sheet, poignée 36 × 4
  a11y      poignée activable, action « Développer / Réduire » ; ne piège pas le focus (la carte reste utilisable)
  used on   S05 à S10, S13

## AddressField
  variants  départ, arrivée, arrêt supplémentaire
  states    vide, saisie, résultats, aucun résultat, erreur réseau, lieu récent (icône horloge), lieu enregistré (épingle)
  tokens    hauteur 56, bordure border-input
  a11y      libellé visible « De » / « À », résultats annoncés (« 4 résultats »)
  used on   S05, S06

## OfferCard
  variants  au prix proposé (badge), contre-offre (prix + écart), chargement de la photo
  states    nouvelle, bouton « Accepter » avec minuteur (barre qui se remplit jusqu'à `expires_at`), expirée (grisée, boutons désactivés), refusée (sortie animée)
  tokens    surface-raised, radius lg, shadow card, prix `price`, durée `title` en text-muted, avatar 56
  a11y      carte annoncée en une phrase (« 3 800 francs, 3 minutes, Marcel, 4,87 sur 3 477 courses, Suzuki Dzire »), le minuteur est aussi annoncé en texte, pas seulement en couleur ; Accepter et Refuser ≥ 48
  used on   S08b

## StatusChip
  variants  info (accent-soft), danger (danger-soft), neutre (surface), niveau chauffeur
  states    default
  a11y      le texte porte le sens, jamais la couleur seule (« Le conducteur a annulé »)
  used on   S08b, S12

## Avatar
  variants  sm 40, md 56 ; photo, initiales, chargement
  states    chargement (indicateur discret), erreur (initiales)
  a11y      décoratif quand le nom est à côté

## RatingStars
  variants  affichage (4,96), saisie (1 à 5)
  states    vide, partielle, pleine
  a11y      saisie : un `Slider` sémantique de 1 à 5, chaque étoile ≥ 48 de zone tactile

## ListRow
  variants  historique (image, titre, heure, prix), menu (icône, libellé, pastille), réglage (libellé, valeur, chevron)
  states    default, pressed, désactivée
  tokens    séparateurs border ou espacement 8
  a11y      toute la ligne est une cible, valeur lue avec le libellé

## Toggle
  variants  option (« Plus de 4 passagers »), acceptation automatique
  states    off, on, disabled
  a11y      libellé lié, état annoncé

## SelectionSheet
  variants  motifs d'annulation, moyens de paiement, langue
  states    liste, sélection, « Une autre raison » avec champ libre
  a11y      focus dans la feuille, fermeture par bouton visible et geste retour

## EmergencyButton
  variants  danger plein
  tokens    danger / on-danger, radius md, hauteur 56
  a11y      confirmation avant l'appel, numéro local lu à voix haute

## Toast et bannière
  variants  info, erreur, hors ligne (persistante)
  a11y      annoncés (live region), ne disparaissent pas avant 5 s, erreur avec action « Réessayer »

## MapPin et marqueurs
  variants  départ, arrivée, chauffeur (voiture orientée), position de l'utilisateur
  states    mouvement interpolé entre deux positions, perte de signal (estompé)
  a11y      la carte est décorative pour le lecteur d'écran ; l'état (distance, durée) est dans la feuille

## NotificationBadge
  variants  nombre, point
  a11y      « 2 notifications non lues »

## États vides, chargement, erreur (obligatoires pour chaque liste)
  historique vide, aucune offre (« Aucune offre pour l'instant : augmentez votre prix »), aucune demande à proximité (chauffeur), hors ligne, GPS refusé, zone non desservie, solde insuffisant.
  Chargement : squelettes à la forme des cartes, pas d'indicateur plein écran.

## Mouvement
  120 ms pour les retours d'état, 200 ms pour feuilles et cartes, `offer-timer` linéaire. Respecter « réduire les animations » : remplacer les glissements par des fondus et l'interpolation du marqueur par un saut.
