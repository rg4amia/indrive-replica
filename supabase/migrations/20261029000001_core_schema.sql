-- Migration 1 : schéma de base. Dérivé de replica/schema.sql (testé sur PostGIS 16), adapté à Supabase.
-- Source de vérité : ce dossier supabase/migrations. replica/schema.sql reste le document de conception.
-- Les fonctions ne sont jamais exécutables par `anon` ni par défaut (voir les privilèges par défaut).

-- Aucune fonction exécutable par défaut : chaque fonction est ouverte explicitement aux rôles qui en ont besoin.
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------------
-- Utilitaires
-- ---------------------------------------------------------------------------

create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Paramètres métier (modifiables sans redéployer)
-- ---------------------------------------------------------------------------

create table app_settings (
  key         text primary key,
  value       jsonb not null,
  note        text,
  updated_at  timestamptz not null default now()
);

insert into app_settings (key, value, note) values
  ('driver_min_balance',          '0',     'solde minimum pour passer en ligne et faire une offre'),
  ('driver_cancel_priority_loss', '5',     'points de priorité perdus quand le chauffeur annule'),
  ('driver_cancel_refund',        'false', 'rembourser la commission si le chauffeur annule (sauf passager absent)'),
  ('refund_delay_hours',          '72',    'délai avant crédit d''un remboursement (source : 7 à 30 jours ouvrés)'),
  ('min_offer_pct_of_recommended','70',    'prix minimum proposé, en % du prix recommandé'),
  ('photo_check_every_days',      '30',    'fréquence de la vérification photo chauffeur'),
  ('position_keep_days',          '30',    'durée de conservation des positions GPS');

