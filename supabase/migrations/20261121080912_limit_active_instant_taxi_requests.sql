-- Prevent duplicate active passenger requests and multiple concurrent driver assignments.
create unique index if not exists ride_requests_one_active_per_passenger_idx
  on public.ride_requests(passenger_id)
  where status in ('searching','accepted','arrived','in_progress');

create unique index if not exists ride_requests_one_active_per_driver_idx
  on public.ride_requests(driver_id)
  where driver_id is not null
    and status in ('accepted','arrived','in_progress');
