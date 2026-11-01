-- Secure public driver avatars: users can manage only their own UUID folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('driver-avatars', 'driver-avatars', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Driver avatars read own folder" on storage.objects;
drop policy if exists "Driver avatars upload own folder" on storage.objects;
drop policy if exists "Driver avatars update own folder" on storage.objects;
drop policy if exists "Driver avatars delete own folder" on storage.objects;

create policy "Driver avatars read own folder"
on storage.objects for select to authenticated
using (bucket_id = 'driver-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "Driver avatars upload own folder"
on storage.objects for insert to authenticated
with check (bucket_id = 'driver-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "Driver avatars update own folder"
on storage.objects for update to authenticated
using (bucket_id = 'driver-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text))
with check (bucket_id = 'driver-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "Driver avatars delete own folder"
on storage.objects for delete to authenticated
using (bucket_id = 'driver-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));
