-- Johanna's Gartenwelt + Vokabeltrainer
-- Current-state bootstrap for a NEW Supabase project.
-- Generated from the verified production schema on 2026-09-24.
--
-- Purpose:
--   Recreate the current backend schema/security state without replaying the
--   historical migration chain. No user/application data is included.
--
-- Assumptions:
--   * Run as the Supabase project postgres/admin role.
--   * Supabase-managed schemas (auth, storage, extensions, etc.) exist.
--   * Edge Function source is deployed separately from supabase/functions/.
--
-- Historical audit trail lives in supabase/migrations/.
-- For recovery, use THIS bootstrap on a clean project, then deploy Edge Functions.

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Secure-by-default Data API boundary.
-- New public objects are not reachable by anon/authenticated/service_role unless
-- the migration that creates them grants the minimum required privileges explicitly.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public;

-- Defense in depth: automatically enable RLS for newly created public tables.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

drop event trigger if exists ensure_rls;
create event trigger ensure_rls
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();

-- Current Gartenwelt/shared backend baseline.
-- Johanna´s Gartenwelt – einmalige Supabase-Einrichtung
-- Diese Datei im Supabase SQL Editor vollständig ausführen.
-- Die eigentlichen privilegierten Funktionen liegen bewusst im nicht exponierten Schema "private".

create schema if not exists private;

create table if not exists private.jgw_gardens (
  garden_id text primary key,
  secret_hash text not null,
  payload jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint jgw_secret_hash_len check (length(secret_hash) = 60)
);

revoke all on table private.jgw_gardens from public, anon, authenticated;

-- Master-Zugriffsschlüssel nie direkt speichern: bestehende 64-stellige
-- Browser-Ableitungen einmalig mit bcrypt härten. Neue Gärten werden direkt so angelegt.
alter table private.jgw_gardens drop constraint if exists jgw_secret_hash_len;

update private.jgw_gardens
set secret_hash = extensions.crypt(lower(secret_hash), extensions.gen_salt('bf', 12))
where length(secret_hash) = 64
  and secret_hash ~ '^[0-9a-fA-F]{64}$';

-- Interne Funktionen: SECURITY DEFINER, aber im nicht exponierten private-Schema.
create or replace function private.jgw_create_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := lower(trim(p_garden_id));
  v_row private.jgw_gardens%rowtype;
begin
  if length(v_id) < 6 or length(v_id) > 80 then
    return jsonb_build_object('ok', false, 'error', 'invalid_garden_id');
  end if;
  if length(coalesce(p_secret_hash, '')) <> 64 or p_secret_hash !~ '^[0-9a-fA-F]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_secret');
  end if;
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  insert into private.jgw_gardens(garden_id, secret_hash, payload)
  values (
    v_id,
    extensions.crypt(lower(p_secret_hash), extensions.gen_salt('bf', 12)),
    coalesce(p_payload, '{}'::jsonb)
  )
  returning * into v_row;

  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'exists');
end;
$$;

create or replace function private.jgw_status_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

create or replace function private.jgw_pull_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at, 'payload', v_row.payload);
end;
$$;

create or replace function private.jgw_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb,
  p_base_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_current bigint;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
     and revision = p_base_revision
  returning * into v_row;

  if found then
    return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
  end if;

  select revision into v_current
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', false, 'conflict', true, 'revision', v_current);
end;
$$;

create or replace function private.jgw_force_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
  returning * into v_row;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

-- Öffentliche Wrapper ohne erhöhte Rechte. Die Data API sieht nur diese Funktionen.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

-- Interne Funktionen ebenfalls explizit absichern.
revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated;

-- Nur Browserrolle anon darf die Wrapper ausführen.
revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;


-- Automatischer Pflegekalender
-- Persönlicher, widerrufbarer Feed-Schlüssel. Der Kalender-Feed kennt weder Garten-PIN noch API-Schlüssel.
alter table private.jgw_gardens
  add column if not exists calendar_token text;

update private.jgw_gardens
set calendar_token = pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
where calendar_token is null;

alter table private.jgw_gardens
  alter column calendar_token set default pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'),
  alter column calendar_token set not null;

create unique index if not exists jgw_gardens_calendar_token_uq
  on private.jgw_gardens(calendar_token);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'jgw_calendar_token_len'
      and conrelid = 'private.jgw_gardens'::regclass
  ) then
    alter table private.jgw_gardens
      add constraint jgw_calendar_token_len check (length(calendar_token) = 64);
  end if;
end $$;

