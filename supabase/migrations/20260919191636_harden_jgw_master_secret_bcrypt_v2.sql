
alter table private.jgw_gardens drop constraint if exists jgw_secret_hash_len;

update private.jgw_gardens
set secret_hash = extensions.crypt(lower(secret_hash), extensions.gen_salt('bf', 12))
where length(secret_hash) = 64
  and secret_hash ~ '^[0-9a-fA-F]{64}$';

alter table private.jgw_gardens
  add constraint jgw_secret_hash_len check (length(secret_hash) = 60);

create or replace function private.jgw_create_garden_impl(p_garden_id text, p_secret_hash text, p_payload jsonb)
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
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
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
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at, 'payload', v_row.payload);
end;
$$;

create or replace function private.jgw_push_garden_impl(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
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
  where garden_id = lower(trim(p_garden_id))
    and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash);
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', false, 'conflict', true, 'revision', v_current);
end;
$$;

create or replace function private.jgw_force_push_garden_impl(p_garden_id text, p_secret_hash text, p_payload jsonb)
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
   where garden_id = lower(trim(p_garden_id))
     and secret_hash = extensions.crypt(lower(coalesce(p_secret_hash,'')), secret_hash)
  returning * into v_row;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'revision', v_row.revision, 'updated_at', v_row.updated_at);
end;
$$;

create or replace function private.jgw_get_calendar_token_impl(p_garden_id text, p_secret_hash text)
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

create or replace function private.jgw_rotate_calendar_token_impl(p_garden_id text, p_secret_hash text)
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
