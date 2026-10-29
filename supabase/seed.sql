-- Données de développement local. En production : insérer la vraie zone, le vrai taux et les vraies plages de trafic
-- (voir replica/backend.md). Aucune vraie personne ici : les comptes de test se créent par l'API (voir tests/).

-- Zone couvrant Abidjan et Bonoua (rectangle approximatif, à remplacer par le vrai contour de la zone desservie)
insert into zones (id, name, country_code, currency, timezone, geom, base_fare, price_per_km, min_fare)
values ('00000000-0000-0000-0000-0000000000f1', 'Abidjan et Bonoua', 'CI', 'XOF', 'Africa/Abidjan',
        st_geomfromtext('MULTIPOLYGON(((-4.35 5.10,-3.40 5.10,-3.40 5.62,-4.35 5.62,-4.35 5.10)))', 4326)::geography,
        500, 250, 1000)
on conflict (id) do nothing;

-- Taux de démonstration : le vrai taux est une décision commerciale (l'original ne le publie pas)
insert into commission_rates (zone_id, rate_bps)
select '00000000-0000-0000-0000-0000000000f1', 1000
where not exists (select 1 from commission_rates where zone_id = '00000000-0000-0000-0000-0000000000f1');

-- Plages de trafic : volontairement vides. Aucune mesure d'Abidjan n'existe encore (coefficient par défaut 1,00).
