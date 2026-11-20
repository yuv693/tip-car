-- Least-privilege hardening for Tip Car.
-- All booking/seat/location mutations go through ownership-checking SECURITY DEFINER RPCs.

-- No unauthenticated table access is required: the app requires a verified sign-in.
revoke all privileges on all tables in schema public from anon;

-- Profiles: users can create their own passenger/driver profile and update only
-- contact/display fields. They cannot promote themselves by changing role later.
revoke all privileges on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant insert (id, full_name, phone, role) on table public.profiles to authenticated;
grant update (full_name, phone, avatar_url) on table public.profiles to authenticated;

-- Ride discovery and publishing are direct operations; seat counts/status are
-- intentionally mutated only by trusted booking RPCs.
revoke all privileges on table public.rides from authenticated;
grant select, insert on table public.rides to authenticated;

-- Booking inserts, status changes and payment metadata are RPC-only.
revoke all privileges on table public.bookings from authenticated;
grant select on table public.bookings to authenticated;

-- Commission records are read-only to drivers; trigger/admin RPCs maintain them.
revoke all privileges on table public.driver_commissions from authenticated;
grant select on table public.driver_commissions to authenticated;

-- Live coordinates are read by ride parties and written only through the
-- driver/confirmed-booking checked update_my_ride_location RPC.
revoke all privileges on table public.ride_locations from authenticated;
grant select on table public.ride_locations to authenticated;

-- Pickup-sharing rows are only available to signed-in ride parties.
revoke all privileges on table public.booking_pickups from authenticated;
grant select, insert, update on table public.booking_pickups to authenticated;

-- The helper is used only by the authenticated ride-read policy.
revoke usage on schema private from anon;
grant usage on schema private to authenticated;
revoke all on function private.user_has_booking_for_ride(uuid) from public, anon;
grant execute on function private.user_has_booking_for_ride(uuid) to authenticated;

-- Active ride discovery is for signed-in Tip Car users only.
drop policy if exists "rides public active read" on public.rides;
create policy "rides signed-in active read" on public.rides
for select to authenticated
using (
  status in ('active','full')
  or driver_id = (select auth.uid())
  or private.user_has_booking_for_ride(id)
);

-- Storage object mutations remain restricted by the existing owner-folder RLS.
revoke all privileges on table storage.objects from anon;
grant select, insert, update, delete on table storage.objects to authenticated;
