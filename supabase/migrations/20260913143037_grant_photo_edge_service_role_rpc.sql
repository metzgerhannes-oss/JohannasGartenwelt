grant execute on function public.jgw_status_garden(text,text) to service_role;
grant execute on function public.jgw_pull_garden(text,text) to service_role;
grant execute on function public.jgw_force_push_garden(text,text,jsonb) to service_role;