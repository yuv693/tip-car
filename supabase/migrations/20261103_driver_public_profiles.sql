-- Driver cards expose only name and optional photo. Phone is never public.
alter table public.profiles
  add column if not exists avatar_url text;

-- Remove the broad row policy: it would expose every profiles column, including phone.
drop policy if exists "profiles public driver card for active rides" on public.profiles;
drop view if exists public.driver_public_profiles;

-- Return only safe driver-card fields for upcoming rides, and only to signed-in users.
create or replace function public.search_driver_public_profiles(p_driver_ids uuid[])
returns table(id uuid, full_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.avatar_url
  from public.profiles p
  where auth.uid() is not null
    and p.role = 'driver'
    and p.id = any(coalesce(p_driver_ids, array[]::uuid[]))
    and exists (
      select 1
      from public.rides r
      where r.driver_id = p.id
        and r.status in ('active', 'full')
        and r.departure_at > now()
    );
$$;

revoke all on function public.search_driver_public_profiles(uuid[]) from public, anon;
grant execute on function public.search_driver_public_profiles(uuid[]) to authenticated;

-- A passenger can retrieve a driver's phone only for their own confirmed booking.
create or replace function public.get_confirmed_ride_driver_contact(p_ride_id uuid)
returns table(full_name text, phone text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select p.full_name, p.phone, p.avatar_url
  from public.profiles p
  join public.rides r on r.driver_id = p.id
  join public.bookings b on b.ride_id = r.id
  where auth.uid() is not null
    and r.id = p_ride_id
    and b.passenger_id = auth.uid()
    and b.status = 'confirmed'
  limit 1;
$$;

revoke all on function public.get_confirmed_ride_driver_contact(uuid) from public, anon;
grant execute on function public.get_confirmed_ride_driver_contact(uuid) to authenticated;
