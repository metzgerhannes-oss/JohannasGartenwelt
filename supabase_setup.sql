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
  and secret_hash ~ '^[0-9a-fA-F]{64}
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
  if length(coalesce(p_secret_hash, '')) <> 64 or p_secret_hash !~ '^[0-9a-fA-F]{64}    return jsonb_build_object('ok', false, 'error', 'payload_too_large');
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
;

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
  if length(coalesce(p_secret_hash, '')) <> 64 or p_secret_hash !~ '^[0-9a-fA-F]{64}
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
 then
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
;

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
  if length(coalesce(p_secret_hash, '')) <> 64 or p_secret_hash !~ '^[0-9a-fA-F]{64}
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
