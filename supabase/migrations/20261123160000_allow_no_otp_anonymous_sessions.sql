-- Tip Car uses Supabase Anonymous Auth for the explicitly requested no-OTP login.
-- Anonymous sessions still have a stable auth.uid(); scope every operation to that UID
-- and the existing driver/passenger ownership checks rather than rejecting is_anonymous.
-- Phone numbers remain unverified contact details and must not be treated as identity proof.

drop policy if exists "drivers create own presence" on public.driver_presence;
create policy "drivers create own presence"
on public.driver_presence for insert to authenticated
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = any (array['driver'::public.app_role, 'admin'::public.app_role])
  )
);

drop policy if exists "drivers read own presence" on public.driver_presence;
create policy "drivers read own presence"
on public.driver_presence for select to authenticated
using (driver_id = (select auth.uid()));

drop policy if exists "drivers remove own presence" on public.driver_presence;
create policy "drivers remove own presence"
on public.driver_presence for delete to authenticated
using (driver_id = (select auth.uid()));

drop policy if exists "drivers update own presence" on public.driver_presence;
create policy "drivers update own presence"
on public.driver_presence for update to authenticated
using (driver_id = (select auth.uid()))
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = any (array['driver'::public.app_role, 'admin'::public.app_role])
  )
);

drop policy if exists "assigned driver deletes completed location" on public.ride_request_locations;
create policy "assigned driver deletes completed location"
on public.ride_request_locations for delete to authenticated
using (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = ride_request_locations.request_id
      and rr.driver_id = (select auth.uid())
      and rr.status = any (array['completed'::text, 'cancelled'::text])
  )
);

drop policy if exists "assigned driver inserts live request location" on public.ride_request_locations;
create policy "assigned driver inserts live request location"
on public.ride_request_locations for insert to authenticated
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = ride_request_locations.request_id
      and rr.driver_id = (select auth.uid())
      and rr.status = any (array['accepted'::text, 'arrived'::text, 'in_progress'::text])
  )
);

drop policy if exists "assigned driver updates live request location" on public.ride_request_locations;
create policy "assigned driver updates live request location"
on public.ride_request_locations for update to authenticated
using (driver_id = (select auth.uid()))
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = ride_request_locations.request_id
      and rr.driver_id = (select auth.uid())
      and rr.status = any (array['accepted'::text, 'arrived'::text, 'in_progress'::text])
  )
);

drop policy if exists "ride parties read live request location" on public.ride_request_locations;
create policy "ride parties read live request location"
on public.ride_request_locations for select to authenticated
using (
  driver_id = (select auth.uid())
  or exists (
    select 1 from public.ride_requests rr
    where rr.id = ride_request_locations.request_id
      and rr.passenger_id = (select auth.uid())
      and rr.driver_id = ride_request_locations.driver_id
      and rr.status = any (array['accepted'::text, 'arrived'::text, 'in_progress'::text])
  )
);

drop policy if exists "passengers and matched drivers read requests" on public.ride_requests;
create policy "passengers and matched drivers read requests"
on public.ride_requests for select to authenticated
using (
  passenger_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or (
    status = 'searching'::text
    and driver_id is null
    and exists (
      select 1 from public.driver_presence dp
      where dp.driver_id = (select auth.uid())
        and dp.online
        and dp.vehicle_type = ride_requests.vehicle_type
        and dp.updated_at > (now() - interval '90 seconds')
        and (
          6371::double precision * acos(least(
            1.0::double precision,
            greatest(
              -1.0::double precision,
              sin(radians(ride_requests.pickup_latitude)) * sin(radians(dp.latitude))
              + cos(radians(ride_requests.pickup_latitude))
                * cos(radians(dp.latitude))
                * cos(radians(dp.longitude) - radians(ride_requests.pickup_longitude))
            )
          ))
        ) <= 8::double precision
    )
  )
);

drop policy if exists "passengers create own requests" on public.ride_requests;
create policy "passengers create own requests"
on public.ride_requests for insert to authenticated
with check (
  passenger_id = (select auth.uid())
  and driver_id is null
  and status = 'searching'::text
);

drop policy if exists "ride participants update requests" on public.ride_requests;
create policy "ride participants update requests"
on public.ride_requests for update to authenticated
using (
  (passenger_id = (select auth.uid())
    and status = any (array['searching'::text, 'accepted'::text]))
  or (
    status = 'searching'::text
    and driver_id is null
    and exists (
      select 1 from public.driver_presence dp
      where dp.driver_id = (select auth.uid())
        and dp.online
        and dp.vehicle_type = ride_requests.vehicle_type
        and dp.updated_at > (now() - interval '90 seconds')
        and (
          6371::double precision * acos(least(
            1.0::double precision,
            greatest(
              -1.0::double precision,
              sin(radians(ride_requests.pickup_latitude)) * sin(radians(dp.latitude))
              + cos(radians(ride_requests.pickup_latitude))
                * cos(radians(dp.latitude))
                * cos(radians(dp.longitude) - radians(ride_requests.pickup_longitude))
            )
          ))
        ) <= 8::double precision
    )
  )
  or (
    driver_id = (select auth.uid())
    and status = any (array['accepted'::text, 'arrived'::text, 'in_progress'::text])
  )
)
with check (
  (passenger_id = (select auth.uid()) and status = 'cancelled'::text)
  or (
    driver_id = (select auth.uid())
    and status = any (array[
      'accepted'::text, 'arrived'::text, 'in_progress'::text,
      'completed'::text, 'cancelled'::text
    ])
  )
);
