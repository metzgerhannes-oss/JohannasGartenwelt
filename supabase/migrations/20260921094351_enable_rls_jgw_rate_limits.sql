-- Supabase migration 20260921094351: enable_rls_jgw_rate_limits
alter table private.jgw_rate_limits enable row level security;
