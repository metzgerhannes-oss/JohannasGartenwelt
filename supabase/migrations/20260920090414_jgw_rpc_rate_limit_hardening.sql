
create table if not exists private.jgw_rate_limits (
  ip inet not null,
  scope text not null,
  requested_at timestamptz not null default now()
);

create index if not exists jgw_rate_limits_scope_ip_requested_at_idx
  on private.jgw_rate_limits(scope, ip, requested_at desc);

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
begin
  if v_method is null or v_method not in ('POST','PUT','PATCH','DELETE') then
    return;
  end if;

  v_path := pg_catalog.regexp_replace(pg_catalog.coalesce(v_path,''), '^/', '');

  if v_path = 'rpc/jgw_create_garden' then
    v_scope := 'create';
    v_limit := 10;
    v_window := interval '1 hour';
  elsif v_path in (
    'rpc/jgw_status_garden',
    'rpc/jgw_pull_garden',
    'rpc/jgw_push_garden',
    'rpc/jgw_force_push_garden',
    'rpc/jgw_get_calendar_token',
    'rpc/jgw_rotate_calendar_token'
  ) then
    v_scope := 'sync_auth';
    v_limit := 60;
    v_window := interval '5 minutes';
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
   where scope = v_scope
     and ip = v_ip
     and requested_at < pg_catalog.now() - interval '24 hours';

  select pg_catalog.count(*)::integer
    into v_count
    from private.jgw_rate_limits
   where scope = v_scope
     and ip = v_ip
     and requested_at >= pg_catalog.now() - v_window;

  if v_count >= v_limit then
    raise sqlstate 'PGRST'
      using message = jsonb_build_object(
        'code','jgw_rate_limit',
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
