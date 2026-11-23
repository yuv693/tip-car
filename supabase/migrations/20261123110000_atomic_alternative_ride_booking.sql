-- Atomically book a scheduled fallback and cancel the passenger's still-searching taxi request.
create or replace function public.create_alternative_booking(
  p_ride_id uuid,
  p_seats integer,
  p_request_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking_id uuid;
  v_request_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_request_id is not null then
    select r.id into v_request_id
    from public.ride_requests r
    where r.id=p_request_id and r.passenger_id=auth.uid() and r.status='searching'
    for update;
    if not found then raise exception 'Your instant taxi request is no longer searching. Check its latest status before booking another ride.'; end if;
  end if;
  v_booking_id := public.create_booking(p_ride_id,p_seats);
  perform public.set_my_booking_payment_method(v_booking_id,'cash');
  if v_request_id is not null then
    update public.ride_requests set status='cancelled',updated_at=now()
    where id=v_request_id and passenger_id=auth.uid() and status='searching';
    if not found then raise exception 'Instant taxi request changed before fallback booking could finish.'; end if;
  end if;
  return v_booking_id;
end;
$function$;
revoke all on function public.create_alternative_booking(uuid,integer,uuid) from public;
revoke all on function public.create_alternative_booking(uuid,integer,uuid) from anon;
grant execute on function public.create_alternative_booking(uuid,integer,uuid) to authenticated, service_role;
