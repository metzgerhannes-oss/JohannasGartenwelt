
drop policy if exists jgw_no_direct_access on private.jgw_gardens;
create policy jgw_no_direct_access
on private.jgw_gardens
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

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

grant usage on schema private to anon;

grant execute on function private.jgw_create_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_status_garden_impl(text,text) to anon;
grant execute on function private.jgw_pull_garden_impl(text,text) to anon;
grant execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) to anon;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to anon;
grant execute on function private.jgw_get_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_rotate_calendar_token_impl(text,text) to anon;
grant execute on function private.jgw_calendar_payload_impl(text) to anon;

revoke usage on schema private from public, authenticated, service_role;

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
