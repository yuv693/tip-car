-- Public driver cards expose only a driver's name and optional photo.
-- Phone numbers are intentionally excluded from the public view.
alter table public.profiles
  add column if not exists avatar_url text;

drop policy if exists "profiles public driver card for active rides" on public.profiles;
create policy "profiles public driver card for active rides"
on public.profiles
for select
to anon, authenticated
using (
  role = 'driver'
  and exists (
    select 1
    from public.rides r
    where r.driver_id = profiles.id
      and r.status in ('active', 'full')
      and r.departure_at > now()
  )
);

create or replace view public.driver_public_profiles
with (security_invoker = true)
as
select id, full_name, avatar_url
from public.profiles
where role = 'driver';

grant select on public.driver_public_profiles to anon, authenticated;

-- A passenger may retrieve the driver's phone only after their booking is confirmed.
create or replace function public.get_confirmed_ride_driver_contact(p_ride_id uuid)
returns table(full_name text, phone text, avatar_url text)
language sql
stable
security invoker
set search_path = public
as $$
  select p.full_name, p.phone, p.avatar_url
  from public.profiles p
  join public.rides r on r.driver_id = p.id
  join public.bookings b on b.ride_id = r.id
  where r.id = p_ride_id
    and b.passenger_id = auth.uid()
    and b.status = 'confirmed'
  limit 1;
$$;

revoke all on function public.get_confirmed_ride_driver_contact(uuid) from public, anon;
grant execute on function public.get_confirmed_ride_driver_contact(uuid) to authenticated;
