-- Tip Car & Bus database schema for Supabase PostgreSQL
create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('passenger','driver','admin');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.vehicle_type as enum ('car','bus');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.ride_status as enum ('active','full','cancelled','completed');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.booking_status as enum ('pending','confirmed','cancelled','completed');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.payment_status as enum ('unpaid','pending','paid','failed','refunded');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text unique,
  role public.app_role not null default 'passenger',
  created_at timestamptz not null default now()
);
create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id),
  vehicle_type public.vehicle_type not null default 'car',
  vehicle_name text not null,
  vehicle_number text not null,
  origin text not null,
  destination text not null,
  departure_at timestamptz not null,
  total_seats integer not null check (total_seats between 1 and 60),
  available_seats integer not null check (available_seats between 0 and 60),
  fare_per_seat numeric(10,2) not null check (fare_per_seat >= 0),
  status public.ride_status not null default 'active',
  notes text,
  created_at timestamptz not null default now(),
  check (available_seats <= total_seats),
  check (length(trim(origin)) > 0 and length(trim(destination)) > 0)
);
create index if not exists rides_route_departure_idx
  on public.rides (lower(origin), lower(destination), departure_at)
  where status = 'active';
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id),
  passenger_id uuid not null references public.profiles(id),
  seats integer not null check (seats between 1 and 8),
  total_amount numeric(10,2) not null check (total_amount >= 0),
  status public.booking_status not null default 'pending',
  payment_status public.payment_status not null default 'unpaid',
  gateway_order_id text,
  gateway_payment_id text,
  created_at timestamptz not null default now(),
  unique (ride_id, passenger_id, status)
);

create or replace function public.create_booking(p_ride_id uuid, p_seats integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_booking_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_seats < 1 or p_seats > 8 then raise exception 'Invalid seat count'; end if;
  select * into v_ride from public.rides where id = p_ride_id and status = 'active' for update;
  if not found then raise exception 'Ride is not available'; end if;
  if v_ride.driver_id = auth.uid() then raise exception 'Driver cannot book own ride'; end if;
  if v_ride.available_seats < p_seats then raise exception 'Not enough seats'; end if;
  update public.rides set available_seats = available_seats - p_seats,
    status = case when available_seats - p_seats = 0 then 'full'::public.ride_status else status end
    where id = p_ride_id;
  insert into public.bookings(ride_id, passenger_id, seats, total_amount)
    values (p_ride_id, auth.uid(), p_seats, v_ride.fare_per_seat * p_seats)
    returning id into v_booking_id;
  return v_booking_id;
end; $$;
revoke all on function public.create_booking(uuid, integer) from public;
grant execute on function public.create_booking(uuid, integer) to authenticated;

alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.bookings enable row level security;

drop policy if exists "profiles read self or admin" on public.profiles;
create policy "profiles read self or admin" on public.profiles for select to authenticated
using (id = auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "profiles update self" on public.profiles;
create policy "profiles update self" on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid() and role <> 'admin');
drop policy if exists "profiles insert self" on public.profiles;
create policy "profiles insert self" on public.profiles for insert to authenticated
with check (id = auth.uid() and role <> 'admin');
drop policy if exists "rides public active read" on public.rides;
create policy "rides public active read" on public.rides for select to anon, authenticated
using (status in ('active','full') or driver_id = auth.uid());
drop policy if exists "driver create own rides" on public.rides;
create policy "driver create own rides" on public.rides for insert to authenticated
with check (driver_id = auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('driver','admin')));
drop policy if exists "driver update own rides" on public.rides;
create policy "driver update own rides" on public.rides for update to authenticated
using (driver_id = auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check (driver_id = auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "booking passenger or ride driver read" on public.bookings;
create policy "booking passenger or ride driver read" on public.bookings for select to authenticated
using (passenger_id = auth.uid() or exists(select 1 from public.rides r where r.id=ride_id and r.driver_id=auth.uid())
  or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "passenger create booking" on public.bookings;
create policy "passenger create booking" on public.bookings for insert to authenticated
with check (passenger_id = auth.uid());
-- No client UPDATE policy: payment state must be set by a trusted server-side webhook.


-- Driver benefits additions (also available as a versioned migration).
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
