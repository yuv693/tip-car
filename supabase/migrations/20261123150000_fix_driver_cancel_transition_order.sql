-- Ensure assigned-driver cancellation is checked before passenger cancellation.
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
  elsif old.status in ('accepted','arrived') and new.status = 'cancelled'
        and old.driver_id = auth.uid() then
    if new.driver_id is distinct from old.driver_id then
      raise exception 'Assigned driver cannot change while cancelling';
    end if;
  elsif old.status in ('searching','accepted') and new.status = 'cancelled' then
    if old.passenger_id is distinct from auth.uid()
       or new.driver_id is distinct from old.driver_id then
      raise exception 'Only the passenger can cancel this request';
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
