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
