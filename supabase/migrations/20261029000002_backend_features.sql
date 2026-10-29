-- Migration 2 : ce qu'il faut côté serveur pour que l'app réelle fonctionne.
-- Inscription, inscription chauffeur, validation par un administrateur, suivi de position,
-- confidentialité des colonnes sensibles, suppression de compte, stockage privé des documents.

-- ---------------------------------------------------------------------------
-- Administrateur : rôle porté par app_metadata du JWT, posé uniquement par le serveur (service_role).
-- Jamais par user_metadata, que l'utilisateur peut modifier lui-même.
-- ---------------------------------------------------------------------------

create or replace function is_admin() returns boolean
language sql stable set search_path = public, extensions as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
$$;

-- ---------------------------------------------------------------------------
-- Profil créé à l'inscription
-- ---------------------------------------------------------------------------

-- Le profil anonymisé doit survivre à la suppression de l'identité (les courses et le journal financier le
-- référencent en `restrict`). On retire donc la clé étrangère vers auth.users ; `handle_new_user` crée le profil.
alter table profiles drop constraint profiles_id_fkey;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- comptes déjà présents avant la migration
insert into profiles (id) select id from auth.users on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Confidentialité des colonnes
-- Une contrepartie de course lit le profil du chauffeur : elle ne doit voir ni son solde,
-- ni sa priorité interne, ni le motif de rejet, ni la marge de la plateforme sur la course.
-- ---------------------------------------------------------------------------

revoke select on driver_profiles from authenticated;
grant select (user_id, zone_id, verification_status, online, location, location_updated_at,
              rating_avg, rating_count, completed_rides, created_at, updated_at)
  on driver_profiles to authenticated;

revoke select on rides from authenticated;
grant select (id, request_id, offer_id, rider_id, driver_id, vehicle_id, zone_id, agreed_price, final_price,
              status, driver_arrived_at, passenger_on_way_at, started_at, ended_at, cancelled_by, cancel_reason,
              created_at, updated_at)
  on rides to authenticated;

-- état privé du chauffeur : lui seul
create or replace function my_driver_state()
returns table (verification_status text, rejection_reason text, online boolean, balance bigint,
               zone_id uuid, priority_score int, commission_rate_bps int)
language sql stable security definer set search_path = public, extensions as $$
  select d.verification_status, d.rejection_reason, d.online, d.balance, d.zone_id, d.priority_score,
         case when d.verification_status = 'approved' then current_commission_bps(d.zone_id) end
  from driver_profiles d where d.user_id = auth.uid()
$$;

