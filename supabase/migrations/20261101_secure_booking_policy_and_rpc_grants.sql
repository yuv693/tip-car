-- Prevent RLS recursion and close anonymous execution on privileged RPCs.

create schema if not exists private;
create or replace function private.user_has_booking_for_ride(p_ride_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.bookings b
    where b.ride_id = p_ride_id
      and b.passenger_id = (select auth.uid())
  );
$$;
revoke all on function private.user_has_booking_for_ride(uuid) from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.user_has_booking_for_ride(uuid) to anon, authenticated;

drop policy if exists "rides public active read" on public.rides;
create policy "rides public active read" on public.rides
for select to anon, authenticated
using (
  status in ('active','full')
  or driver_id = (select auth.uid())
  or private.user_has_booking_for_ride(id)
);

revoke all on function public.create_booking(uuid,integer) from public, anon;
grant execute on function public.create_booking(uuid,integer) to authenticated;
revoke all on function public.driver_respond_booking(uuid,text) from public, anon;
grant execute on function public.driver_respond_booking(uuid,text) to authenticated;
revoke all on function public.cancel_my_booking(uuid) from public, anon;
grant execute on function public.cancel_my_booking(uuid) to authenticated;
revoke all on function public.sync_booking_commission() from public, anon, authenticated;
