create or replace function public.require_approved_driver_kyc()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
  if new.online is true and not exists (
    select 1 from public.driver_kyc k
    where k.driver_id=new.driver_id and k.verification_status='approved'
  ) then
    raise exception 'Driver KYC approval is required before going online';
  end if;
  return new;
end;
$$;
drop trigger if exists driver_presence_requires_kyc on public.driver_presence;
create trigger driver_presence_requires_kyc
before insert or update of online on public.driver_presence
for each row execute function public.require_approved_driver_kyc();
