create table if not exists public.ride_locations (
  ride_id uuid primary key references public.rides(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);
alter table public.ride_locations enable row level security;

create or replace function private.user_can_track_ride(p_ride_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.bookings
    where ride_id = p_ride_id
      and passenger_id = (select auth.uid())
      and status::text = 'confirmed'
  );
$$;
revoke all on function private.user_can_track_ride(uuid) from public;
grant execute on function private.user_can_track_ride(uuid) to authenticated;

create policy "ride location visible to ride parties"
on public.ride_locations for select to authenticated
using (driver_id = (select auth.uid()) or private.user_can_track_ride(ride_id));

create or replace function public.update_my_ride_location(
  p_ride_id uuid, p_latitude double precision, p_longitude double precision
)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Invalid coordinates';
  end if;
  if not exists (
    select 1 from public.rides r
    where r.id = p_ride_id and r.driver_id = auth.uid()
      and r.status::text = 'active'
      and exists (select 1 from public.bookings b
        where b.ride_id = r.id and b.status::text = 'confirmed')
  ) then raise exception 'Ride is not eligible for location sharing'; end if;

  insert into public.ride_locations (ride_id, driver_id, latitude, longitude, updated_at)
  values (p_ride_id, auth.uid(), p_latitude, p_longitude, now())
  on conflict (ride_id) do update set
    latitude = excluded.latitude, longitude = excluded.longitude, updated_at = now();
end;
$$;
revoke all on function public.update_my_ride_location(uuid,double precision,double precision) from public, anon;
grant execute on function public.update_my_ride_location(uuid,double precision,double precision) to authenticated;

alter publication supabase_realtime add table public.ride_locations;
