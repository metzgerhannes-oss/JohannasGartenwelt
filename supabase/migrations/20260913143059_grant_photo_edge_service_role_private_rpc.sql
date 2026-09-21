grant usage on schema private to service_role;
grant execute on function private.jgw_status_garden_impl(text,text) to service_role;
grant execute on function private.jgw_pull_garden_impl(text,text) to service_role;
grant execute on function private.jgw_force_push_garden_impl(text,text,jsonb) to service_role;