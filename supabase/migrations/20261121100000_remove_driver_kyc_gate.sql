-- Tip Car keeps ride booking simple: no KYC/admin approval gate for drivers.
drop trigger if exists driver_presence_requires_kyc on public.driver_presence;
drop function if exists public.require_approved_driver_kyc();
