-- Store an optional emergency contact number for the signed-in user.
alter table public.profiles
  add column if not exists emergency_contact_phone text;

comment on column public.profiles.emergency_contact_phone is
  'Optional user-provided emergency contact number; not verified by Tip Car.';
