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

 
create table if not exists private.tipcar_owner_activation_codes (
  activation_code text primary key,
  used_at timestamptz,
  used_by uuid,
  created_at timestamptz not null default now()
);
revoke all on private.tipcar_owner_activation_codes from public, anon, authenticated;

create or replace function private.claim_tipcar_owner(p_activation_code text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Sign in is required';
  end if;
  if p_activation_code is null or length(trim(p_activation_code)) < 40 then
    raise exception 'Invalid owner activation code';
  end if;
  select activation_code into v_code
  from private.tipcar_owner_activation_codes
  where activation_code = trim(p_activation_code) and used_at is null
  for update;
  if v_code is null then
    raise exception 'Owner activation code is invalid or already used';
  end if;
  update public.profiles set role = 'admin'::public.app_role where id = auth.uid();
  if not found then
    raise exception 'Create your Tip Car profile first';
  end if;
  update private.tipcar_owner_activation_codes
  set used_at = now(), used_by = auth.uid()
  where activation_code = v_code;
  return true;
end;
$$;
revoke all on function private.claim_tipcar_owner(text) from public, anon;
grant execute on function private.claim_tipcar_owner(text) to authenticated;

create or replace function public.claim_tipcar_owner(p_activation_code text)
returns boolean
language sql
security invoker
set search_path = pg_catalog, public, private
as $$
  select private.claim_tipcar_owner(p_activation_code);
$$;
revoke all on function public.claim_tipcar_owner(text) from public, anon;
grant execute on function public.claim_tipcar_owner(text) to authenticated;

-- For a fresh environment, create a fresh one-time code with:
-- insert into private.tipcar_owner_activation_codes(activation_code)
-- values (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''));