create or replace function private.jgw_get_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  select calendar_token into v_token
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_rotate_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
begin
  update private.jgw_gardens
     set calendar_token = v_token,
         updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_calendar_payload_impl(
  p_calendar_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_plants jsonb;
begin
  if length(coalesce(p_calendar_token, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  select * into v_row
  from private.jgw_gardens
  where calendar_token = p_calendar_token;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p->>'id',
      'name', p->>'name',
      'scientific', p->>'scientific',
      'family', case when jsonb_typeof(p->'family') = 'string' then p->>'family' else '' end,
      'type', coalesce(p->>'type', 'bed'),
      'quantity', coalesce(p->'quantity', '1'::jsonb),
      'area', p->>'area',
      'plantedSince', p->>'plantedSince',
      'transplanted', p->>'transplanted',
      'fertMonths', coalesce(p->'fertMonths', '[]'::jsonb),
      'cutMonths', coalesce(p->'cutMonths', '[]'::jsonb)
    )
  ), '[]'::jsonb)
  into v_plants
  from jsonb_array_elements(coalesce(v_row.payload->'plants', '[]'::jsonb)) p;

  return jsonb_build_object(
    'ok', true,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at,
    'plants', v_plants,
    'ecology', jsonb_build_object(
      'leaveStemsInWinter', coalesce((v_row.payload #>> '{ecology,practice,leaveStemsInWinter}')::boolean, false),
      'leavesPartlyRemain', coalesce((v_row.payload #>> '{ecology,practice,leavesPartlyRemain}')::boolean, false)
    )
  );
end;
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated;

revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;


-- Sicherheits-Härtung: RLS + minimale RPC-Grenze
-- Die Tabelle bleibt in einem nicht exponierten Schema und hat keine direkten
-- Browser-Rechte. RLS ergänzt eine ausdrückliche zweite Schutzschicht.
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

drop policy if exists jgw_no_direct_access on private.jgw_gardens;
create policy jgw_no_direct_access
on private.jgw_gardens
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Öffentliche RPC-Wrapper bleiben SECURITY INVOKER.
-- Sie delegieren ausschließlich an die geprüften SECURITY-DEFINER-Implementierungen
-- im privaten Schema. Der leere search_path verhindert Namensauflösungs-Hijacking.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

-- anon darf das private Schema nur so weit betreten, wie es für die Delegation
-- an die internen Funktionen nötig ist. Direkte Tabellenrechte bleiben entzogen.
grant usage on schema private to anon;
revoke usage on schema private from public, authenticated, service_role;

grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, authenticated, service_role;

revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated, service_role;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;
;

alter table private.jgw_gardens
  add constraint jgw_secret_hash_len check (length(secret_hash) = 60);

-- Interne Funktionen: SECURITY DEFINER, aber im nicht exponierten private-Schema.
create or replace function private.jgw_create_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := lower(trim(p_garden_id));
  v_row private.jgw_gardens%rowtype;
begin
  if length(v_id) < 6 or length(v_id) > 80 then
    return jsonb_build_object('ok', false, 'error', 'invalid_garden_id');
  end if;
  if length(coalesce(p_secret_hash, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_secret');
  end if;
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  insert into private.jgw_gardens(garden_id, secret_hash, payload)
  values (v_id, p_secret_hash, coalesce(p_payload, '{}'::jsonb))
  returning * into v_row;

  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'exists');
end;
$$;

create or replace function private.jgw_status_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

create or replace function private.jgw_pull_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at, 'payload', v_row.payload);
end;
$$;

create or replace function private.jgw_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb,
  p_base_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_current bigint;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
     and revision = p_base_revision
  returning * into v_row;

  if found then
    return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
  end if;

  select revision into v_current
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', false, 'conflict', true, 'revision', v_current);
end;
$$;

create or replace function private.jgw_force_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
  returning * into v_row;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

-- Öffentliche Wrapper ohne erhöhte Rechte. Die Data API sieht nur diese Funktionen.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

-- Interne Funktionen ebenfalls explizit absichern.
revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated;

-- Nur Browserrolle anon darf die Wrapper ausführen.
revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;


-- Automatischer Pflegekalender
-- Persönlicher, widerrufbarer Feed-Schlüssel. Der Kalender-Feed kennt weder Garten-PIN noch API-Schlüssel.
alter table private.jgw_gardens
  add column if not exists calendar_token text;

update private.jgw_gardens
set calendar_token = pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
where calendar_token is null;

alter table private.jgw_gardens
  alter column calendar_token set default pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'),
  alter column calendar_token set not null;

create unique index if not exists jgw_gardens_calendar_token_uq
  on private.jgw_gardens(calendar_token);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'jgw_calendar_token_len'
      and conrelid = 'private.jgw_gardens'::regclass
  ) then
    alter table private.jgw_gardens
      add constraint jgw_calendar_token_len check (length(calendar_token) = 64);
  end if;
end $$;

create or replace function private.jgw_get_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  select calendar_token into v_token
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_rotate_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
begin
  update private.jgw_gardens
     set calendar_token = v_token,
         updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_calendar_payload_impl(
  p_calendar_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_plants jsonb;
begin
  if length(coalesce(p_calendar_token, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  select * into v_row
  from private.jgw_gardens
  where calendar_token = p_calendar_token;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p->>'id',
      'name', p->>'name',
      'scientific', p->>'scientific',
      'family', case when jsonb_typeof(p->'family') = 'string' then p->>'family' else '' end,
      'type', coalesce(p->>'type', 'bed'),
      'quantity', coalesce(p->'quantity', '1'::jsonb),
      'area', p->>'area',
      'plantedSince', p->>'plantedSince',
      'transplanted', p->>'transplanted',
      'fertMonths', coalesce(p->'fertMonths', '[]'::jsonb),
      'cutMonths', coalesce(p->'cutMonths', '[]'::jsonb)
    )
  ), '[]'::jsonb)
  into v_plants
  from jsonb_array_elements(coalesce(v_row.payload->'plants', '[]'::jsonb)) p;

  return jsonb_build_object(
    'ok', true,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at,
    'plants', v_plants,
    'ecology', jsonb_build_object(
      'leaveStemsInWinter', coalesce((v_row.payload #>> '{ecology,practice,leaveStemsInWinter}')::boolean, false),
      'leavesPartlyRemain', coalesce((v_row.payload #>> '{ecology,practice,leavesPartlyRemain}')::boolean, false)
    )
  );
end;
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated;

revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;


-- Sicherheits-Härtung: RLS + minimale RPC-Grenze
-- Die Tabelle bleibt in einem nicht exponierten Schema und hat keine direkten
-- Browser-Rechte. RLS ergänzt eine ausdrückliche zweite Schutzschicht.
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

drop policy if exists jgw_no_direct_access on private.jgw_gardens;
create policy jgw_no_direct_access
on private.jgw_gardens
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Öffentliche RPC-Wrapper bleiben SECURITY INVOKER.
-- Sie delegieren ausschließlich an die geprüften SECURITY-DEFINER-Implementierungen
-- im privaten Schema. Der leere search_path verhindert Namensauflösungs-Hijacking.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

-- anon darf das private Schema nur so weit betreten, wie es für die Delegation
-- an die internen Funktionen nötig ist. Direkte Tabellenrechte bleiben entzogen.
grant usage on schema private to anon;
revoke usage on schema private from public, authenticated, service_role;

grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, authenticated, service_role;

revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated, service_role;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;
 then
    return jsonb_build_object('ok', false, 'error', 'invalid_secret');
  end if;
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  insert into private.jgw_gardens(garden_id, secret_hash, payload)
  values (v_id, p_secret_hash, coalesce(p_payload, '{}'::jsonb))
  returning * into v_row;

  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'exists');
end;
$$;

create or replace function private.jgw_status_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

create or replace function private.jgw_pull_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at, 'payload', v_row.payload);
end;
$$;

create or replace function private.jgw_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb,
  p_base_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_current bigint;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
     and revision = p_base_revision
  returning * into v_row;

  if found then
    return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
  end if;

  select revision into v_current
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', false, 'conflict', true, 'revision', v_current);
end;
$$;

create or replace function private.jgw_force_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
  returning * into v_row;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

-- Öffentliche Wrapper ohne erhöhte Rechte. Die Data API sieht nur diese Funktionen.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

-- Interne Funktionen ebenfalls explizit absichern.
revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated;

-- Nur Browserrolle anon darf die Wrapper ausführen.
revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;


-- Automatischer Pflegekalender
-- Persönlicher, widerrufbarer Feed-Schlüssel. Der Kalender-Feed kennt weder Garten-PIN noch API-Schlüssel.
alter table private.jgw_gardens
  add column if not exists calendar_token text;

update private.jgw_gardens
set calendar_token = pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
where calendar_token is null;

alter table private.jgw_gardens
  alter column calendar_token set default pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'),
  alter column calendar_token set not null;

create unique index if not exists jgw_gardens_calendar_token_uq
  on private.jgw_gardens(calendar_token);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'jgw_calendar_token_len'
      and conrelid = 'private.jgw_gardens'::regclass
  ) then
    alter table private.jgw_gardens
      add constraint jgw_calendar_token_len check (length(calendar_token) = 64);
  end if;
end $$;

create or replace function private.jgw_get_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  select calendar_token into v_token
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_rotate_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
begin
  update private.jgw_gardens
     set calendar_token = v_token,
         updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_calendar_payload_impl(
  p_calendar_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_plants jsonb;
begin
  if length(coalesce(p_calendar_token, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  select * into v_row
  from private.jgw_gardens
  where calendar_token = p_calendar_token;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p->>'id',
      'name', p->>'name',
      'scientific', p->>'scientific',
      'family', case when jsonb_typeof(p->'family') = 'string' then p->>'family' else '' end,
      'type', coalesce(p->>'type', 'bed'),
      'quantity', coalesce(p->'quantity', '1'::jsonb),
      'area', p->>'area',
      'plantedSince', p->>'plantedSince',
      'transplanted', p->>'transplanted',
      'fertMonths', coalesce(p->'fertMonths', '[]'::jsonb),
      'cutMonths', coalesce(p->'cutMonths', '[]'::jsonb)
    )
  ), '[]'::jsonb)
  into v_plants
  from jsonb_array_elements(coalesce(v_row.payload->'plants', '[]'::jsonb)) p;

  return jsonb_build_object(
    'ok', true,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at,
    'plants', v_plants,
    'ecology', jsonb_build_object(
      'leaveStemsInWinter', coalesce((v_row.payload #>> '{ecology,practice,leaveStemsInWinter}')::boolean, false),
      'leavesPartlyRemain', coalesce((v_row.payload #>> '{ecology,practice,leavesPartlyRemain}')::boolean, false)
    )
  );
end;
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated;

revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;


-- Sicherheits-Härtung: RLS + minimale RPC-Grenze
-- Die Tabelle bleibt in einem nicht exponierten Schema und hat keine direkten
-- Browser-Rechte. RLS ergänzt eine ausdrückliche zweite Schutzschicht.
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

drop policy if exists jgw_no_direct_access on private.jgw_gardens;
create policy jgw_no_direct_access
on private.jgw_gardens
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Öffentliche RPC-Wrapper bleiben SECURITY INVOKER.
-- Sie delegieren ausschließlich an die geprüften SECURITY-DEFINER-Implementierungen
-- im privaten Schema. Der leere search_path verhindert Namensauflösungs-Hijacking.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

-- anon darf das private Schema nur so weit betreten, wie es für die Delegation
-- an die internen Funktionen nötig ist. Direkte Tabellenrechte bleiben entzogen.
grant usage on schema private to anon;
revoke usage on schema private from public, authenticated, service_role;

grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, authenticated, service_role;

revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated, service_role;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;
;

alter table private.jgw_gardens
  add constraint jgw_secret_hash_len check (length(secret_hash) = 60);

-- Interne Funktionen: SECURITY DEFINER, aber im nicht exponierten private-Schema.
create or replace function private.jgw_create_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := lower(trim(p_garden_id));
  v_row private.jgw_gardens%rowtype;
begin
  if length(v_id) < 6 or length(v_id) > 80 then
    return jsonb_build_object('ok', false, 'error', 'invalid_garden_id');
  end if;
  if length(coalesce(p_secret_hash, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_secret');
  end if;
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  insert into private.jgw_gardens(garden_id, secret_hash, payload)
  values (v_id, p_secret_hash, coalesce(p_payload, '{}'::jsonb))
  returning * into v_row;

  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'exists');
end;
$$;

create or replace function private.jgw_status_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

create or replace function private.jgw_pull_garden_impl(p_garden_id text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  select * into v_row
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at, 'payload', v_row.payload);
end;
$$;

create or replace function private.jgw_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb,
  p_base_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_current bigint;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
     and revision = p_base_revision
  returning * into v_row;

  if found then
    return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
  end if;

  select revision into v_current
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', false, 'conflict', true, 'revision', v_current);
end;
$$;

create or replace function private.jgw_force_push_garden_impl(
  p_garden_id text,
  p_secret_hash text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
begin
  if pg_column_size(coalesce(p_payload, '{}'::jsonb)) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
  end if;

  update private.jgw_gardens
     set payload = coalesce(p_payload, '{}'::jsonb), revision = revision + 1, updated_at = now()
   where garden_id = lower(trim(p_garden_id)) and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
  returning * into v_row;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

-- Öffentliche Wrapper ohne erhöhte Rechte. Die Data API sieht nur diese Funktionen.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

-- Interne Funktionen ebenfalls explizit absichern.
revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated;

-- Nur Browserrolle anon darf die Wrapper ausführen.
revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;


-- Automatischer Pflegekalender
-- Persönlicher, widerrufbarer Feed-Schlüssel. Der Kalender-Feed kennt weder Garten-PIN noch API-Schlüssel.
alter table private.jgw_gardens
  add column if not exists calendar_token text;

update private.jgw_gardens
set calendar_token = pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
where calendar_token is null;

alter table private.jgw_gardens
  alter column calendar_token set default pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'),
  alter column calendar_token set not null;

create unique index if not exists jgw_gardens_calendar_token_uq
  on private.jgw_gardens(calendar_token);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'jgw_calendar_token_len'
      and conrelid = 'private.jgw_gardens'::regclass
  ) then
    alter table private.jgw_gardens
      add constraint jgw_calendar_token_len check (length(calendar_token) = 64);
  end if;
end $$;

create or replace function private.jgw_get_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  select calendar_token into v_token
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_rotate_calendar_token_impl(
  p_garden_id text,
  p_secret_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
begin
  update private.jgw_gardens
     set calendar_token = v_token,
         updated_at = now()
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'calendar_token', v_token);
end;
$$;

create or replace function private.jgw_calendar_payload_impl(
  p_calendar_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.jgw_gardens%rowtype;
  v_plants jsonb;
begin
  if length(coalesce(p_calendar_token, '')) <> 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  select * into v_row
  from private.jgw_gardens
  where calendar_token = p_calendar_token;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p->>'id',
      'name', p->>'name',
      'scientific', p->>'scientific',
      'family', case when jsonb_typeof(p->'family') = 'string' then p->>'family' else '' end,
      'type', coalesce(p->>'type', 'bed'),
      'quantity', coalesce(p->'quantity', '1'::jsonb),
      'area', p->>'area',
      'plantedSince', p->>'plantedSince',
      'transplanted', p->>'transplanted',
      'fertMonths', coalesce(p->'fertMonths', '[]'::jsonb),
      'cutMonths', coalesce(p->'cutMonths', '[]'::jsonb)
    )
  ), '[]'::jsonb)
  into v_plants
  from jsonb_array_elements(coalesce(v_row.payload->'plants', '[]'::jsonb)) p;

  return jsonb_build_object(
    'ok', true,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at,
    'plants', v_plants,
    'ecology', jsonb_build_object(
      'leaveStemsInWinter', coalesce((v_row.payload #>> '{ecology,practice,leaveStemsInWinter}')::boolean, false),
      'leavesPartlyRemain', coalesce((v_row.payload #>> '{ecology,practice,leavesPartlyRemain}')::boolean, false)
    )
  );
end;
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated;

revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated;

grant usage on schema private to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;


-- Sicherheits-Härtung: RLS + minimale RPC-Grenze
-- Die Tabelle bleibt in einem nicht exponierten Schema und hat keine direkten
-- Browser-Rechte. RLS ergänzt eine ausdrückliche zweite Schutzschicht.
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

drop policy if exists jgw_no_direct_access on private.jgw_gardens;
create policy jgw_no_direct_access
on private.jgw_gardens
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Öffentliche RPC-Wrapper bleiben SECURITY INVOKER.
-- Sie delegieren ausschließlich an die geprüften SECURITY-DEFINER-Implementierungen
-- im privaten Schema. Der leere search_path verhindert Namensauflösungs-Hijacking.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

-- anon darf das private Schema nur so weit betreten, wie es für die Delegation
-- an die internen Funktionen nötig ist. Direkte Tabellenrechte bleiben entzogen.
grant usage on schema private to anon;
revoke usage on schema private from public, authenticated, service_role;

grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, authenticated, service_role;

revoke execute on function public.jgw_create_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_status_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_pull_garden(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_push_garden(text,text,jsonb,bigint) from public, authenticated, service_role;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from public, authenticated, service_role;
revoke execute on function public.jgw_get_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_rotate_calendar_token(text,text) from public, authenticated, service_role;
revoke execute on function public.jgw_calendar_payload(text) from public, authenticated, service_role;

grant execute on function public.jgw_create_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_status_garden(text,text) to anon;
grant execute on function public.jgw_pull_garden(text,text) to anon;
grant execute on function public.jgw_push_garden(text,text,jsonb,bigint) to anon;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to anon;
grant execute on function public.jgw_get_calendar_token(text,text) to anon;
grant execute on function public.jgw_rotate_calendar_token(text,text) to anon;
grant execute on function public.jgw_calendar_payload(text) to anon;


-- Sicherheits-Härtung: gemeinsames RPC-Rate-Limit
-- Schützt JGW- und Vokabeltrainer-RPCs vor automatisierten Fehlversuchen und Massenaufrufen.
-- Kalenderfeed wird bewusst nicht limitiert, da er über die Edge Function läuft.
create table if not exists private.jgw_rate_limits (
  id bigint generated by default as identity primary key,
  ip inet not null,
  scope text not null,
  requested_at timestamptz not null default now()
);

alter table private.jgw_rate_limits
  add column if not exists id bigint generated by default as identity;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace n on n.oid=t.relnamespace
    where n.nspname='private'
      and t.relname='jgw_rate_limits'
      and c.contype='p'
  ) then
    alter table private.jgw_rate_limits
      add constraint jgw_rate_limits_pkey primary key (id);
  end if;
end
$$;

alter table private.jgw_rate_limits enable row level security;

create index if not exists jgw_rate_limits_scope_ip_requested_at_idx
  on private.jgw_rate_limits(scope, ip, requested_at desc);

create index if not exists jgw_rate_limits_requested_at_idx
  on private.jgw_rate_limits(requested_at);

revoke all on table private.jgw_rate_limits from public, anon, authenticated, service_role;

create or replace function private.jgw_pre_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text := pg_catalog.current_setting('request.method', true);
  v_path text := pg_catalog.current_setting('request.path', true);
  v_headers_text text := pg_catalog.current_setting('request.headers', true);
  v_ip_text text;
  v_ip inet;
  v_scope text;
  v_limit integer;
  v_window interval;
  v_count integer;
  v_error_code text := 'api_rate_limit';
begin
  if v_method is null or v_method not in ('POST','PUT','PATCH','DELETE') then
    return;
  end if;

  v_path := pg_catalog.regexp_replace(coalesce(v_path,''), '^/', '');

  if v_path = 'rpc/jgw_create_garden' then
    v_scope := 'jgw_create';
    v_limit := 10;
    v_window := interval '1 hour';
    v_error_code := 'jgw_rate_limit';
  elsif v_path in (
    'rpc/jgw_status_garden',
    'rpc/jgw_pull_garden',
    'rpc/jgw_push_garden',
    'rpc/jgw_force_push_garden',
    'rpc/jgw_get_calendar_token',
    'rpc/jgw_rotate_calendar_token'
  ) then
    v_scope := 'jgw_sync_auth';
    v_limit := 60;
    v_window := interval '5 minutes';
    v_error_code := 'jgw_rate_limit';
  elsif v_path = 'rpc/vt_create_family' then
    v_scope := 'vt_create_family';
    v_limit := 10;
    v_window := interval '1 hour';
    v_error_code := 'vt_rate_limit';
  elsif v_path = 'rpc/vt_join_parent' then
    v_scope := 'vt_join_parent';
    v_limit := 12;
    v_window := interval '15 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path = 'rpc/vt_claim_child_invite' then
    v_scope := 'vt_claim_child';
    v_limit := 30;
    v_window := interval '15 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path in (
    'rpc/vt_create_child_invite',
    'rpc/vt_list_devices',
    'rpc/vt_revoke_device'
  ) then
    v_scope := 'vt_device_admin';
    v_limit := 60;
    v_window := interval '5 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path in (
    'rpc/vt_pull_documents',
    'rpc/vt_push_document',
    'rpc/vt_status_documents'
  ) then
    v_scope := 'vt_sync';
    v_limit := 180;
    v_window := interval '5 minutes';
    v_error_code := 'vt_rate_limit';
  else
    return;
  end if;

  if v_headers_text is null or v_headers_text = '' then
    return;
  end if;

  begin
    v_ip_text := pg_catalog.btrim(
      pg_catalog.split_part((v_headers_text::jsonb)->>'x-forwarded-for', ',', 1)
    );
    if v_ip_text is null or v_ip_text = '' then return; end if;
    v_ip := v_ip_text::inet;
  exception when others then
    return;
  end;

  delete from private.jgw_rate_limits
   where requested_at < pg_catalog.now() - interval '24 hours';

  select pg_catalog.count(*)::integer
    into v_count
    from private.jgw_rate_limits
   where scope = v_scope
     and ip = v_ip
     and requested_at >= pg_catalog.now() - v_window;

  if v_count >= v_limit then
    raise sqlstate 'PGRST'
      using message = jsonb_build_object(
        'code',v_error_code,
        'message','Zu viele Anfragen. Bitte kurz warten und erneut versuchen.'
      )::text,
      detail = jsonb_build_object(
        'status',429,
        'status_text','Too Many Requests'
      )::text;
  end if;

  insert into private.jgw_rate_limits(ip, scope, requested_at)
  values (v_ip, v_scope, pg_catalog.now());
end;
$$;

revoke execute on function private.jgw_pre_request() from public;
grant usage on schema private to anon, authenticated, service_role;
grant execute on function private.jgw_pre_request() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request = 'private.jgw_pre_request';

notify pgrst, 'reload config';


-- Current Vokabeltrainer Family Sync schema and RPC boundary.

create schema if not exists private;

create table if not exists private.vt_families (
  family_id text primary key,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vt_family_id_format check (family_id ~ '^[a-z0-9_-]{6,80}$')
);
alter table private.vt_families enable row level security;

create table if not exists private.vt_devices (
  family_id text not null references private.vt_families(family_id) on delete cascade,
  device_id text not null,
  device_secret_hash text not null,
  role text not null check (role in ('parent','child')),
  profile_id text,
  label text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (family_id, device_id),
  constraint vt_device_id_format check (device_id ~ '^[A-Za-z0-9_-]{8,120}$'),
  constraint vt_child_profile_required check ((role='parent' and profile_id is null) or (role='child' and profile_id is not null))
);
alter table private.vt_devices enable row level security;

create table if not exists private.vt_documents (
  family_id text not null references private.vt_families(family_id) on delete cascade,
  doc_key text not null,
  revision bigint not null default 1 check (revision > 0),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (family_id, doc_key),
  constraint vt_doc_key_format check (
    doc_key='shared'
    or doc_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$'
  )
);
alter table private.vt_documents enable row level security;

create table if not exists private.vt_invites (
  token_hash text primary key,
  family_id text not null references private.vt_families(family_id) on delete cascade,
  profile_id text not null,
  created_by_device_id text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  constraint vt_invite_token_hash_format check (token_hash ~ '^[0-9a-f]{64}$')
);
alter table private.vt_invites enable row level security;

revoke all on private.vt_families, private.vt_devices, private.vt_documents, private.vt_invites from public, anon, authenticated;

create or replace function private.vt_device_context(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
  v_device private.vt_devices%rowtype;
begin
  select * into v_device
  from private.vt_devices
  where family_id=v_family
    and device_id=trim(coalesce(p_device_id,''))
    and active=true
    and device_secret_hash=extensions.crypt(coalesce(p_device_secret,''),device_secret_hash);

  if not found then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;

  update private.vt_devices
     set last_seen_at=now()
   where family_id=v_family and device_id=v_device.device_id;

  return jsonb_build_object(
    'ok',true,
    'family_id',v_family,
    'device_id',v_device.device_id,
    'role',v_device.role,
    'profile_id',v_device.profile_id
  );
end;
$$;

create or replace function private.vt_create_family_impl(
  p_family_id text,
  p_family_secret_hash text,
  p_device_id text,
  p_device_secret text,
  p_label text,
  p_documents jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
  v_key text;
  v_payload jsonb;
begin
  if v_family !~ '^[a-z0-9_-]{6,80}$' then
    return jsonb_build_object('ok',false,'error','invalid_family_id');
  end if;
  if length(coalesce(p_family_secret_hash,''))<>64 or p_family_secret_hash !~ '^[0-9a-fA-F]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_family_secret');
  end if;
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$' then
    return jsonb_build_object('ok',false,'error','invalid_device_id');
  end if;
  if length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device_secret');
  end if;
  if jsonb_typeof(coalesce(p_documents,'{}'::jsonb))<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_documents');
  end if;
  if pg_column_size(coalesce(p_documents,'{}'::jsonb))>33554432 then
    return jsonb_build_object('ok',false,'error','payload_too_large');
  end if;

  insert into private.vt_families(family_id,secret_hash)
  values(v_family,extensions.crypt(lower(p_family_secret_hash),extensions.gen_salt('bf',12)));

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_family,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));

  for v_key,v_payload in select key,value from jsonb_each(coalesce(p_documents,'{}'::jsonb))
  loop
    if not (v_key='shared' or v_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$') then
      raise exception 'invalid_doc_key';
    end if;
    if pg_column_size(v_payload)>16777216 then
      raise exception 'document_too_large';
    end if;
    insert into private.vt_documents(family_id,doc_key,payload)
    values(v_family,v_key,coalesce(v_payload,'{}'::jsonb));
  end loop;

  return jsonb_build_object('ok',true,'family_id',v_family,'role','parent');
exception
  when unique_violation then return jsonb_build_object('ok',false,'error','exists');
  when others then
    if sqlerrm in ('invalid_doc_key','document_too_large') then
      return jsonb_build_object('ok',false,'error',sqlerrm);
    end if;
    raise;
end;
$$;

create or replace function private.vt_join_parent_impl(
  p_family_id text,
  p_family_secret_hash text,
  p_device_id text,
  p_device_secret text,
  p_label text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$'
     or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device');
  end if;

  perform 1 from private.vt_families
   where family_id=v_family
     and secret_hash=extensions.crypt(lower(coalesce(p_family_secret_hash,'')),secret_hash);
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;

  if exists(select 1 from private.vt_devices where family_id=v_family and device_id=trim(p_device_id)) then
    return jsonb_build_object('ok',false,'error','device_exists');
  end if;

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_family,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));

  return jsonb_build_object('ok',true,'family_id',v_family,'role','parent');
end;
$$;

create or replace function private.vt_create_child_invite_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_profile_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_profile text := trim(coalesce(p_profile_id,''));
  v_token text;
  v_hash text;
  v_expires timestamptz := now()+interval '15 minutes';
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  if v_profile !~ '^[A-Za-z0-9_-]{3,120}$' then
    return jsonb_build_object('ok',false,'error','invalid_profile_id');
  end if;
  if not exists(
    select 1 from private.vt_documents
    where family_id=v_ctx->>'family_id' and doc_key='profile/'||v_profile||'/setup'
  ) then
    return jsonb_build_object('ok',false,'error','profile_not_found');
  end if;

  delete from private.vt_invites where expires_at<now() or used_at is not null;
  v_token:=encode(extensions.gen_random_bytes(24),'hex');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.vt_invites(token_hash,family_id,profile_id,created_by_device_id,expires_at)
  values(v_hash,v_ctx->>'family_id',v_profile,trim(p_device_id),v_expires);

  return jsonb_build_object('ok',true,'token',v_token,'profile_id',v_profile,'expires_at',v_expires);
end;
$$;

create or replace function private.vt_claim_child_invite_impl(
  p_invite_token text,
  p_device_id text,
  p_device_secret text,
  p_label text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := encode(extensions.digest(coalesce(p_invite_token,''),'sha256'),'hex');
  v_inv private.vt_invites%rowtype;
  v_docs jsonb;
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$'
     or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device');
  end if;

  select * into v_inv from private.vt_invites
   where token_hash=v_hash and used_at is null and expires_at>now()
   for update;
  if not found then return jsonb_build_object('ok',false,'error','invite_invalid'); end if;

  if exists(select 1 from private.vt_devices where family_id=v_inv.family_id and device_id=trim(p_device_id)) then
    return jsonb_build_object('ok',false,'error','device_exists');
  end if;

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,profile_id,label)
  values(v_inv.family_id,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'child',v_inv.profile_id,left(coalesce(p_label,''),120));

  update private.vt_invites set used_at=now() where token_hash=v_hash;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_inv.family_id
     and doc_key in ('shared','profile/'||v_inv.profile_id||'/setup','profile/'||v_inv.profile_id||'/progress');

  return jsonb_build_object('ok',true,'family_id',v_inv.family_id,'role','child','profile_id',v_inv.profile_id,'documents',v_docs);
end;
$$;

create or replace function private.vt_pull_documents_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_docs jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_ctx->>'family_id'
     and (
       v_ctx->>'role'='parent'
       or doc_key='shared'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/setup'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/progress'
     );

  return jsonb_build_object('ok',true,'family_id',v_ctx->>'family_id','role',v_ctx->>'role','profile_id',v_ctx->>'profile_id','documents',v_docs);
end;
$$;

create or replace function private.vt_status_documents_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_docs jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_ctx->>'family_id'
     and (
       v_ctx->>'role'='parent'
       or doc_key='shared'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/setup'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/progress'
     );

  return jsonb_build_object('ok',true,'family_id',v_ctx->>'family_id','role',v_ctx->>'role','profile_id',v_ctx->>'profile_id','documents',v_docs);
end;
$$;

create or replace function private.vt_push_document_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_doc_key text,
  p_payload jsonb,
  p_base_revision bigint
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_key text := trim(coalesce(p_doc_key,''));
  v_revision bigint;
  v_updated timestamptz;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;
  if not (v_key='shared' or v_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$') then
    return jsonb_build_object('ok',false,'error','invalid_doc_key');
  end if;
  if pg_column_size(coalesce(p_payload,'{}'::jsonb))>16777216 then
    return jsonb_build_object('ok',false,'error','payload_too_large');
  end if;

  if v_ctx->>'role'='child' then
    if v_key <> 'profile/'||(v_ctx->>'profile_id')||'/progress' then
      return jsonb_build_object('ok',false,'error','forbidden');
    end if;
  end if;

  if coalesce(p_base_revision,0)=0 then
    begin
      insert into private.vt_documents(family_id,doc_key,revision,payload,updated_at)
      values(v_ctx->>'family_id',v_key,1,coalesce(p_payload,'{}'::jsonb),now())
      returning revision,updated_at into v_revision,v_updated;
      return jsonb_build_object('ok',true,'revision',v_revision,'updated_at',v_updated);
    exception when unique_violation then
      select revision into v_revision from private.vt_documents where family_id=v_ctx->>'family_id' and doc_key=v_key;
      return jsonb_build_object('ok',false,'conflict',true,'revision',v_revision);
    end;
  end if;

  update private.vt_documents
     set payload=coalesce(p_payload,'{}'::jsonb),revision=revision+1,updated_at=now()
   where family_id=v_ctx->>'family_id' and doc_key=v_key and revision=p_base_revision
   returning revision,updated_at into v_revision,v_updated;

  if found then return jsonb_build_object('ok',true,'revision',v_revision,'updated_at',v_updated); end if;

  select revision into v_revision from private.vt_documents where family_id=v_ctx->>'family_id' and doc_key=v_key;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return jsonb_build_object('ok',false,'conflict',true,'revision',v_revision);
end;
$$;

create or replace function private.vt_list_devices_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_devices jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('device_id',device_id,'role',role,'profile_id',profile_id,'label',label,'active',active,'last_seen_at',last_seen_at,'created_at',created_at) order by created_at),'[]'::jsonb)
    into v_devices
    from private.vt_devices where family_id=v_ctx->>'family_id';
  return jsonb_build_object('ok',true,'devices',v_devices);
end;
$$;

create or replace function private.vt_revoke_device_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_target_device_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  if trim(coalesce(p_target_device_id,''))=trim(coalesce(p_device_id,'')) then
    return jsonb_build_object('ok',false,'error','cannot_revoke_self');
  end if;
  update private.vt_devices set active=false
   where family_id=v_ctx->>'family_id' and device_id=trim(coalesce(p_target_device_id,''));
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.vt_create_family(p_family_id text,p_family_secret_hash text,p_device_id text,p_device_secret text,p_label text,p_documents jsonb)
returns jsonb language sql set search_path='' as $$ select private.vt_create_family_impl(p_family_id,p_family_secret_hash,p_device_id,p_device_secret,p_label,p_documents); $$;
create or replace function public.vt_join_parent(p_family_id text,p_family_secret_hash text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $$ select private.vt_join_parent_impl(p_family_id,p_family_secret_hash,p_device_id,p_device_secret,p_label); $$;
create or replace function public.vt_create_child_invite(p_family_id text,p_device_id text,p_device_secret text,p_profile_id text)
returns jsonb language sql set search_path='' as $$ select private.vt_create_child_invite_impl(p_family_id,p_device_id,p_device_secret,p_profile_id); $$;
create or replace function public.vt_claim_child_invite(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $$ select private.vt_claim_child_invite_impl(p_invite_token,p_device_id,p_device_secret,p_label); $$;
create or replace function public.vt_pull_documents(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_pull_documents_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_status_documents(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_status_documents_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_push_document(p_family_id text,p_device_id text,p_device_secret text,p_doc_key text,p_payload jsonb,p_base_revision bigint)
returns jsonb language sql set search_path='' as $$ select private.vt_push_document_impl(p_family_id,p_device_id,p_device_secret,p_doc_key,p_payload,p_base_revision); $$;
create or replace function public.vt_list_devices(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_list_devices_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_revoke_device(p_family_id text,p_device_id text,p_device_secret text,p_target_device_id text)
returns jsonb language sql set search_path='' as $$ select private.vt_revoke_device_impl(p_family_id,p_device_id,p_device_secret,p_target_device_id); $$;

revoke execute on all functions in schema private from public, authenticated;
grant usage on schema private to anon;
grant execute on function private.vt_device_context(text,text,text) to anon;
grant execute on function private.vt_create_family_impl(text,text,text,text,text,jsonb) to anon;
grant execute on function private.vt_join_parent_impl(text,text,text,text,text) to anon;
grant execute on function private.vt_create_child_invite_impl(text,text,text,text) to anon;
grant execute on function private.vt_claim_child_invite_impl(text,text,text,text) to anon;
grant execute on function private.vt_pull_documents_impl(text,text,text) to anon;
grant execute on function private.vt_status_documents_impl(text,text,text) to anon;
grant execute on function private.vt_push_document_impl(text,text,text,text,jsonb,bigint) to anon;
grant execute on function private.vt_list_devices_impl(text,text,text) to anon;
grant execute on function private.vt_revoke_device_impl(text,text,text,text) to anon;

revoke execute on function public.vt_create_family(text,text,text,text,text,jsonb) from public, authenticated;
revoke execute on function public.vt_join_parent(text,text,text,text,text) from public, authenticated;
revoke execute on function public.vt_create_child_invite(text,text,text,text) from public, authenticated;
revoke execute on function public.vt_claim_child_invite(text,text,text,text) from public, authenticated;
revoke execute on function public.vt_pull_documents(text,text,text) from public, authenticated;
revoke execute on function public.vt_status_documents(text,text,text) from public, authenticated;
revoke execute on function public.vt_push_document(text,text,text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.vt_list_devices(text,text,text) from public, authenticated;
revoke execute on function public.vt_revoke_device(text,text,text,text) from public, authenticated;

grant execute on function public.vt_create_family(text,text,text,text,text,jsonb) to anon;
grant execute on function public.vt_join_parent(text,text,text,text,text) to anon;
grant execute on function public.vt_create_child_invite(text,text,text,text) to anon;
grant execute on function public.vt_claim_child_invite(text,text,text,text) to anon;
grant execute on function public.vt_pull_documents(text,text,text) to anon;
grant execute on function public.vt_status_documents(text,text,text) to anon;
grant execute on function public.vt_push_document(text,text,text,text,jsonb,bigint) to anon;
grant execute on function public.vt_list_devices(text,text,text) to anon;
grant execute on function public.vt_revoke_device(text,text,text,text) to anon;


create index if not exists vt_invites_family_idx
  on private.vt_invites(family_id);

-- Current private photo bucket configuration.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'jgw-photos',
  'jgw-photos',
  false,
  5242880,
  array['image/jpeg','image/webp','image/png']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- The photo Edge Function authenticates the garden through the anon RPC and
-- uses service_role only for Storage. Keep private-schema USAGE for the global
-- pre-request hook, but do not grant service_role application-RPC execution.
grant usage on schema private to service_role;
revoke execute on function public.jgw_status_garden(text,text) from service_role;
revoke execute on function public.jgw_pull_garden(text,text) from service_role;
revoke execute on function public.jgw_force_push_garden(text,text,jsonb) from service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from service_role;

-- Reassert private-table boundary after all objects exist.
revoke all on table private.jgw_gardens from public, anon, authenticated, service_role;
revoke all on table private.jgw_rate_limits from public, anon, authenticated, service_role;
revoke all on table private.vt_families, private.vt_devices, private.vt_documents, private.vt_invites
  from public, anon, authenticated, service_role;

alter table private.jgw_gardens enable row level security;
alter table private.jgw_rate_limits enable row level security;
alter table private.vt_families enable row level security;
alter table private.vt_devices enable row level security;
alter table private.vt_documents enable row level security;
alter table private.vt_invites enable row level security;



-- Recovery replay: 20260924203104_vt_family_sync_v2_parent_invites.sql
-- Vokabeltrainer family/device sync v2: one-time parent invites
-- Enables secure QR/link pairing of an additional parent device without exposing the reusable family PIN.

create table if not exists private.vt_parent_invites (
  token_hash text primary key,
  family_id text not null references private.vt_families(family_id) on delete cascade,
  created_by_device_id text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  constraint vt_parent_invite_token_hash_format check (token_hash ~ '^[0-9a-f]{64}
)
);
alter table private.vt_parent_invites enable row level security;
create index if not exists vt_parent_invites_family_idx on private.vt_parent_invites(family_id);
revoke all on private.vt_parent_invites from public, anon, authenticated;

create or replace function private.vt_create_parent_invite_impl(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language plpgsql security definer set search_path='' as $
declare
  v_ctx jsonb;
  v_token text;
  v_hash text;
  v_expires timestamptz := now()+interval '15 minutes';
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent'
    then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  delete from private.vt_parent_invites where expires_at<now() or used_at is not null;
  v_token:=encode(extensions.gen_random_bytes(24),'hex');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.vt_parent_invites(token_hash,family_id,created_by_device_id,expires_at)
  values(v_hash,v_ctx->>'family_id',trim(p_device_id),v_expires);
  return jsonb_build_object('ok',true,'token',v_token,'expires_at',v_expires);
end;
$;

create or replace function private.vt_claim_parent_invite_impl(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language plpgsql security definer set search_path='' as $
declare
  v_hash text := encode(extensions.digest(coalesce(p_invite_token,''),'sha256'),'hex');
  v_inv private.vt_parent_invites%rowtype;
  v_docs jsonb;
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}
 or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256
    then return jsonb_build_object('ok',false,'error','invalid_device'); end if;
  select * into v_inv from private.vt_parent_invites where token_hash=v_hash and used_at is null and expires_at>now() for update;
  if not found then return jsonb_build_object('ok',false,'error','invite_invalid'); end if;
  if exists(select 1 from private.vt_devices where family_id=v_inv.family_id and device_id=trim(p_device_id))
    then return jsonb_build_object('ok',false,'error','device_exists'); end if;
  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_inv.family_id,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));
  update private.vt_parent_invites set used_at=now() where token_hash=v_hash;
  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs from private.vt_documents where family_id=v_inv.family_id;
  return jsonb_build_object('ok',true,'family_id',v_inv.family_id,'role','parent','documents',v_docs);
end;
$;

create or replace function public.vt_create_parent_invite(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $
  select private.vt_create_parent_invite_impl(p_family_id,p_device_id,p_device_secret);
$;

create or replace function public.vt_claim_parent_invite(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $
  select private.vt_claim_parent_invite_impl(p_invite_token,p_device_id,p_device_secret,p_label);
$;

revoke execute on function private.vt_create_parent_invite_impl(text,text,text) from public, authenticated;
revoke execute on function private.vt_claim_parent_invite_impl(text,text,text,text) from public, authenticated;
grant execute on function private.vt_create_parent_invite_impl(text,text,text) to anon;
grant execute on function private.vt_claim_parent_invite_impl(text,text,text,text) to anon;

revoke execute on function public.vt_create_parent_invite(text,text,text) from public, authenticated;
revoke execute on function public.vt_claim_parent_invite(text,text,text,text) from public, authenticated;
grant execute on function public.vt_create_parent_invite(text,text,text) to anon;
grant execute on function public.vt_claim_parent_invite(text,text,text,text) to anon;


-- Recovery replay: 20260925041851_rate_limit_vt_parent_invites.sql
create or replace function private.jgw_pre_request()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_method text := pg_catalog.current_setting('request.method', true);
  v_path text := pg_catalog.current_setting('request.path', true);
  v_headers_text text := pg_catalog.current_setting('request.headers', true);
  v_ip_text text;
  v_ip inet;
  v_scope text;
  v_limit integer;
  v_window interval;
  v_count integer;
  v_error_code text := 'api_rate_limit';
begin
  if v_method is null or v_method not in ('POST','PUT','PATCH','DELETE') then
    return;
  end if;

  v_path := pg_catalog.regexp_replace(coalesce(v_path,''), '^/', '');

  if v_path = 'rpc/jgw_create_garden' then
    v_scope := 'jgw_create';
    v_limit := 10;
    v_window := interval '1 hour';
    v_error_code := 'jgw_rate_limit';
  elsif v_path in (
    'rpc/jgw_status_garden',
    'rpc/jgw_pull_garden',
    'rpc/jgw_push_garden',
    'rpc/jgw_force_push_garden',
    'rpc/jgw_get_calendar_token',
    'rpc/jgw_rotate_calendar_token'
  ) then
    v_scope := 'jgw_sync_auth';
    v_limit := 60;
    v_window := interval '5 minutes';
    v_error_code := 'jgw_rate_limit';
  elsif v_path = 'rpc/vt_create_family' then
    v_scope := 'vt_create_family';
    v_limit := 10;
    v_window := interval '1 hour';
    v_error_code := 'vt_rate_limit';
  elsif v_path = 'rpc/vt_join_parent' then
    v_scope := 'vt_join_parent';
    v_limit := 12;
    v_window := interval '15 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path = 'rpc/vt_claim_child_invite' then
    v_scope := 'vt_claim_child';
    v_limit := 30;
    v_window := interval '15 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path = 'rpc/vt_claim_parent_invite' then
    v_scope := 'vt_claim_parent';
    v_limit := 30;
    v_window := interval '15 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path in (
    'rpc/vt_create_child_invite',
    'rpc/vt_create_parent_invite',
    'rpc/vt_list_devices',
    'rpc/vt_revoke_device'
  ) then
    v_scope := 'vt_device_admin';
    v_limit := 60;
    v_window := interval '5 minutes';
    v_error_code := 'vt_rate_limit';
  elsif v_path in (
    'rpc/vt_pull_documents',
    'rpc/vt_push_document',
    'rpc/vt_status_documents'
  ) then
    v_scope := 'vt_sync';
    v_limit := 180;
    v_window := interval '5 minutes';
    v_error_code := 'vt_rate_limit';
  else
    return;
  end if;

  if v_headers_text is null or v_headers_text = '' then
    return;
  end if;

  begin
    v_ip_text := pg_catalog.btrim(
      pg_catalog.split_part((v_headers_text::jsonb)->>'x-forwarded-for', ',', 1)
    );
    if v_ip_text is null or v_ip_text = '' then return; end if;
    v_ip := v_ip_text::inet;
  exception when others then
    return;
  end;

  delete from private.jgw_rate_limits
   where requested_at < pg_catalog.now() - interval '24 hours';

  select pg_catalog.count(*)::integer
    into v_count
    from private.jgw_rate_limits
   where scope = v_scope
     and ip = v_ip
     and requested_at >= pg_catalog.now() - v_window;

  if v_count >= v_limit then
    raise sqlstate 'PGRST'
      using message = jsonb_build_object(
        'code',v_error_code,
        'message','Zu viele Anfragen. Bitte kurz warten und erneut versuchen.'
      )::text,
      detail = jsonb_build_object(
        'status',429,
        'status_text','Too Many Requests'
      )::text;
  end if;

  insert into private.jgw_rate_limits(ip, scope, requested_at)
  values (v_ip, v_scope, pg_catalog.now());
end;
$function$;


-- Recovery replay: 20260925204000_harden_vt_device_context_boundary.sql
-- Vokabeltrainer family sync v3: tighten internal RPC helper boundary.
-- Public RPC wrappers continue to call the private SECURITY DEFINER implementations.
-- The device-context helper itself is never a browser RPC entrypoint.
revoke execute on function private.vt_device_context(text,text,text) from anon, authenticated, public;


notify pgrst, 'reload config';

commit;
