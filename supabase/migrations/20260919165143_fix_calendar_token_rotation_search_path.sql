
alter table private.jgw_gardens
  alter column calendar_token set default pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

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
