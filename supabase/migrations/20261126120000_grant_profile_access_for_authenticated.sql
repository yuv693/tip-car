-- Permit signed-in/anonymous-authenticated Tip Car clients to perform profile writes.
-- Row-level security still limits each non-owner to their own profile and forbids self-promotion.
grant select, insert, update on table public.profiles to authenticated;
