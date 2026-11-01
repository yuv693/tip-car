-- Tip Car booking history and safe driver/passenger booking actions.

drop policy if exists "rides public active read" on public.rides;
create policy "rides public active read" on public.rides
for select to anon, authenticated
using (
  status in ('active','full')
  or driver_id = auth.uid()
  or exists (
    select 1 from public.bookings b
    where b.ride_id = rides.id and b.passenger_id = auth.uid()
  )
);

create or replace function public.driver_respond_booking(
  p_booking_id uuid,
  p_decision text
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype; v_ride public.rides%rowtype;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_decision not in ('confirmed','cancelled') then raise exception 'Invalid decision'; end if;
  select b.* into v_booking from public.bookings b where b.id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  select r.* into v_ride from public.rides r where r.id=v_booking.ride_id for update;
  if not found or v_ride.driver_id <> auth.uid() then raise exception 'Only this ride driver can respond'; end if;
  if v_booking.status <> 'pending' then raise exception 'Only pending bookings can be changed'; end if;
  update public.bookings set status=p_decision::public.booking_status where id=p_booking_id;
  if p_decision='cancelled' then
    update public.rides set available_seats=least(total_seats,available_seats+v_booking.seats), status='active'
    where id=v_ride.id;
  end if;
end; $$;
revoke all on function public.driver_respond_booking(uuid,text) from public;
grant execute on function public.driver_respond_booking(uuid,text) to authenticated;

create or replace function public.cancel_my_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select b.* into v_booking from public.bookings b
   where b.id=p_booking_id and b.passenger_id=auth.uid() for update;
  if not found then raise exception 'Your booking was not found'; end if;
  if v_booking.status not in ('pending','confirmed') then raise exception 'This booking cannot be cancelled'; end if;
  update public.bookings set status='cancelled' where id=p_booking_id;
  update public.rides set available_seats=least(total_seats,available_seats+v_booking.seats), status='active'
   where id=v_booking.ride_id;
end; $$;
revoke all on function public.cancel_my_booking(uuid) from public;
grant execute on function public.cancel_my_booking(uuid) to authenticated;
