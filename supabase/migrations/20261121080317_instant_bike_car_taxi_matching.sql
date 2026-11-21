-- Instant Bike/Car Taxi: online driver presence and 8 km request matching.
create table public.driver_presence (
  driver_id uuid primary key references public.profiles(id) on delete cascade,
  vehicle_type public.vehicle_type not null check (vehicle_type in ('bike','car')),
  vehicle_name text not null,
  vehicle_number text not null,
  online boolean not null default false,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);
create index driver_presence_online_type_updated_idx
  on public.driver_presence(vehicle_type, online, updated_at desc);

create table public.ride_requests (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles(id) on delete restrict,
  driver_id uuid references public.profiles(id) on delete restrict,
  vehicle_type public.vehicle_type not null check (vehicle_type in ('bike','car')),
  pickup_label text not null,
  destination_label text not null,
  pickup_latitude double precision not null check (pickup_latitude between -90 and 90),
  pickup_longitude double precision not null check (pickup_longitude between -180 and 180),
  status text not null default 'searching'
    check (status in ('searching','accepted','arrived','in_progress','completed','cancelled','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (passenger_id <> driver_id)
);
create index ride_requests_passenger_created_idx on public.ride_requests(passenger_id, created_at desc);
create index ride_requests_driver_status_idx on public.ride_requests(driver_id, status);
create index ride_requests_search_idx on public.ride_requests(vehicle_type, status, created_at desc);

create table public.ride_request_locations (
  request_id uuid primary key references public.ride_requests(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);

alter table public.driver_presence enable row level security;
alter table public.ride_requests enable row level security;
alter table public.ride_request_locations enable row level security;
revoke all on public.driver_presence, public.ride_requests, public.ride_request_locations from anon, public;
grant select, insert, update, delete on public.driver_presence to authenticated;
grant select, insert, update on public.ride_requests to authenticated;
grant select, insert, update on public.ride_request_locations to authenticated;

create policy "drivers manage own presence" on public.driver_presence
for select to authenticated using (driver_id = (select auth.uid()));
create policy "drivers start own presence" on public.driver_presence
for insert to authenticated with check (
  driver_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('driver','admin'))
);
create policy "drivers update own presence" on public.driver_presence
for update to authenticated using (driver_id = (select auth.uid()))
with check (
  driver_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('driver','admin'))
);
create policy "drivers remove own presence" on public.driver_presence
for delete to authenticated using (driver_id = (select auth.uid()));

create policy "passengers and matched drivers read requests" on public.ride_requests
for select to authenticated using (
  passenger_id = (select auth.uid()) or driver_id = (select auth.uid())
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
);
create policy "passengers create own requests" on public.ride_requests
for insert to authenticated with check (
  passenger_id = (select auth.uid()) and driver_id is null and status = 'searching'
);
create policy "passengers cancel own requests" on public.ride_requests
for update to authenticated using (
  passenger_id = (select auth.uid()) and status in ('searching','accepted')
) with check (passenger_id = (select auth.uid()) and status = 'cancelled');
create policy "nearby drivers accept and progress requests" on public.ride_requests
for update to authenticated using (
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
) with check (
  driver_id = (select auth.uid()) and status in ('accepted','arrived','in_progress','completed')
);

create policy "ride parties read live request location" on public.ride_request_locations
for select to authenticated using (
  driver_id = (select auth.uid())
  or exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.passenger_id = (select auth.uid())
      and rr.driver_id = ride_request_locations.driver_id
  )
);
create policy "assigned driver inserts live request location" on public.ride_request_locations
for insert to authenticated with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status in ('accepted','arrived','in_progress')
  )
);
create policy "assigned driver updates live request location" on public.ride_request_locations
for update to authenticated using (driver_id = (select auth.uid()))
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1 from public.ride_requests rr
    where rr.id = request_id and rr.driver_id = (select auth.uid())
      and rr.status in ('accepted','arrived','in_progress')
  )
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='ride_requests') then
      alter publication supabase_realtime add table public.ride_requests;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='ride_request_locations') then
      alter publication supabase_realtime add table public.ride_request_locations;
    end if;
  end if;
end $$;
