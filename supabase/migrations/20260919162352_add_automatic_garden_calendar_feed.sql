
alter table private.jgw_gardens
  add column if not exists calendar_token text;

update private.jgw_gardens
set calendar_token = encode(gen_random_bytes(32), 'hex')
where calendar_token is null;

alter table private.jgw_gardens
  alter column calendar_token set default encode(gen_random_bytes(32), 'hex'),
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
  v_token text := encode(gen_random_bytes(32), 'hex');
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
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
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
