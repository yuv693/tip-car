create index if not exists ride_request_locations_driver_idx
  on public.ride_request_locations(driver_id);

drop policy if exists "drivers manage own presence" on public.driver_presence;
drop policy if exists "drivers start own presence" on public.driver_presence;
drop policy if exists "drivers update own presence" on public.driver_presence;
drop policy if exists "drivers remove own presence" on public.driver_presence;
create policy "drivers read own presence" on public.driver_presence
for select to authenticated using (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
);
create policy "drivers create own presence" on public.driver_presence
for insert to authenticated with check (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('driver','admin'))
);
create policy "drivers update own presence" on public.driver_presence
for update to authenticated using (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
) with check (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('driver','admin'))
);
create policy "drivers remove own presence" on public.driver_presence
for delete to authenticated using (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
);

drop policy if exists "passengers and matched drivers read requests" on public.ride_requests;
create policy "passengers and matched drivers read requests" on public.ride_requests
for select to authenticated using (
  coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and (
    passenger_id = (select auth.uid())
    or driver_id = (select auth.uid())
    or (
      status = 'searching' and driver_id is null
      and exists (
        select 1 from public.driver_presence dp
        where dp.driver_id = (select auth.uid()) and dp.online
          and dp.vehicle_type = ride_requests.vehicle_type
          and dp.updated_at > now() - interval '90 seconds'
          and 6371 * acos(least(1.0, greatest(-1.0,
            sin(radians(ride_requests.pickup_latitude)) * sin(radians(dp.latitude))
            + cos(radians(ride_requests.pickup_latitude)) * cos(radians(dp.latitude))
            * cos(radians(dp.longitude) - radians(ride_requests.pickup_longitude))
          ))) <= 8
      )
    )
  )
);
drop policy if exists "passengers create own requests" on public.ride_requests;
create policy "passengers create own requests" on public.ride_requests
for insert to authenticated with check (
  passenger_id = (select auth.uid()) and driver_id is null and status = 'searching'
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
);
drop policy if exists "passengers cancel own requests" on public.ride_requests;
drop policy if exists "nearby drivers accept and progress requests" on public.ride_requests;
create policy "ride participants update requests" on public.ride_requests
for update to authenticated using (
  coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and (
    (passenger_id = (select auth.uid()) and status in ('searching','accepted'))
    or (
      status = 'searching' and driver_id is null
      and exists (
        select 1 from public.driver_presence dp
        where dp.driver_id = (select auth.uid()) and dp.online
          and dp.vehicle_type = ride_requests.vehicle_type
          and dp.updated_at > now() - interval '90 seconds'
          and 6371 * acos(least(1.0, greatest(-1.0,
            sin(radians(ride_requests.pickup_latitude)) * sin(radians(dp.latitude))
            + cos(radians(ride_requests.pickup_latitude)) * cos(radians(dp.latitude))
            * cos(radians(dp.longitude) - radians(ride_requests.pickup_longitude))
          ))) <= 8
      )
    )
    or (driver_id = (select auth.uid()) and status in ('accepted','arrived','in_progress'))
  )
) with check (
  coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and (
    (passenger_id = (select auth.uid()) and status = 'cancelled')
    or (driver_id = (select auth.uid()) and status in ('accepted','arrived','in_progress','completed'))
  )
);

drop policy if exists "ride parties read live request location" on public.ride_request_locations;
create policy "ride parties read live request location"
on public.ride_request_locations for select to authenticated using (
  coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and (
    driver_id = (select auth.uid())
    or exists (
      select 1 from public.ride_requests rr
      where rr.id = request_id and rr.passenger_id = (select auth.uid())
        and rr.driver_id = ride_request_locations.driver_id
        and rr.status in ('accepted','arrived','in_progress')
    )
  )
);
drop policy if exists "assigned driver inserts live request location" on public.ride_request_locations;
create policy "assigned driver inserts live request location"
on public.ride_request_locations for insert to authenticated with check (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status in ('accepted','arrived','in_progress')
  )
);
drop policy if exists "assigned driver updates live request location" on public.ride_request_locations;
create policy "assigned driver updates live request location"
on public.ride_request_locations for update to authenticated using (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
) with check (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status in ('accepted','arrived','in_progress')
  )
);
drop policy if exists "assigned driver deletes completed location" on public.ride_request_locations;
create policy "assigned driver deletes completed location"
on public.ride_request_locations for delete to authenticated using (
  driver_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) = false
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status in ('completed','cancelled')
  )
);
