-- Trigger-only commission synchronizer: callers must not invoke it as an RPC.
revoke all on function public.sync_instant_taxi_commission() from public;
revoke all on function public.sync_instant_taxi_commission() from anon;
revoke all on function public.sync_instant_taxi_commission() from authenticated;
grant execute on function public.sync_instant_taxi_commission() to service_role;