create table zones (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  country_code        text not null check (char_length(country_code) = 2),
  currency            text not null default 'XOF',
  timezone            text not null default 'Africa/Abidjan',
  geom                geography(MultiPolygon, 4326) not null,
  base_fare           int  not null check (base_fare >= 0),
  price_per_km        int  not null check (price_per_km >= 0),
  min_fare            int  not null check (min_fare >= 0),
  price_step          int  not null default 50 check (price_step > 0),
  raise_step          int  not null default 100 check (raise_step > 0),
  counter_band_pct    int  not null default 30 check (counter_band_pct between 0 and 100),
  search_radius_m     int  not null default 4000,
  request_ttl_seconds int  not null default 60,
  traffic_factor      numeric(4,2) not null default 1.00 check (traffic_factor between 0.5 and 5), -- multiplie la durée OSRM hors plages
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index zones_geom_idx on zones using gist (geom);
create trigger zones_touch before update on zones for each row execute function touch_updated_at();

-- OSRM ignore la circulation : plages horaires où la durée estimée est multipliée (heure locale de la zone)
create table zone_traffic (
  id          uuid primary key default gen_random_uuid(),
  zone_id     uuid not null references zones(id) on delete cascade,
  weekdays    int[] not null default '{1,2,3,4,5}' check (weekdays <@ array[0,1,2,3,4,5,6]),  -- 0 = dimanche
  start_hour  int  not null check (start_hour between 0 and 23),
  end_hour    int  not null check (end_hour between 1 and 24),                                  -- exclu ; 24 = minuit
  factor      numeric(4,2) not null check (factor between 0.5 and 5),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (end_hour > start_hour),
  check (cardinality(weekdays) > 0)
);
create index zone_traffic_zone_idx on zone_traffic (zone_id);
create trigger zone_traffic_touch before update on zone_traffic for each row execute function touch_updated_at();

create table commission_rates (
  id              uuid primary key default gen_random_uuid(),
  zone_id         uuid not null references zones(id) on delete cascade,
  rate_bps        int  not null check (rate_bps between 0 and 10000),  -- 1000 = 10 %
  effective_from  timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index commission_rates_zone_idx on commission_rates (zone_id, effective_from desc);
create trigger commission_rates_touch before update on commission_rates for each row execute function touch_updated_at();

create table ride_categories (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique check (code in ('course','confort','un_clic','ville_en_ville')),
  name              text not null,
  seats             int  not null default 4,
  price_multiplier  numeric(4,2) not null default 1.00,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create trigger ride_categories_touch before update on ride_categories for each row execute function touch_updated_at();

insert into ride_categories (code, name, seats, price_multiplier) values
  ('course',  'Course',  4, 1.00),
  ('confort', 'Confort', 4, 1.20),
  ('un_clic', 'Un Clic', 4, 1.10);

-- ---------------------------------------------------------------------------
-- Comptes
-- ---------------------------------------------------------------------------
-- Le téléphone reste dans auth.users, pas ici : la contrepartie d'une course ne doit
-- jamais le voir (numéro masqué).

create table profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  full_name           text,
  avatar_url          text,
  locale              text not null default 'fr',
  status              text not null default 'active' check (status in ('active','blocked')),
  rider_rating_avg    numeric(3,2) not null default 0,
  rider_rating_count  int not null default 0,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger profiles_touch before update on profiles for each row execute function touch_updated_at();

-- 1-1 avec profiles : la clé primaire est user_id (pas d'id propre).
create table driver_profiles (
  user_id               uuid primary key references profiles(id) on delete cascade,
  zone_id               uuid references zones(id) on delete restrict,
  verification_status   text not null default 'draft'
                        check (verification_status in ('draft','pending','approved','rejected')),
  rejection_reason      text,
  priority_score        int  not null default 100 check (priority_score between 0 and 200),
  online                boolean not null default false,
  location              geography(Point, 4326),
  location_updated_at   timestamptz,
  balance               bigint not null default 0,   -- cache de sum(wallet_entries posted)
  rating_avg            numeric(3,2) not null default 0,
  rating_count          int not null default 0,
  completed_rides       int not null default 0,
  last_photo_check_at   timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index driver_profiles_loc_idx on driver_profiles using gist (location) where online;
create index driver_profiles_zone_idx on driver_profiles (zone_id);
create trigger driver_profiles_touch before update on driver_profiles for each row execute function touch_updated_at();

create table vehicles (
  id           uuid primary key default gen_random_uuid(),
  driver_id    uuid not null references driver_profiles(user_id) on delete cascade,
  category_id  uuid not null references ride_categories(id) on delete restrict,
  make         text not null,
  model        text not null,
  year         int  check (year between 1990 and 2100),
  color        text,
  plate        text not null,
  seats        int  not null default 4 check (seats between 4 and 8),
  photo_path   text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index vehicles_plate_uq on vehicles (upper(plate));
create index vehicles_driver_idx on vehicles (driver_id);
create index vehicles_category_idx on vehicles (category_id);
create trigger vehicles_touch before update on vehicles for each row execute function touch_updated_at();

create table driver_documents (
  id               uuid primary key default gen_random_uuid(),
  driver_id        uuid not null references driver_profiles(user_id) on delete cascade,
  type             text not null check (type in ('id_card','licence','vehicle_registration','insurance','technical_inspection','selfie','vehicle_photo')),
  file_path        text not null,                 -- bucket privé driver-docs
  status           text not null default 'pending' check (status in ('pending','approved','rejected')),
  rejection_reason text,
  expires_at       date,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index driver_documents_driver_idx on driver_documents (driver_id, type);
create trigger driver_documents_touch before update on driver_documents for each row execute function touch_updated_at();

create table emergency_contacts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  name        text not null,
  phone       text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index emergency_contacts_user_idx on emergency_contacts (user_id);
create trigger emergency_contacts_touch before update on emergency_contacts for each row execute function touch_updated_at();

create table saved_places (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  label       text not null,
  address     text not null,
  location    geography(Point, 4326) not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index saved_places_user_idx on saved_places (user_id);
create trigger saved_places_touch before update on saved_places for each row execute function touch_updated_at();

create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  token       text not null unique,
  platform    text not null check (platform in ('ios','android')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index device_tokens_user_idx on device_tokens (user_id);
create trigger device_tokens_touch before update on device_tokens for each row execute function touch_updated_at();

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        text not null check (kind in ('safety','promo','ride','wallet','system')),
  title       text not null,
  body        text,
  data        jsonb not null default '{}',
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index notifications_user_idx on notifications (user_id, created_at desc);
create trigger notifications_touch before update on notifications for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Boucle principale : demande, offres, course
-- ---------------------------------------------------------------------------
-- Les comptes des passagers sont conservés (on delete restrict) : l'effacement RGPD
-- anonymise le profil, il ne supprime pas l'historique financier.

create table ride_requests (
  id                  uuid primary key default gen_random_uuid(),
  rider_id            uuid not null references profiles(id) on delete restrict,
  zone_id             uuid not null references zones(id) on delete restrict,
  category_id         uuid not null references ride_categories(id) on delete restrict,
  pickup              geography(Point, 4326) not null,
  pickup_address      text not null,
  pickup_hint         text,                      -- « Porte d'entrée »
  dropoff             geography(Point, 4326) not null,
  dropoff_address     text not null,
  stops               jsonb not null default '[]',
  distance_m          int  not null check (distance_m > 0),
  duration_s          int  not null check (duration_s > 0),
  recommended_price   int  not null check (recommended_price > 0),
  offered_price       int  not null check (offered_price > 0),
  price_raise_count   int  not null default 0,
  auto_accept         boolean not null default false,
  payment_method      text not null default 'cash' check (payment_method in ('cash','wallet','card','mobile_money')),
  options             jsonb not null default '{}',   -- {"extra_passengers":true,"child_seat":true}
  note                text,
  status              text not null default 'open' check (status in ('open','matched','cancelled','expired')),
  cancel_reason       text check (cancel_reason in ('drivers_too_far','price_too_high','accidental','wrong_location','no_offers','other')),
  expires_at          timestamptz not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
-- un seul ordre ouvert par passager
create unique index ride_requests_one_open_uq on ride_requests (rider_id) where status = 'open';
create index ride_requests_open_geo_idx on ride_requests using gist (pickup) where status = 'open';
create index ride_requests_rider_idx on ride_requests (rider_id, created_at desc);
create index ride_requests_expiry_idx on ride_requests (expires_at) where status = 'open';
create index ride_requests_zone_idx on ride_requests (zone_id);
create index ride_requests_category_idx on ride_requests (category_id);
create trigger ride_requests_touch before update on ride_requests for each row execute function touch_updated_at();

create table offers (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references ride_requests(id) on delete cascade,
  driver_id   uuid not null references driver_profiles(user_id) on delete restrict,
  vehicle_id  uuid not null references vehicles(id) on delete restrict,
  price       int  not null check (price > 0),
  eta_seconds int  not null check (eta_seconds >= 0),
  kind        text not null check (kind in ('accept','counter')),
  status      text not null default 'pending' check (status in ('pending','chosen','rejected','withdrawn','expired')),
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (request_id, driver_id)
);
create index offers_request_idx on offers (request_id, status);
create index offers_driver_idx on offers (driver_id, created_at desc);
create index offers_vehicle_idx on offers (vehicle_id);
create trigger offers_touch before update on offers for each row execute function touch_updated_at();

create table rides (
  id                      uuid primary key default gen_random_uuid(),
  request_id              uuid not null unique references ride_requests(id) on delete restrict,
  offer_id                uuid not null unique references offers(id) on delete restrict,
  rider_id                uuid not null references profiles(id) on delete restrict,
  driver_id               uuid not null references driver_profiles(user_id) on delete restrict,
  vehicle_id              uuid not null references vehicles(id) on delete restrict,
  zone_id                 uuid not null references zones(id) on delete restrict,
  agreed_price            int  not null check (agreed_price > 0),
  final_price             int  check (final_price > 0),
  commission_rate_bps     int  not null check (commission_rate_bps between 0 and 10000),
  commission              int  not null check (commission >= 0),
  status                  text not null default 'to_pickup'
                          check (status in ('to_pickup','arrived','in_progress','completed','cancelled')),
  driver_arrived_at       timestamptz,        -- « Je suis là » : déclenche la commission
  passenger_on_way_at     timestamptz,        -- le passager a signalé qu'il vient
  started_at              timestamptz,
  ended_at                timestamptz,
  cancelled_by            text check (cancelled_by in ('rider','driver','system')),
  cancel_reason           text check (cancel_reason in ('passenger_no_show','changed_mind','car_problem','too_far','wrong_location','other')),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint ended_after_start check (ended_at is null or started_at is null or ended_at >= started_at)
);
-- une course active par chauffeur et par passager (anti double-affectation)
create unique index rides_one_active_driver_uq on rides (driver_id) where status in ('to_pickup','arrived','in_progress');
create unique index rides_one_active_rider_uq  on rides (rider_id)  where status in ('to_pickup','arrived','in_progress');
create index rides_rider_hist_idx  on rides (rider_id, created_at desc);
create index rides_driver_hist_idx on rides (driver_id, created_at desc);
create index rides_vehicle_idx on rides (vehicle_id);
create index rides_zone_idx on rides (zone_id, ended_at);
create trigger rides_touch before update on rides for each row execute function touch_updated_at();

create table ride_positions (
  id           bigint generated always as identity primary key,
  ride_id      uuid not null references rides(id) on delete cascade,
  location     geography(Point, 4326) not null,
  recorded_at  timestamptz not null default now()
);
create index ride_positions_ride_idx on ride_positions (ride_id, recorded_at);

create table ratings (
  id            uuid primary key default gen_random_uuid(),
  ride_id       uuid not null references rides(id) on delete cascade,
  from_user_id  uuid not null references profiles(id) on delete restrict,
  to_user_id    uuid not null references profiles(id) on delete restrict,
  stars         int  not null check (stars between 1 and 5),
  comment       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (ride_id, from_user_id),
  check (from_user_id <> to_user_id)
);
create index ratings_to_idx on ratings (to_user_id, created_at desc);
create trigger ratings_touch before update on ratings for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Argent : journal du solde chauffeur (jamais modifié à la main)
-- ---------------------------------------------------------------------------

create table wallet_entries (
  id            uuid primary key default gen_random_uuid(),
  driver_id     uuid not null references driver_profiles(user_id) on delete restrict,
  kind          text not null check (kind in ('topup','commission','refund','penalty','adjustment')),
  amount        bigint not null check (amount <> 0),            -- signé : débit < 0, crédit > 0
  status        text not null default 'posted' check (status in ('pending','posted','failed')),
  ride_id       uuid references rides(id) on delete restrict,
  external_ref  text,                                            -- id du fournisseur de paiement
  available_at  timestamptz not null default now(),             -- remboursements différés
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (kind not in ('commission','refund') or ride_id is not null)
);
-- idempotence : une commission et un remboursement par course, un événement PSP une fois
create unique index wallet_one_per_ride_kind_uq on wallet_entries (ride_id, kind) where kind in ('commission','refund');
create unique index wallet_external_ref_uq on wallet_entries (external_ref) where external_ref is not null;
create index wallet_driver_idx on wallet_entries (driver_id, created_at desc);
create index wallet_pending_idx on wallet_entries (available_at) where status = 'pending';
create trigger wallet_entries_touch before update on wallet_entries for each row execute function touch_updated_at();

create table payments (
  id          uuid primary key default gen_random_uuid(),
  ride_id     uuid not null references rides(id) on delete restrict,
  method      text not null check (method in ('cash','wallet','card','mobile_money')),
  amount      int  not null check (amount > 0),
  status      text not null default 'paid' check (status in ('pending','paid','failed','refunded')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index payments_ride_idx on payments (ride_id);
create trigger payments_touch before update on payments for each row execute function touch_updated_at();

-- webhooks reçus deux fois : on garde l'événement avant de créditer
create table payment_events (
  id            uuid primary key default gen_random_uuid(),
  provider      text not null,
  event_id      text not null,
  payload       jsonb not null,
  processed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (provider, event_id)
);
create trigger payment_events_touch before update on payment_events for each row execute function touch_updated_at();

-- le solde en cache suit le journal
create or replace function apply_wallet_entry() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' and new.status = 'posted' then
    update driver_profiles set balance = balance + new.amount where user_id = new.driver_id;
  elsif tg_op = 'UPDATE' and old.status <> 'posted' and new.status = 'posted' then
    update driver_profiles set balance = balance + new.amount where user_id = new.driver_id;
  end if;
  return new;
end $$;
create trigger wallet_entries_balance after insert or update on wallet_entries
  for each row execute function apply_wallet_entry();

-- ---------------------------------------------------------------------------
-- Fonctions internes
-- ---------------------------------------------------------------------------

-- un compte suspendu ou supprimé ne peut plus commander, proposer ni passer en ligne
create or replace function assert_active() returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and status = 'active' and deleted_at is null) then
    raise exception 'account_blocked' using errcode = '42501';
  end if;
end $$;

create or replace function setting_int(p_key text) returns int
language sql stable as $$ select (value #>> '{}')::int from app_settings where key = p_key $$;

create or replace function setting_bool(p_key text) returns boolean
language sql stable as $$ select (value #>> '{}')::boolean from app_settings where key = p_key $$;

create or replace function current_commission_bps(p_zone uuid) returns int
language sql stable as $$
  select rate_bps from commission_rates
  where zone_id = p_zone and effective_from <= now()
  order by effective_from desc limit 1
$$;

-- coefficient de trafic applicable à un instant : plus forte valeur parmi les plages couvrantes, sinon le défaut de la zone
create or replace function traffic_factor_at(p_zone uuid, p_at timestamptz default now()) returns numeric
language sql stable set search_path = public, extensions as $$
  with z as (select traffic_factor, timezone from zones where id = p_zone),
       t as (select p_at at time zone z.timezone as local from z)
  select coalesce(
    (select max(zt.factor) from zone_traffic zt, t
      where zt.zone_id = p_zone
        and extract(dow from t.local)::int = any (zt.weekdays)
        and extract(hour from t.local)::int >= zt.start_hour
        and extract(hour from t.local)::int <  zt.end_hour),
    (select traffic_factor from z))
$$;

create or replace function adjusted_duration_s(p_zone uuid, p_osrm_seconds int, p_at timestamptz default now()) returns int
language sql stable set search_path = public, extensions as $$
  select round(p_osrm_seconds * traffic_factor_at(p_zone, p_at))::int
$$;

create or replace function recommended_price(p_zone uuid, p_category uuid, p_distance_m int) returns int
language sql stable as $$
  select (round(
           greatest(z.min_fare, z.base_fare + (p_distance_m / 1000.0) * z.price_per_km) * c.price_multiplier
           / z.price_step) * z.price_step)::int
  from zones z, ride_categories c
  where z.id = p_zone and c.id = p_category
$$;

create or replace function is_counterpart(p_user uuid) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from rides r
    where (r.rider_id = auth.uid() and r.driver_id = p_user)
       or (r.driver_id = auth.uid() and r.rider_id = p_user))
$$;

create or replace function owns_request(p_request uuid) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from ride_requests where id = p_request and rider_id = auth.uid())
$$;

-- commission : appelée par driver_arrived et par la fonction d'appel masqué (service role)
create or replace function _charge_commission(p_ride uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r rides;
begin
  select * into r from rides where id = p_ride;
  if not found or r.commission = 0 then return; end if;
  insert into wallet_entries (driver_id, kind, amount, ride_id)
  values (r.driver_id, 'commission', -r.commission, r.id)
  on conflict (ride_id, kind) where kind in ('commission','refund') do nothing;
end $$;

create or replace function _refund_commission(p_ride uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r rides; delay int := coalesce(setting_int('refund_delay_hours'), 72);
begin
  select * into r from rides where id = p_ride;
  if not exists (select 1 from wallet_entries where ride_id = p_ride and kind = 'commission') then return; end if;
  insert into wallet_entries (driver_id, kind, amount, status, ride_id, available_at)
  values (r.driver_id, 'refund', r.commission, 'pending', r.id, now() + make_interval(hours => delay))
  on conflict (ride_id, kind) where kind in ('commission','refund') do nothing;
end $$;

-- choix atomique de l'offre : verrouille la demande et l'offre, crée la course une seule fois
create or replace function _choose_offer(p_offer uuid, p_rider uuid) returns rides
language plpgsql security definer set search_path = public, extensions as $$
declare o offers; rq ride_requests; v_ride rides; bps int;
begin
  select * into o from offers where id = p_offer for update;
  if not found then raise exception 'offer_not_found'; end if;
  select * into rq from ride_requests where id = o.request_id for update;
  if rq.rider_id <> p_rider then raise exception 'forbidden' using errcode = '42501'; end if;
  if rq.status <> 'open' or o.status <> 'pending' then raise exception 'offer_not_available'; end if;

  bps := coalesce(current_commission_bps(rq.zone_id), 0);

  insert into rides (request_id, offer_id, rider_id, driver_id, vehicle_id, zone_id,
                     agreed_price, commission_rate_bps, commission)
  values (rq.id, o.id, rq.rider_id, o.driver_id, o.vehicle_id, rq.zone_id,
          o.price, bps, round(o.price * bps / 10000.0)::int)
  returning * into v_ride;      -- échoue si le chauffeur ou le passager a déjà une course active

  update ride_requests set status = 'matched' where id = rq.id;
  update offers set status = case when id = o.id then 'chosen' else 'rejected' end
   where request_id = rq.id and status = 'pending';

  insert into notifications (user_id, kind, title, data)
  values (o.driver_id, 'ride', 'Offre acceptée', jsonb_build_object('ride_id', v_ride.id));
  return v_ride;
end $$;

-- ---------------------------------------------------------------------------
-- API passager (appelée depuis Flutter via supabase.rpc)
-- ---------------------------------------------------------------------------

create or replace function create_ride_request(
  p_category uuid,
  p_pickup_lng double precision, p_pickup_lat double precision, p_pickup_address text, p_pickup_hint text,
  p_dropoff_lng double precision, p_dropoff_lat double precision, p_dropoff_address text,
  p_distance_m int, p_duration_s int, p_price int,
  p_payment_method text default 'cash', p_auto_accept boolean default false,
  p_options jsonb default '{}', p_note text default null
) returns ride_requests
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_pick geography := st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography;
  v_drop geography := st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography;
  z zones; v_dist int; v_rec int; v_req ride_requests;
begin
  perform assert_active();
  select * into z from zones where active and st_covers(geom, v_pick) limit 1;
  if not found then raise exception 'zone_not_served'; end if;

  -- la distance du client n'est jamais inférieure à la ligne droite calculée côté serveur
  v_dist := greatest(p_distance_m, st_distance(v_pick, v_drop)::int);
  v_rec  := recommended_price(z.id, p_category, v_dist);
  if p_price < v_rec * setting_int('min_offer_pct_of_recommended') / 100 then
    raise exception 'price_too_low';
  end if;

  begin
    insert into ride_requests (rider_id, zone_id, category_id, pickup, pickup_address, pickup_hint,
      dropoff, dropoff_address, distance_m, duration_s, recommended_price, offered_price,
      auto_accept, payment_method, options, note, expires_at)
    values (v_uid, z.id, p_category, v_pick, p_pickup_address, p_pickup_hint,
      v_drop, p_dropoff_address, v_dist, p_duration_s, v_rec, p_price,
      p_auto_accept, p_payment_method, p_options, p_note,
      now() + make_interval(secs => z.request_ttl_seconds))
    returning * into v_req;
  exception when unique_violation then
    raise exception 'request_already_open';
  end;
  return v_req;
end $$;

-- le passager augmente son prix pendant la recherche ; les acceptations à l'ancien prix sont invalidées
create or replace function raise_request_price(p_request uuid, p_steps int default 1) returns ride_requests
language plpgsql security definer set search_path = public, extensions as $$
declare rq ride_requests; step int;
begin
  select * into rq from ride_requests where id = p_request and rider_id = auth.uid() for update;
  if not found or rq.status <> 'open' then raise exception 'request_not_open'; end if;
  select raise_step into step from zones where id = rq.zone_id;
  update ride_requests
     set offered_price = offered_price + step * greatest(p_steps, 1),
         price_raise_count = price_raise_count + 1,
         expires_at = greatest(expires_at, now() + interval '30 seconds')
   where id = rq.id returning * into rq;
  update offers set status = 'expired'
   where request_id = rq.id and status = 'pending' and kind = 'accept' and price < rq.offered_price;
  return rq;
end $$;

create or replace function cancel_request(p_request uuid, p_reason text default 'other') returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests set status = 'cancelled', cancel_reason = p_reason
   where id = p_request and rider_id = auth.uid() and status = 'open';
  if not found then raise exception 'request_not_open'; end if;
  update offers set status = 'expired' where request_id = p_request and status = 'pending';
end $$;

create or replace function choose_offer(p_offer uuid) returns rides
language sql security definer set search_path = public, extensions as $$
  select * from _choose_offer(p_offer, auth.uid())
$$;

create or replace function reject_offer(p_offer uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update offers o set status = 'rejected'
   from ride_requests r
   where o.id = p_offer and r.id = o.request_id and r.rider_id = auth.uid() and o.status = 'pending';
end $$;

-- cartes d'offres pour le passager : infos chauffeur et voiture sans exposer les tables
create or replace function list_offers(p_request uuid)
returns table (offer_id uuid, price int, eta_seconds int, kind text, expires_at timestamptz,
               driver_id uuid, driver_name text, avatar_url text, rating_avg numeric,
               completed_rides int, priority_score int, vehicle_label text, plate text)
language sql stable security definer set search_path = public, extensions as $$
  select o.id, o.price, o.eta_seconds, o.kind, o.expires_at,
         d.user_id, p.full_name, p.avatar_url, d.rating_avg, d.completed_rides, d.priority_score,
         v.make || ' ' || v.model, v.plate
  from offers o
  join driver_profiles d on d.user_id = o.driver_id
  join profiles p on p.id = o.driver_id
  join vehicles v on v.id = o.vehicle_id
  where o.request_id = p_request and o.status = 'pending' and owns_request(p_request)
  order by o.price, o.eta_seconds
$$;

-- ---------------------------------------------------------------------------
-- API chauffeur
-- ---------------------------------------------------------------------------

create or replace function set_driver_online(p_online boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d driver_profiles;
begin
  perform assert_active();
  select * into d from driver_profiles where user_id = auth.uid() for update;
  if not found or d.verification_status <> 'approved' then raise exception 'driver_not_approved'; end if;
  if p_online and d.balance < coalesce(setting_int('driver_min_balance'), 0) then
    raise exception 'balance_too_low';
  end if;
  update driver_profiles set online = p_online where user_id = auth.uid();
end $$;

create or replace function update_driver_location(p_lng double precision, p_lat double precision) returns void
language sql security definer set search_path = public, extensions as $$
  update driver_profiles
     set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, location_updated_at = now()
   where user_id = auth.uid()
$$;

-- demandes ouvertes autour du chauffeur, avec les infos passager utiles à la décision
create or replace function nearby_open_requests()
returns table (request_id uuid, offered_price int, recommended_price int, pickup_address text,
               dropoff_address text, distance_m int, duration_s int, options jsonb, note text,
               pickup_distance_m int, expires_at timestamptz,
               rider_name text, rider_avatar text, rider_rating numeric, rider_rating_count int)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.offered_price, r.recommended_price, r.pickup_address, r.dropoff_address,
         r.distance_m, r.duration_s, r.options, r.note,
         st_distance(d.location, r.pickup)::int, r.expires_at,
         p.full_name, p.avatar_url, p.rider_rating_avg, p.rider_rating_count
  from driver_profiles d
  join zones z on z.id = d.zone_id
  join ride_requests r on r.zone_id = d.zone_id and r.status = 'open' and r.expires_at > now()
       and st_dwithin(d.location, r.pickup, z.search_radius_m)
  join profiles p on p.id = r.rider_id
  where d.user_id = auth.uid() and d.online and d.verification_status = 'approved'
  order by st_distance(d.location, r.pickup)
  limit 30
$$;

create or replace function submit_offer(p_request uuid, p_price int, p_eta_seconds int, p_vehicle uuid)
returns offers
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  d driver_profiles; rq ride_requests; z zones; v_kind text; v_offer offers;
begin
  perform assert_active();
  select * into d from driver_profiles where user_id = v_uid;
  if not found or d.verification_status <> 'approved' or not d.online then raise exception 'driver_not_ready'; end if;
  if d.balance < coalesce(setting_int('driver_min_balance'), 0) then raise exception 'balance_too_low'; end if;
  if not exists (select 1 from vehicles where id = p_vehicle and driver_id = v_uid and active) then
    raise exception 'vehicle_invalid';
  end if;

  select * into rq from ride_requests where id = p_request and status = 'open' and expires_at > now();
  if not found then raise exception 'request_not_open'; end if;
  select * into z from zones where id = rq.zone_id;
  if not st_dwithin(d.location, rq.pickup, z.search_radius_m) then raise exception 'too_far'; end if;

  -- une contre-offre est plus haute que l'offre du passager, dans la bande de la zone
  if p_price < rq.offered_price
     or p_price > rq.offered_price * (100 + z.counter_band_pct) / 100 then
    raise exception 'price_out_of_band';
  end if;
  v_kind := case when p_price = rq.offered_price then 'accept' else 'counter' end;

  insert into offers (request_id, driver_id, vehicle_id, price, eta_seconds, kind, expires_at)
  values (p_request, v_uid, p_vehicle, p_price, p_eta_seconds, v_kind, rq.expires_at)
  on conflict (request_id, driver_id) do update
     set price = excluded.price, eta_seconds = excluded.eta_seconds, kind = excluded.kind,
         vehicle_id = excluded.vehicle_id, status = 'pending', expires_at = excluded.expires_at
  returning * into v_offer;

  -- acceptation automatique : le premier chauffeur proche qui accepte le prix est choisi
  if rq.auto_accept and v_kind = 'accept' then
    perform _choose_offer(v_offer.id, rq.rider_id);
    select * into v_offer from offers where id = v_offer.id;
  end if;
  return v_offer;
end $$;

create or replace function withdraw_offer(p_offer uuid) returns void
language sql security definer set search_path = public, extensions as $$
  update offers set status = 'withdrawn' where id = p_offer and driver_id = auth.uid() and status = 'pending'
$$;

-- « Je suis là » : passe la course en arrivée et débite la commission
create or replace function driver_arrived(p_ride uuid) returns rides
language plpgsql security definer set search_path = public, extensions as $$
declare r rides;
begin
  update rides set status = 'arrived', driver_arrived_at = now()
   where id = p_ride and driver_id = auth.uid() and status = 'to_pickup'
   returning * into r;
  if not found then raise exception 'ride_not_in_pickup'; end if;
  perform _charge_commission(r.id);
  return r;
end $$;

create or replace function passenger_on_way(p_ride uuid) returns void
language sql security definer set search_path = public, extensions as $$
  update rides set passenger_on_way_at = now()
   where id = p_ride and rider_id = auth.uid() and status in ('to_pickup','arrived')
$$;

create or replace function start_ride(p_ride uuid) returns rides
language plpgsql security definer set search_path = public, extensions as $$
declare r rides;
begin
  update rides set status = 'in_progress', started_at = now()
   where id = p_ride and driver_id = auth.uid() and status = 'arrived' returning * into r;
  if not found then raise exception 'ride_not_arrived'; end if;
  return r;
end $$;

create or replace function complete_ride(p_ride uuid, p_final_price int default null) returns rides
language plpgsql security definer set search_path = public, extensions as $$
declare r rides;
begin
  update rides set status = 'completed', ended_at = now(), final_price = coalesce(p_final_price, agreed_price)
   where id = p_ride and driver_id = auth.uid() and status = 'in_progress' returning * into r;
  if not found then raise exception 'ride_not_in_progress'; end if;
  insert into payments (ride_id, method, amount)
  select r.id, rq.payment_method, r.final_price from ride_requests rq where rq.id = r.request_id;
  update driver_profiles set completed_rides = completed_rides + 1,
         priority_score = least(200, priority_score + 1) where user_id = r.driver_id;
  return r;
end $$;

-- annulation d'une course acceptée, par le passager ou le chauffeur
create or replace function cancel_ride(p_ride uuid, p_reason text default 'other') returns rides
language plpgsql security definer set search_path = public, extensions as $$
declare r rides; v_by text;
begin
  select * into r from rides where id = p_ride for update;
  if not found or auth.uid() not in (r.rider_id, r.driver_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if r.status not in ('to_pickup','arrived') then raise exception 'ride_not_cancellable'; end if;
  v_by := case when auth.uid() = r.rider_id then 'rider' else 'driver' end;

  update rides set status = 'cancelled', cancelled_by = v_by, cancel_reason = p_reason, ended_at = now()
   where id = r.id returning * into r;

  -- remboursement : passager absent, ou passager qui annule avant d'avoir signalé qu'il vient
  if (v_by = 'rider' and r.passenger_on_way_at is null)
     or (v_by = 'driver' and p_reason = 'passenger_no_show')
     or (v_by = 'driver' and coalesce(setting_bool('driver_cancel_refund'), false)) then
    perform _refund_commission(r.id);
  end if;
  if v_by = 'driver' and p_reason <> 'passenger_no_show' then
    update driver_profiles
       set priority_score = greatest(0, priority_score - coalesce(setting_int('driver_cancel_priority_loss'), 5))
     where user_id = r.driver_id;
  end if;
  return r;
end $$;

-- ---------------------------------------------------------------------------
-- Notes : moyennes recalculées par trigger
-- ---------------------------------------------------------------------------

create or replace function apply_rating() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from driver_profiles where user_id = new.to_user_id) then
    update driver_profiles d set
      rating_count = s.c, rating_avg = s.a
    from (select count(*) c, round(avg(stars), 2) a from ratings where to_user_id = new.to_user_id) s
    where d.user_id = new.to_user_id;
  else
    update profiles p set
      rider_rating_count = s.c, rider_rating_avg = s.a
    from (select count(*) c, round(avg(stars), 2) a from ratings where to_user_id = new.to_user_id) s
    where p.id = new.to_user_id;
  end if;
  return new;
end $$;
create trigger ratings_apply after insert or update on ratings for each row execute function apply_rating();

-- ---------------------------------------------------------------------------
-- Tâches planifiées
-- ---------------------------------------------------------------------------

create or replace function expire_requests() returns void
language sql security definer set search_path = public, extensions as $$
  update ride_requests set status = 'expired' where status = 'open' and expires_at < now();
  update offers set status = 'expired' where status = 'pending' and expires_at < now();
$$;

create or replace function settle_refunds() returns void
language sql security definer set search_path = public, extensions as $$
  update wallet_entries set status = 'posted'
   where kind = 'refund' and status = 'pending' and available_at <= now();
$$;

create or replace function purge_old_positions() returns void
language sql security definer set search_path = public, extensions as $$
  delete from ride_positions
   where recorded_at < now() - make_interval(days => coalesce(setting_int('position_keep_days'), 30));
$$;

-- contrôle quotidien : le solde en cache doit égaler la somme du journal
create or replace function balance_drift()
returns table (driver_id uuid, cached bigint, ledger bigint)
language sql stable security definer set search_path = public, extensions as $$
  select d.user_id, d.balance, coalesce(sum(w.amount) filter (where w.status = 'posted'), 0)
  from driver_profiles d left join wallet_entries w on w.driver_id = d.user_id
  group by d.user_id, d.balance
  having d.balance <> coalesce(sum(w.amount) filter (where w.status = 'posted'), 0)
$$;

select cron.schedule('expire-requests', '30 seconds', $$select expire_requests()$$);  -- pg_cron >= 1.5
select cron.schedule('settle-refunds',  '0 * * * *',  $$select settle_refunds()$$);
select cron.schedule('purge-positions', '15 3 * * *', $$select purge_old_positions()$$);

-- ---------------------------------------------------------------------------
-- Temps réel : seules les lignes utiles au passager sont publiées
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table offers, rides, ride_requests, notifications;

-- ---------------------------------------------------------------------------
-- Accès (RLS) : lecture seule pour le client, écriture via les fonctions ci-dessus
-- ---------------------------------------------------------------------------

alter table app_settings       enable row level security;
alter table zones              enable row level security;
alter table commission_rates   enable row level security;
alter table zone_traffic       enable row level security;
alter table ride_categories    enable row level security;
alter table profiles           enable row level security;
alter table driver_profiles    enable row level security;
alter table vehicles           enable row level security;
alter table driver_documents   enable row level security;
alter table emergency_contacts enable row level security;
alter table saved_places       enable row level security;
alter table device_tokens      enable row level security;
alter table notifications      enable row level security;
alter table ride_requests      enable row level security;
alter table offers             enable row level security;
alter table rides              enable row level security;
alter table ride_positions     enable row level security;
alter table ratings            enable row level security;
alter table wallet_entries     enable row level security;
alter table payments           enable row level security;
alter table payment_events     enable row level security;
-- app_settings, commission_rates (taux d'un chauffeur vérifié : via fonction dédiée),
-- payment_events : aucune policy = inaccessibles au client.

create policy zones_read      on zones           for select to authenticated using (active);
create policy traffic_read    on zone_traffic    for select to authenticated using (true);
create policy categories_read on ride_categories for select to authenticated using (active);

create policy profiles_read   on profiles for select to authenticated
  using (id = auth.uid() or is_counterpart(id));
create policy profiles_update on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy drivers_read on driver_profiles for select to authenticated
  using (user_id = auth.uid() or is_counterpart(user_id));

create policy vehicles_read  on vehicles for select to authenticated
  using (driver_id = auth.uid() or is_counterpart(driver_id));
create policy vehicles_write on vehicles for all to authenticated
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

create policy docs_read   on driver_documents for select to authenticated using (driver_id = auth.uid());
create policy docs_insert on driver_documents for insert to authenticated
  with check (driver_id = auth.uid() and status = 'pending');

create policy contacts_all on emergency_contacts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy places_all on saved_places for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy tokens_all on device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_read on notifications for select to authenticated using (user_id = auth.uid());
create policy notif_mark on notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy requests_read on ride_requests for select to authenticated using (rider_id = auth.uid());
create policy offers_read   on offers        for select to authenticated
  using (driver_id = auth.uid() or owns_request(request_id));
create policy rides_read    on rides         for select to authenticated
  using (rider_id = auth.uid() or driver_id = auth.uid());

create policy positions_read on ride_positions for select to authenticated
  using (exists (select 1 from rides r where r.id = ride_id and (r.rider_id = auth.uid() or r.driver_id = auth.uid())));

create policy ratings_read   on ratings for select to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid());
create policy ratings_insert on ratings for insert to authenticated
  with check (from_user_id = auth.uid() and exists (
    select 1 from rides r
    where r.id = ride_id and r.status = 'completed'
      and ((r.rider_id = auth.uid() and r.driver_id = to_user_id)
        or (r.driver_id = auth.uid() and r.rider_id = to_user_id))));

create policy wallet_read   on wallet_entries for select to authenticated using (driver_id = auth.uid());
create policy payments_read on payments for select to authenticated
  using (exists (select 1 from rides r where r.id = ride_id and (r.rider_id = auth.uid() or r.driver_id = auth.uid())));

-- privilèges de table : lecture seule côté client, écriture via les fonctions
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
revoke select on app_settings, commission_rates, payment_events from authenticated;
grant update (full_name, avatar_url, locale) on profiles to authenticated;
grant insert, update, delete on vehicles, emergency_contacts, saved_places, device_tokens to authenticated;
grant insert on driver_documents, ratings to authenticated;
grant update (read_at) on notifications to authenticated;

-- les fonctions « métier » sont ouvertes aux utilisateurs connectés, les fonctions internes non
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
  loop
    if f.proname in ('_choose_offer','_charge_commission','_refund_commission','expire_requests','settle_refunds',
                     'purge_old_positions','balance_drift','apply_wallet_entry','apply_rating','touch_updated_at') then
      execute format('revoke all on function %s from public, anon, authenticated', f.sig);
      execute format('grant execute on function %s to service_role', f.sig);
    else
      execute format('revoke all on function %s from public, anon', f.sig);
      execute format('grant execute on function %s to authenticated, service_role', f.sig);
    end if;
  end loop;
end $$;
