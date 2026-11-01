create table if not exists public.booking_pickups (
  booking_id uuid primary key references public.bookings(id) on delete cascade,
  ride_id uuid not null references public.rides(id) on delete cascade,
  passenger_id uuid not null references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);

create index if not exists booking_pickups_ride_id_idx on public.booking_pickups(ride_id);
alter table public.booking_pickups enable row level security;
grant select, insert, update on public.booking_pickups to authenticated;

create policy "passenger shares own confirmed booking pickup"
on public.booking_pickups for insert to authenticated
with check (
  passenger_id = (select auth.uid())
  and exists (
    select 1 from public.bookings b
    where b.id = booking_pickups.booking_id and b.ride_id = booking_pickups.ride_id
      and b.passenger_id = (select auth.uid())
      and b.status::text = 'confirmed'
  )
);

create policy "passenger updates own confirmed booking pickup"
on public.booking_pickups for update to authenticated
using (
  passenger_id = (select auth.uid())
  and exists (
    select 1 from public.bookings b
    where b.id = booking_pickups.booking_id and b.ride_id = booking_pickups.ride_id
      and b.passenger_id = (select auth.uid())
      and b.status::text = 'confirmed'
  )
)
with check (
  passenger_id = (select auth.uid())
  and exists (
    select 1 from public.bookings b
    where b.id = booking_pickups.booking_id and b.ride_id = booking_pickups.ride_id
      and b.passenger_id = (select auth.uid())
      and b.status::text = 'confirmed'
  )
);

create policy "ride driver and passenger read pickup"
on public.booking_pickups for select to authenticated
using (
  passenger_id = (select auth.uid())
  or exists (
    select 1 from public.rides r
    join public.bookings b on b.ride_id = r.id
    where b.id = booking_pickups.booking_id and r.id = booking_pickups.ride_id
      and r.driver_id = (select auth.uid())
      and b.status::text = 'confirmed'
  )
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'booking_pickups'
  ) then
    alter publication supabase_realtime add table public.booking_pickups;
  end if;
end
$$;