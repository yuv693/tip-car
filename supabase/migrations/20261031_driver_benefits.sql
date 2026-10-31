-- Tip Car driver benefits: ₹20 per confirmed new passenger booking,
-- exact-route seat matching, and 1,000 completed-ride insurance eligibility.
-- Apply this migration in Supabase SQL Editor.

create table if not exists public.driver_commissions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete restrict,
  driver_id uuid not null references public.profiles(id),
  passenger_id uuid not null references public.profiles(id),
  amount numeric(10,2) not null default 20 check (amount = 20),
  status text not null default 'accrued' check (status in ('accrued','reversed')),
  created_at timestamptz not null default now(),
  reversed_at timestamptz
);

create index if not exists driver_commissions_driver_idx
  on public.driver_commissions(driver_id, status);

alter table public.driver_commissions enable row level security;
drop policy if exists "driver reads own commissions" on public.driver_commissions;
create policy "driver reads own commissions" on public.driver_commissions
  for select to authenticated using (driver_id = auth.uid());

create or replace function public.sync_booking_commission()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_driver_id uuid;
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    select driver_id into v_driver_id from public.rides where id = new.ride_id;
    if v_driver_id is not null then
      insert into public.driver_commissions(booking_id, driver_id, passenger_id, amount)
      values (new.id, v_driver_id, new.passenger_id, 20)
      on conflict (booking_id) do update
        set status = 'accrued', reversed_at = null;
    end if;
  elsif new.status = 'cancelled' and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    update public.driver_commissions
       set status = 'reversed', reversed_at = now()
     where booking_id = new.id and status = 'accrued';
  end if;
  return new;
end; $$;

drop trigger if exists bookings_commission_sync on public.bookings;
create trigger bookings_commission_sync
after insert or update of status on public.bookings
for each row execute function public.sync_booking_commission();

create or replace function public.find_route_matches(
  p_origin text,
  p_destination text,
  p_min_seats integer default 1
)
returns table (
  ride_id uuid,
  driver_id uuid,
  vehicle_name text,
  origin text,
  destination text,
  departure_at timestamptz,
  available_seats integer,
  fare_per_seat numeric
)
language sql stable security invoker set search_path = public as $$
  select r.id, r.driver_id, r.vehicle_name, r.origin, r.destination,
         r.departure_at, r.available_seats, r.fare_per_seat
    from public.rides r
   where r.status = 'active'
     and r.departure_at > now()
     and r.available_seats >= greatest(1, least(coalesce(p_min_seats,1),8))
     and lower(trim(r.origin)) = lower(trim(p_origin))
     and lower(trim(r.destination)) = lower(trim(p_destination))
   order by r.departure_at asc
   limit 50;
$$;
grant execute on function public.find_route_matches(text,text,integer) to anon, authenticated;

create or replace function public.get_my_driver_benefits()
returns table (
  completed_rides bigint,
  insurance_eligible boolean,
  commission_total numeric,
  commission_bookings bigint
)
language sql stable security invoker set search_path = public as $$
  select
    (select count(*) from public.rides r
      where r.driver_id = auth.uid() and r.status = 'completed') as completed_rides,
    (select count(*) from public.rides r
      where r.driver_id = auth.uid() and r.status = 'completed') >= 1000 as insurance_eligible,
    coalesce((select sum(c.amount) from public.driver_commissions c
      where c.driver_id = auth.uid() and c.status = 'accrued'), 0) as commission_total,
    (select count(*) from public.driver_commissions c
      where c.driver_id = auth.uid() and c.status = 'accrued') as commission_bookings;
$$;
grant execute on function public.get_my_driver_benefits() to authenticated;
