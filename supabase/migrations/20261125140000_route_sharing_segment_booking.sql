-- Tip Car route-sharing: ordered stops, segment seat capacity and atomic booking.
create table if not exists public.ride_stops (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  stop_order integer not null check (stop_order >= 0),
  location_name text not null check (length(trim(location_name)) > 0),
  planned_at timestamptz,
  created_at timestamptz not null default now(),
  unique (ride_id, stop_order)
);
alter table public.bookings
  add column if not exists pickup_stop_order integer not null default 0,
  add column if not exists dropoff_stop_order integer not null default 1,
  add column if not exists segment_booking boolean not null default false;
alter table public.ride_stops enable row level security;
drop policy if exists "ride stops visible to signed-in travellers" on public.ride_stops;
create policy "ride stops visible to signed-in travellers"
on public.ride_stops for select to authenticated
using (
  exists (
    select 1 from public.rides r
    where r.id = ride_stops.ride_id
      and (r.status in ('active','full') or r.driver_id = auth.uid()
        or exists (select 1 from public.bookings b
          where b.ride_id = r.id and b.passenger_id = auth.uid()
            and b.status in ('pending','confirmed')))
  )
);
drop policy if exists "drivers manage own ride stops" on public.ride_stops;
create policy "drivers manage own ride stops"
on public.ride_stops for all to authenticated
using (exists (select 1 from public.rides r where r.id=ride_stops.ride_id and r.driver_id=auth.uid()))
with check (exists (select 1 from public.rides r where r.id=ride_stops.ride_id and r.driver_id=auth.uid()));
create index if not exists ride_stops_route_order_idx on public.ride_stops(ride_id, stop_order);
create index if not exists bookings_segment_capacity_idx
on public.bookings(ride_id, pickup_stop_order, dropoff_stop_order)
where status in ('pending','confirmed');

insert into public.ride_stops(ride_id,stop_order,location_name)
select r.id,0,r.origin from public.rides r
where not exists(select 1 from public.ride_stops s where s.ride_id=r.id)
on conflict(ride_id,stop_order) do nothing;
insert into public.ride_stops(ride_id,stop_order,location_name)
select r.id,1,r.destination from public.rides r
where (select count(*) from public.ride_stops s where s.ride_id=r.id)=1
on conflict(ride_id,stop_order) do nothing;

create or replace function public.publish_route_ride(
 p_vehicle_type text,p_vehicle_name text,p_vehicle_number text,
 p_origin text,p_destination text,p_departure_at timestamptz,
 p_total_seats integer,p_fare_per_seat numeric,p_intermediate_stops text[] default '{}'
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_id uuid; v_stop text; v_order integer:=1;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('driver','admin')) then
   raise exception 'A driver account is required to publish a ride';
 end if;
 if trim(coalesce(p_vehicle_name,''))='' or trim(coalesce(p_vehicle_number,''))='' or
    trim(coalesce(p_origin,''))='' or trim(coalesce(p_destination,''))='' then
   raise exception 'Complete vehicle and route details';
 end if;
 if p_departure_at<=now() then raise exception 'Choose a future departure time'; end if;
 if p_total_seats<1 or p_total_seats>60 or p_fare_per_seat<0 then raise exception 'Check seats and fare';
 end if;
 if coalesce(array_length(p_intermediate_stops,1),0)>8 then raise exception 'Maximum 8 intermediate stops'; end if;
 insert into public.rides(driver_id,vehicle_type,vehicle_name,vehicle_number,origin,destination,departure_at,total_seats,available_seats,fare_per_seat)
 values(auth.uid(),p_vehicle_type::public.vehicle_type,trim(p_vehicle_name),trim(p_vehicle_number),
        trim(p_origin),trim(p_destination),p_departure_at,p_total_seats,p_total_seats,p_fare_per_seat)
 returning id into v_id;
 insert into public.ride_stops(ride_id,stop_order,location_name) values(v_id,0,trim(p_origin));
 if p_intermediate_stops is not null then
   foreach v_stop in array p_intermediate_stops loop
     if trim(coalesce(v_stop,''))='' then raise exception 'Intermediate stop cannot be empty'; end if;
     if lower(trim(v_stop)) in (lower(trim(p_origin)),lower(trim(p_destination))) then
       raise exception 'Remove duplicate origin or destination from intermediate stops';
     end if;
     insert into public.ride_stops(ride_id,stop_order,location_name) values(v_id,v_order,trim(v_stop));
     v_order:=v_order+1;
   end loop;
 end if;
 insert into public.ride_stops(ride_id,stop_order,location_name) values(v_id,v_order,trim(p_destination));
 return v_id;
end;
$function$;
revoke all on function public.publish_route_ride(text,text,text,text,text,timestamptz,integer,numeric,text[]) from public,anon;
grant execute on function public.publish_route_ride(text,text,text,text,text,timestamptz,integer,numeric,text[]) to authenticated;

