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
