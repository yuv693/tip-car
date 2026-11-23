-- Allow an assigned driver to cancel before the ride starts.
create or replace function public.enforce_ride_request_transition()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.passenger_id is distinct from old.passenger_id
     or new.vehicle_type is distinct from old.vehicle_type
     or new.pickup_label is distinct from old.pickup_label
     or new.destination_label is distinct from old.destination_label
     or new.pickup_latitude is distinct from old.pickup_latitude
     or new.pickup_longitude is distinct from old.pickup_longitude
     or new.created_at is distinct from old.created_at then
    raise exception 'Ride request details cannot be changed after submission';
  end if;

  if old.status = 'searching' and new.status = 'accepted' then
    if old.driver_id is not null or new.driver_id is distinct from auth.uid() then
      raise exception 'Only the accepting driver can claim this request';
    end if;
  elsif old.status in ('searching','accepted') and new.status = 'cancelled' then
    if old.passenger_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the passenger can cancel this request';
    end if;
  elsif old.status in ('accepted','arrived') and new.status = 'cancelled' then
    if old.driver_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the assigned driver can cancel before the ride starts';
    end if;
  elsif old.status = 'accepted' and new.status = 'arrived' then
    if old.driver_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the assigned driver can mark arrival';
    end if;
  elsif old.status = 'arrived' and new.status = 'in_progress' then
    if old.driver_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the assigned driver can start this ride';
    end if;
  elsif old.status = 'in_progress' and new.status = 'completed' then
    if old.driver_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the assigned driver can complete this ride';
    end if;
  else
    raise exception 'Invalid ride request status transition: % -> %', old.status, new.status;
  end if;
  return new;
end;
$$;

drop policy if exists "nearby drivers accept and progress requests" on public.ride_requests;
create policy "nearby drivers accept and progress requests" on public.ride_requests
for update to authenticated
using (
  (
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
with check (
  driver_id = (select auth.uid())
  and status in ('accepted','arrived','in_progress','completed','cancelled')
);