-- le taux n'est visible que d'un chauffeur vérifié (comme chez l'original)
create or replace function my_commission_rate() returns int
language plpgsql stable security definer set search_path = public, extensions as $$
declare d driver_profiles;
begin
  select * into d from driver_profiles where user_id = auth.uid();
  if not found or d.verification_status <> 'approved' then raise exception 'driver_not_approved' using errcode = '42501'; end if;
  return coalesce(current_commission_bps(d.zone_id), 0);
end $$;

create or replace function my_balance() returns bigint
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(sum(amount) filter (where status = 'posted'), 0)
  from wallet_entries where driver_id = auth.uid()
$$;

-- le chauffeur d'une course lit la demande liée (adresses, options) ; le passager la lisait déjà
create policy requests_read_driver on ride_requests for select to authenticated
  using (exists (select 1 from rides r where r.request_id = ride_requests.id and r.driver_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- Véhicules : la catégorie (Confort...) est attribuée par un administrateur, pas par le chauffeur
-- ---------------------------------------------------------------------------

create or replace function vehicles_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_course uuid;
begin
  if is_admin() or coalesce(auth.role(), '') = 'service_role' then return new; end if;
  select id into v_course from ride_categories where code = 'course';
  if tg_op = 'INSERT' then
    new.category_id := v_course;
  elsif new.category_id is distinct from old.category_id then
    new.category_id := old.category_id;
  end if;
  return new;
end $$;
create trigger vehicles_guard_trg before insert or update on vehicles
  for each row execute function vehicles_guard();

-- ---------------------------------------------------------------------------
-- Inscription chauffeur
-- ---------------------------------------------------------------------------

create or replace function become_driver(p_zone uuid) returns driver_profiles
language plpgsql security definer set search_path = public, extensions as $$
declare d driver_profiles;
begin
  perform assert_active();
  if not exists (select 1 from zones where id = p_zone and active) then raise exception 'zone_not_served'; end if;
  insert into driver_profiles (user_id, zone_id) values (auth.uid(), p_zone)
  on conflict (user_id) do nothing;
  select * into d from driver_profiles where user_id = auth.uid();
  return d;
end $$;

-- soumet le dossier : tous les documents requis (le plus récent de chaque type n'est pas rejeté) et un véhicule
create or replace function submit_driver_application() returns driver_profiles
language plpgsql security definer set search_path = public, extensions as $$
declare
  d driver_profiles;
  required text[] := array['id_card','licence','vehicle_registration','selfie','vehicle_photo'];
  t text;
begin
  perform assert_active();
  select * into d from driver_profiles where user_id = auth.uid() for update;
  if not found then raise exception 'not_a_driver'; end if;
  if d.verification_status not in ('draft','rejected') then raise exception 'application_not_editable'; end if;

  foreach t in array required loop
    if not exists (
      select 1 from (
        select distinct on (type) type, status from driver_documents
        where driver_id = auth.uid() order by type, created_at desc
      ) x where x.type = t and x.status <> 'rejected'
    ) then
      raise exception 'document_missing:%', t;
    end if;
  end loop;
  if not exists (select 1 from vehicles where driver_id = auth.uid() and active) then raise exception 'vehicle_missing'; end if;

  update driver_profiles set verification_status = 'pending', rejection_reason = null where user_id = auth.uid()
  returning * into d;
  return d;
end $$;

create or replace function admin_review_document(p_doc uuid, p_approve boolean, p_reason text default null)
returns driver_documents
language plpgsql security definer set search_path = public, extensions as $$
declare doc driver_documents;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if not p_approve and coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  update driver_documents set status = case when p_approve then 'approved' else 'rejected' end,
         rejection_reason = case when p_approve then null else p_reason end
   where id = p_doc returning * into doc;
  if not found then raise exception 'document_not_found'; end if;
  return doc;
end $$;

create or replace function admin_review_driver(p_driver uuid, p_approve boolean, p_reason text default null)
returns driver_profiles
language plpgsql security definer set search_path = public, extensions as $$
declare d driver_profiles;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if not p_approve and coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  select * into d from driver_profiles where user_id = p_driver for update;
  if not found then raise exception 'driver_not_found'; end if;
  if d.verification_status <> 'pending' then raise exception 'application_not_pending'; end if;
  if p_approve and exists (
    select 1 from (select distinct on (type) status from driver_documents where driver_id = p_driver order by type, created_at desc) x
    where x.status <> 'approved'
  ) then raise exception 'documents_not_all_approved'; end if;

  update driver_profiles
     set verification_status = case when p_approve then 'approved' else 'rejected' end,
         rejection_reason = case when p_approve then null else p_reason end,
         last_photo_check_at = case when p_approve then now() else last_photo_check_at end
   where user_id = p_driver returning * into d;

  insert into notifications (user_id, kind, title, body)
  values (p_driver, 'system',
          case when p_approve then 'Compte chauffeur validé' else 'Dossier à corriger' end,
          case when p_approve then 'Vous pouvez passer en ligne et recevoir des demandes.' else p_reason end);
  return d;
end $$;

-- ---------------------------------------------------------------------------
-- Suivi de position pendant une course
-- ---------------------------------------------------------------------------

create or replace function record_position(p_ride uuid, p_lng double precision, p_lat double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r rides; pt geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography; last_at timestamptz;
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'invalid_position'; end if;
  select * into r from rides where id = p_ride and driver_id = auth.uid() and status in ('to_pickup','arrived','in_progress');
  if not found then raise exception 'ride_not_active'; end if;
  update driver_profiles set location = pt, location_updated_at = now() where user_id = auth.uid();
  select max(recorded_at) into last_at from ride_positions where ride_id = p_ride;
  if last_at is not null and last_at > now() - interval '2 seconds' then return; end if;   -- limite de débit
  insert into ride_positions (ride_id, location) values (p_ride, pt);
end $$;

-- même limite pour la position hors course (attente de demandes)
create or replace function update_driver_location(p_lng double precision, p_lat double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'invalid_position'; end if;
  update driver_profiles
     set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, location_updated_at = now()
   where user_id = auth.uid()
     and (location_updated_at is null or location_updated_at < now() - interval '2 seconds');
end $$;

alter publication supabase_realtime add table ride_positions;

-- ---------------------------------------------------------------------------
-- Suppression de compte : on anonymise, on garde les courses et le journal financier (obligation comptable)
-- Appelée uniquement par l'Edge Function delete-account (service_role).
-- ---------------------------------------------------------------------------

create or replace function anonymize_account(p_user uuid) returns text[]
language plpgsql security definer set search_path = public, extensions as $$
declare paths text[];
begin
  if exists (select 1 from rides where (rider_id = p_user or driver_id = p_user) and status in ('to_pickup','arrived','in_progress')) then
    raise exception 'ride_active';
  end if;
  if exists (select 1 from ride_requests where rider_id = p_user and status = 'open') then
    update ride_requests set status = 'cancelled', cancel_reason = 'other' where rider_id = p_user and status = 'open';
  end if;
  if exists (select 1 from driver_profiles where user_id = p_user and balance > 0) then
    raise exception 'balance_not_zero';   -- à régler avec l'administrateur avant la suppression
  end if;

  select coalesce(array_agg(file_path), '{}') into paths from driver_documents where driver_id = p_user;
  paths := paths || coalesce((select array_agg(photo_path) from vehicles where driver_id = p_user and photo_path is not null), '{}');

  delete from ride_positions where ride_id in (select id from rides where rider_id = p_user or driver_id = p_user);
  delete from driver_documents where driver_id = p_user;
  delete from device_tokens where user_id = p_user;
  delete from saved_places where user_id = p_user;
  delete from emergency_contacts where user_id = p_user;
  delete from notifications where user_id = p_user;
  update vehicles set active = false, photo_path = null where driver_id = p_user;
  update driver_profiles set online = false, location = null where user_id = p_user;
  update profiles set full_name = null, avatar_url = null, status = 'blocked', deleted_at = now() where id = p_user;
  return paths;
end $$;

-- ---------------------------------------------------------------------------
-- Stockage privé des documents chauffeur (5 Mo, images seulement)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('driver-docs', 'driver-docs', false, 5242880, array['image/jpeg','image/png'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png'];

create policy driver_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy driver_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'driver-docs' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));

-- ---------------------------------------------------------------------------
-- Privilèges des fonctions ajoutées
-- ---------------------------------------------------------------------------

revoke all on function anonymize_account(uuid), handle_new_user(), vehicles_guard() from public, anon, authenticated;
grant execute on function anonymize_account(uuid) to service_role;
revoke all on function is_admin(), my_driver_state(), my_commission_rate(), my_balance(), become_driver(uuid),
  submit_driver_application(), admin_review_document(uuid, boolean, text), admin_review_driver(uuid, boolean, text),
  record_position(uuid, double precision, double precision), update_driver_location(double precision, double precision)
  from public, anon;
grant execute on function is_admin(), my_driver_state(), my_commission_rate(), my_balance(), become_driver(uuid),
  submit_driver_application(), admin_review_document(uuid, boolean, text), admin_review_driver(uuid, boolean, text),
  record_position(uuid, double precision, double precision), update_driver_location(double precision, double precision)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Zone d'un point : utilisée par les Edge Functions et par l'app
-- ---------------------------------------------------------------------------

create or replace function zone_for_point(p_lng double precision, p_lat double precision) returns uuid
language sql stable security definer set search_path = public, extensions as $$
  select id from zones where active and st_covers(geom, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) limit 1
$$;
revoke all on function zone_for_point(double precision, double precision) from public, anon;
grant execute on function zone_for_point(double precision, double precision) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Recharge du solde : appelée uniquement par psp-webhook (service_role), idempotente
-- ---------------------------------------------------------------------------

create or replace function credit_topup(p_provider text, p_event_id text, p_driver uuid, p_amount bigint,
                                        p_external_ref text, p_payload jsonb) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare ev payment_events;
begin
  if p_amount <= 0 or p_amount > 5000000 then raise exception 'invalid_amount'; end if;
  -- l'événement est enregistré d'abord : un second envoi échoue sur la contrainte et ne crédite pas deux fois
  insert into payment_events (provider, event_id, payload) values (p_provider, p_event_id, p_payload)
  on conflict (provider, event_id) do nothing returning * into ev;
  if ev.id is null then return 'duplicate'; end if;

  if not exists (select 1 from driver_profiles where user_id = p_driver) then
    update payment_events set processed_at = now() where id = ev.id;
    return 'unknown_driver';
  end if;
  insert into wallet_entries (driver_id, kind, amount, external_ref)
  values (p_driver, 'topup', p_amount, p_provider || ':' || p_external_ref)
  on conflict do nothing;
  update payment_events set processed_at = now() where id = ev.id;
  insert into notifications (user_id, kind, title, body)
  values (p_driver, 'wallet', 'Recharge reçue', 'Votre solde a été crédité.');
  return 'credited';
end $$;
revoke all on function credit_topup(text, text, uuid, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function credit_topup(text, text, uuid, bigint, text, jsonb) to service_role;