create or replace function public.search_route_segment_matches(
 p_origin text,p_destination text,p_min_seats integer default 1
) returns table (
 ride_id uuid,driver_id uuid,vehicle_type public.vehicle_type,vehicle_name text,
 vehicle_number text,origin text,destination text,departure_at timestamptz,
 total_seats integer,available_seats integer,fare_per_seat numeric,status public.ride_status,
 pickup_stop_order integer,dropoff_stop_order integer,segment_available_seats integer,segment_fare numeric
)
language sql stable security definer set search_path=''
as $function$
 select r.id,r.driver_id,r.vehicle_type,r.vehicle_name,r.vehicle_number,r.origin,r.destination,
        r.departure_at,r.total_seats,r.available_seats,r.fare_per_seat,r.status,
        a.stop_order,b.stop_order,cap.free_seats,r.fare_per_seat*(b.stop_order-a.stop_order)
 from public.rides r
 join public.ride_stops a on a.ride_id=r.id
 join public.ride_stops b on b.ride_id=r.id and b.stop_order>a.stop_order
 cross join lateral (
   select min(r.total_seats-coalesce((
     select sum(booked.seats)::integer from public.bookings booked
     where booked.ride_id=r.id and booked.status in ('pending','confirmed')
       and booked.pickup_stop_order<=leg.leg_no and booked.dropoff_stop_order>leg.leg_no
   ),0))::integer as free_seats
   from generate_series(a.stop_order,b.stop_order-1) as leg(leg_no)
 ) cap
 where auth.uid() is not null and r.status in ('active','full') and r.departure_at>now()
   and cap.free_seats>=greatest(1,least(coalesce(p_min_seats,1),8))
   and lower(trim(a.location_name))=lower(trim(p_origin))
   and lower(trim(b.location_name))=lower(trim(p_destination))
 order by r.fare_per_seat*(b.stop_order-a.stop_order),r.departure_at
 limit 50;
$function$;
revoke all on function public.search_route_segment_matches(text,text,integer) from public,anon;
grant execute on function public.search_route_segment_matches(text,text,integer) to authenticated;

create or replace function public.create_route_segment_booking(
 p_ride_id uuid,p_pickup_stop_order integer,p_dropoff_stop_order integer,p_seats integer
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_ride public.rides%rowtype; v_booking_id uuid; v_free integer; v_due numeric(10,2);
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if p_seats<1 or p_seats>8 then raise exception 'Invalid seat count'; end if;
 if p_pickup_stop_order<0 or p_dropoff_stop_order<=p_pickup_stop_order then
   raise exception 'Choose a valid pickup and later drop-off stop';
 end if;
 select * into v_ride from public.rides where id=p_ride_id for update;
 if not found or v_ride.status not in ('active','full') then raise exception 'Ride is not available'; end if;
 if v_ride.driver_id=auth.uid() then raise exception 'Driver cannot book own ride'; end if;
 select coalesce(sum(c.amount),0) into v_due from public.driver_commissions c
 where c.driver_id=v_ride.driver_id and c.status='accrued';
 if v_due>0 then
   raise exception 'Driver account locked: ₹% commission due. Driver must clear verified Tip Car commission before receiving new bookings.',v_due;
 end if;
 if not exists(select 1 from public.ride_stops s where s.ride_id=p_ride_id and s.stop_order=p_pickup_stop_order)
    or not exists(select 1 from public.ride_stops s where s.ride_id=p_ride_id and s.stop_order=p_dropoff_stop_order) then
   raise exception 'Selected stops are not on this route';
 end if;
 select min(v_ride.total_seats-coalesce((
   select sum(b.seats)::integer from public.bookings b
   where b.ride_id=p_ride_id and b.status in ('pending','confirmed')
     and b.pickup_stop_order<=leg.leg_no and b.dropoff_stop_order>leg.leg_no
 ),0)) into v_free
 from generate_series(p_pickup_stop_order,p_dropoff_stop_order-1) as leg(leg_no);
 if coalesce(v_free,0)<p_seats then raise exception 'Not enough seats on one or more route segments'; end if;
 insert into public.bookings(ride_id,passenger_id,seats,total_amount,pickup_stop_order,dropoff_stop_order,segment_booking)
 values(p_ride_id,auth.uid(),p_seats,
   v_ride.fare_per_seat*(p_dropoff_stop_order-p_pickup_stop_order)*p_seats,
   p_pickup_stop_order,p_dropoff_stop_order,true)
 returning id into v_booking_id;
 return v_booking_id;
end;
$function$;
revoke all on function public.create_route_segment_booking(uuid,integer,integer,integer) from public,anon;
grant execute on function public.create_route_segment_booking(uuid,integer,integer,integer) to authenticated;

create or replace function public.cancel_my_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_booking public.bookings%rowtype;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 select b.* into v_booking from public.bookings b
 where b.id=p_booking_id and b.passenger_id=auth.uid() for update;
 if not found then raise exception 'Your booking was not found'; end if;
 if v_booking.status not in ('pending','confirmed') then raise exception 'This booking cannot be cancelled'; end if;
 update public.bookings set status='cancelled' where id=p_booking_id;
 if not v_booking.segment_booking then
   update public.rides set available_seats=least(total_seats,available_seats+v_booking.seats),status='active'
   where id=v_booking.ride_id;
 end if;
end;
$function$;
revoke all on function public.cancel_my_booking(uuid) from public,anon;
grant execute on function public.cancel_my_booking(uuid) to authenticated,service_role;
