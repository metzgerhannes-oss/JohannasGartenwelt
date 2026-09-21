
alter table private.jgw_gardens enable row level security;
alter table private.jgw_gardens no force row level security;

create or replace function public.jgw_create_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_create_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_status_garden(p_garden_id text, p_secret_hash text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_status_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_pull_garden(p_garden_id text, p_secret_hash text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_pull_garden_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb, p_base_revision bigint)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_push_garden_impl(p_garden_id, p_secret_hash, p_payload, p_base_revision);
$$;

create or replace function public.jgw_force_push_garden(p_garden_id text, p_secret_hash text, p_payload jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_force_push_garden_impl(p_garden_id, p_secret_hash, p_payload);
$$;

create or replace function public.jgw_get_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_get_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_rotate_calendar_token(p_garden_id text, p_secret_hash text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_rotate_calendar_token_impl(p_garden_id, p_secret_hash);
$$;

create or replace function public.jgw_calendar_payload(p_calendar_token text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.jgw_calendar_payload_impl(p_calendar_token);
$$;

revoke usage on schema private from public, anon, authenticated, service_role;

revoke execute on function private.jgw_create_garden_impl(text,text,jsonb) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_status_garden_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_pull_garden_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_push_garden_impl(text,text,jsonb,bigint) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_force_push_garden_impl(text,text,jsonb) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_get_calendar_token_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_rotate_calendar_token_impl(text,text) from public, anon, authenticated, service_role;
revoke execute on function private.jgw_calendar_payload_impl(text) from public, anon, authenticated, service_role;

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
