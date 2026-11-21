grant delete on public.ride_request_locations to authenticated;
drop policy if exists "ride parties read live request location" on public.ride_request_locations;
create policy "ride parties read live request location"
on public.ride_request_locations for select to authenticated
using (
  driver_id = (select auth.uid())
  or exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id
      and rr.passenger_id = (select auth.uid())
      and rr.driver_id = ride_request_locations.driver_id
      and rr.status in ('accepted','arrived','in_progress')
  )
);
create policy "assigned driver deletes completed location"
on public.ride_request_locations for delete to authenticated
using (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status = 'completed'
  )
);
