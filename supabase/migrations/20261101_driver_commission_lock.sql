-- Tip Car: ₹20 driver commission is due only after a passenger booking is completed.
-- Existing confirmation-time accrued entries are reversed unless already completed.
update public.driver_commissions c
set status='reversed', reversed_at=coalesce(c.reversed_at, now())
from public.bookings b
where b.id=c.booking_id and c.status='accrued' and b.status <> 'completed';

alter table public.driver_commissions
  add column if not exists paid_at timestamptz,
  add column if not exists payment_reference text,
  add column if not exists verified_by uuid references public.profiles(id);

alter table public.driver_commissions drop constraint if exists driver_commissions_status_check;
alter table public.driver_commissions add constraint driver_commissions_status_check
  check (status = any (array['accrued'::text,'reversed'::text,'paid'::text]));

create or replace function public.sync_booking_commission()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_driver_id uuid;
begin
  if new.status='completed' and (tg_op='INSERT' or old.status is distinct from new.status) then
    select r.driver_id into v_driver_id from public.rides r where r.id=new.ride_id;
    if v_driver_id is not null then
      insert into public.driver_commissions(booking_id,driver_id,passenger_id,amount,status)
      values(new.id,v_driver_id,new.passenger_id,20,'accrued')
      on conflict(booking_id) do update set driver_id=excluded.driver_id,
        passenger_id=excluded.passenger_id,amount=20,status='accrued',reversed_at=null;
    end if;
  elsif new.status='cancelled' and (tg_op='INSERT' or old.status is distinct from new.status) then
    update public.driver_commissions set status='reversed',reversed_at=now()
    where booking_id=new.id and status='accrued';
  end if;
  return new;
end; $$;

create or replace function public.create_booking(p_ride_id uuid,p_seats integer)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype; v_booking_id uuid; v_due numeric(10,2);
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_seats<1 or p_seats>8 then raise exception 'Invalid seat count'; end if;
  select * into v_ride from public.rides where id=p_ride_id and status='active' for update;
  if not found then raise exception 'Ride is not available'; end if;
  if v_ride.driver_id=auth.uid() then raise exception 'Driver cannot book own ride'; end if;
  select coalesce(sum(c.amount),0) into v_due from public.driver_commissions c
    where c.driver_id=v_ride.driver_id and c.status='accrued';
  if v_due>0 then
    raise exception 'Driver account locked: ₹% commission due. Driver must clear verified Tip Car commission before receiving new bookings.',v_due;
  end if;
  if v_ride.available_seats<p_seats then raise exception 'Not enough seats'; end if;
  update public.rides set available_seats=available_seats-p_seats,
    status=case when available_seats-p_seats=0 then 'full'::public.ride_status else status end
    where id=p_ride_id;
  insert into public.bookings(ride_id,passenger_id,seats,total_amount)
    values(p_ride_id,auth.uid(),p_seats,v_ride.fare_per_seat*p_seats)
    returning id into v_booking_id;
  return v_booking_id;
end; $$;
revoke all on function public.create_booking(uuid,integer) from public,anon;
grant execute on function public.create_booking(uuid,integer) to authenticated;

create or replace function public.driver_respond_booking(p_booking_id uuid,p_decision text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype; v_ride public.rides%rowtype; v_due numeric(10,2);
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_decision not in ('confirmed','cancelled') then raise exception 'Invalid decision'; end if;
  select b.* into v_booking from public.bookings b where b.id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  select r.* into v_ride from public.rides r where r.id=v_booking.ride_id for update;
  if not found or v_ride.driver_id<>auth.uid() then raise exception 'Only this ride driver can respond'; end if;
  if v_booking.status<>'pending' then raise exception 'Only pending bookings can be changed'; end if;
  if p_decision='confirmed' then
    select coalesce(sum(c.amount),0) into v_due from public.driver_commissions c
      where c.driver_id=auth.uid() and c.status='accrued';
    if v_due>0 then raise exception 'Driver account locked: ₹% commission due. Clear verified Tip Car commission before confirming new bookings.',v_due; end if;
  end if;
  update public.bookings set status=p_decision::public.booking_status where id=p_booking_id;
  if p_decision='cancelled' then
    update public.rides set available_seats=least(total_seats,available_seats+v_booking.seats),status='active'
      where id=v_ride.id;
  end if;
end; $$;
revoke all on function public.driver_respond_booking(uuid,text) from public,anon;
grant execute on function public.driver_respond_booking(uuid,text) to authenticated;

create or replace function public.driver_complete_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype; v_ride public.rides%rowtype;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select b.* into v_booking from public.bookings b where b.id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  select r.* into v_ride from public.rides r where r.id=v_booking.ride_id for update;
  if not found or v_ride.driver_id<>auth.uid() then raise exception 'Only this ride driver can complete the booking'; end if;
  if v_booking.status<>'confirmed' then raise exception 'Only confirmed bookings can be completed'; end if;
  if v_ride.departure_at>now() then raise exception 'This ride cannot be completed before its departure time'; end if;
  update public.bookings set status='completed'::public.booking_status where id=p_booking_id;
end; $$;
revoke all on function public.driver_complete_booking(uuid) from public,anon;
grant execute on function public.driver_complete_booking(uuid) to authenticated;

create or replace function public.admin_verify_driver_commission_payment(p_driver_id uuid,p_payment_reference text)
returns numeric language plpgsql security definer set search_path = '' as $$
declare v_total numeric(10,2);
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'::public.app_role) then
    raise exception 'Only Tip Car admins can verify commission payments';
  end if;
  if nullif(btrim(p_payment_reference),'') is null then raise exception 'Payment reference is required'; end if;
  perform 1 from public.driver_commissions c where c.driver_id=p_driver_id and c.status='accrued' for update;
  select coalesce(sum(c.amount),0) into v_total from public.driver_commissions c
    where c.driver_id=p_driver_id and c.status='accrued';
  if v_total<=0 then raise exception 'No outstanding commission is due'; end if;
  update public.driver_commissions set status='paid',paid_at=now(),
    payment_reference=btrim(p_payment_reference),verified_by=auth.uid()
    where driver_id=p_driver_id and status='accrued';
  return v_total;
end; $$;
revoke all on function public.admin_verify_driver_commission_payment(uuid,text) from public,anon;
grant execute on function public.admin_verify_driver_commission_payment(uuid,text) to authenticated;
