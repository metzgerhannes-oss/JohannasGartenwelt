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
  constraint jgw_secret_hash_len check (length(secret_hash) = 64)
);

revoke all on table private.jgw_gardens from public, anon, authenticated;

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
  where garden_id = lower(trim(p_garden_id)) and secret_hash = p_secret_hash;
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
  where garden_id = lower(trim(p_garden_id)) and secret_hash = p_secret_hash;
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
     and secret_hash = p_secret_hash
     and revision = p_base_revision
  returning * into v_row;

  if found then
    return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
  end if;

  select revision into v_current
  from private.jgw_gardens
  where garden_id = lower(trim(p_garden_id)) and secret_hash = p_secret_hash;
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
   where garden_id = lower(trim(p_garden_id)) and secret_hash = p_secret_hash
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
    and secret_hash = p_secret_hash;

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
     and secret_hash = p_secret_hash;

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
-- Die private Tabelle ist nie direkt für Browserrollen freigegeben.
-- RLS liefert zusätzliche Defense-in-Depth. FORCE RLS bleibt bewusst aus,
-- weil die geprüften SECURITY-DEFINER-Funktionen des Tabellenbesitzers
-- die einzige Datenzugriffsschicht bilden.
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

-- Öffentliche RPC-Endpunkte übernehmen die Privilegien des Funktionsbesitzers.
-- search_path='' verhindert Namensauflösungs-/Hijacking-Risiken.
create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

-- Browserrollen sehen das private Schema und dessen Implementierungsfunktionen nicht mehr.
revoke usage on schema private from public, anon, authenticated, service_role;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated, service_role;

-- Nur die explizit vorgesehenen öffentlichen RPCs sind für die Browserrolle anon erreichbar.
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
