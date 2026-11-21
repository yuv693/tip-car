-- Unified Tip Car commission and driver reward rules.
-- ₹20 is accrued only after a scheduled booking OR an instant taxi request is completed.
-- Cancelled rides never earn commission. One completed booking/request = one completed ride.

alter table public.driver_commissions
  alter column booking_id drop not null;

alter table public.driver_commissions
  add column if not exists ride_request_id uuid references public.ride_requests(id) on delete restrict;

create unique index if not exists driver_commissions_ride_request_uidx
  on public.driver_commissions(ride_request_id)
  where ride_request_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'driver_commissions_one_ride_source'
      and conrelid = 'public.driver_commissions'::regclass
  ) then
    alter table public.driver_commissions
      add constraint driver_commissions_one_ride_source
      check ((booking_id is not null and ride_request_id is null)
          or (booking_id is null and ride_request_id is not null));
  end if;
end $$;

-- Correct the previous behaviour: a confirmed-but-not-completed booking is not chargeable.
update public.driver_commissions dc
set status = 'reversed', reversed_at = now()
from public.bookings b
where dc.booking_id = b.id
  and b.status <> 'completed'
  and dc.status = 'accrued';

create or replace function public.sync_booking_commission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_driver_id uuid;
begin
  if new.status = 'completed'
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    select r.driver_id into v_driver_id
    from public.rides r where r.id = new.ride_id;
    if v_driver_id is not null then
      insert into public.driver_commissions(booking_id, ride_request_id, driver_id, passenger_id, amount, status, reversed_at)
      values (new.id, null, v_driver_id, new.passenger_id, 20, 'accrued', null)
      on conflict (booking_id) do update
        set status = 'accrued', reversed_at = null;
    end if;
  elsif new.status = 'cancelled'
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    update public.driver_commissions
       set status = 'reversed', reversed_at = now()
     where booking_id = new.id and status = 'accrued';
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_commission_sync on public.bookings;
create trigger bookings_commission_sync
after insert or update of status on public.bookings
for each row execute function public.sync_booking_commission();

create or replace function public.sync_instant_taxi_commission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed'
     and old.status is distinct from new.status
     and new.driver_id is not null then
    insert into public.driver_commissions(
      booking_id, ride_request_id, driver_id, passenger_id, amount, status, reversed_at
    ) values (
      null, new.id, new.driver_id, new.passenger_id, 20, 'accrued', null
    )
    on conflict (ride_request_id) where ride_request_id is not null
    do update set status = 'accrued', reversed_at = null;
  elsif new.status = 'cancelled' and old.status is distinct from new.status then
    update public.driver_commissions
       set status = 'reversed', reversed_at = now()
     where ride_request_id = new.id and status = 'accrued';
  end if;
  return new;
end;
$$;

drop trigger if exists ride_requests_commission_sync on public.ride_requests;
create trigger ride_requests_commission_sync
after update of status on public.ride_requests
for each row execute function public.sync_instant_taxi_commission();

create or replace function public.get_my_driver_benefits()
returns table (
  completed_rides bigint,
  insurance_eligible boolean,
  commission_total numeric,
  commission_bookings bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with completed as (
    select count(*)::bigint as total
    from public.bookings b
    join public.rides r on r.id = b.ride_id
    where r.driver_id = auth.uid() and b.status = 'completed'
    union all
    select count(*)::bigint
    from public.ride_requests rr
    where rr.driver_id = auth.uid() and rr.status = 'completed'
  ), totals as (
    select coalesce(sum(total), 0)::bigint as ride_count from completed
  )
  select
    totals.ride_count,
    totals.ride_count >= 1000,
    coalesce((select sum(dc.amount) from public.driver_commissions dc
      where dc.driver_id = auth.uid() and dc.status = 'accrued'), 0),
    (select count(*) from public.driver_commissions dc
      where dc.driver_id = auth.uid() and dc.status = 'accrued')
  from totals;
$$;

grant execute on function public.get_my_driver_benefits() to authenticated;
