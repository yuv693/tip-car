-- Secure public driver avatars. Each signed-in user manages only their UUID folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('driver-avatars', 'driver-avatars', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=excluded.public, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Driver avatars read own folder" on storage.objects;
drop policy if exists "Driver avatars upload own folder" on storage.objects;
drop policy if exists "Driver avatars update own folder" on storage.objects;
drop policy if exists "Driver avatars delete own folder" on storage.objects;
create policy "Driver avatars read own folder" on storage.objects for select to authenticated
using (bucket_id='driver-avatars' and (storage.foldername(name))[1]=(select auth.uid()::text));
create policy "Driver avatars upload own folder" on storage.objects for insert to authenticated
with check (bucket_id='driver-avatars' and (storage.foldername(name))[1]=(select auth.uid()::text));
create policy "Driver avatars update own folder" on storage.objects for update to authenticated
using (bucket_id='driver-avatars' and (storage.foldername(name))[1]=(select auth.uid()::text))
with check (bucket_id='driver-avatars' and (storage.foldername(name))[1]=(select auth.uid()::text));
create policy "Driver avatars delete own folder" on storage.objects for delete to authenticated
using (bucket_id='driver-avatars' and (storage.foldername(name))[1]=(select auth.uid()::text));

alter table public.bookings add column if not exists payment_method text;
alter table public.bookings drop constraint if exists bookings_payment_method_check;
alter table public.bookings add constraint bookings_payment_method_check
check (payment_method is null or payment_method in ('cash','upi'));

create or replace function public.set_my_booking_payment_method(p_booking_id uuid, p_method text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if p_method not in ('cash','upi') then raise exception 'Unsupported payment method'; end if;
  update public.bookings
  set payment_method=p_method,
      payment_status=case when p_method='upi' then 'pending'::public.payment_status else 'unpaid'::public.payment_status end
  where id=p_booking_id and passenger_id=auth.uid()
    and status='pending' and payment_status='unpaid';
  if not found then raise exception 'Booking not found or payment method cannot be changed'; end if;
end;
$$;
revoke all on function public.set_my_booking_payment_method(uuid,text) from public,anon;
grant execute on function public.set_my_booking_payment_method(uuid,text) to authenticated;
