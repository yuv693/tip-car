create schema if not exists private;

create or replace function private.is_tipcar_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((
    select p.role = 'admin'::public.app_role
    from public.profiles p
    where p.id = (select auth.uid())
  ), false);
$$;

revoke all on function private.is_tipcar_admin() from public;
grant usage on schema private to authenticated;
grant execute on function private.is_tipcar_admin() to authenticated;

drop policy if exists "profiles read self or admin" on public.profiles;
create policy "profiles read self or admin"
on public.profiles for select
to authenticated
using (id = (select auth.uid()) or (select private.is_tipcar_admin()));

drop policy if exists "admin update driver profiles" on public.profiles;
create policy "admin update driver profiles"
on public.profiles for update
to authenticated
using ((select private.is_tipcar_admin()))
with check ((select private.is_tipcar_admin()));

drop policy if exists "admin read all driver presence" on public.driver_presence;
create policy "admin read all driver presence"
on public.driver_presence for select
to authenticated
using ((select private.is_tipcar_admin()));

drop policy if exists "admin update all driver presence" on public.driver_presence;
create policy "admin update all driver presence"
on public.driver_presence for update
to authenticated
using ((select private.is_tipcar_admin()))
with check ((select private.is_tipcar_admin()));
