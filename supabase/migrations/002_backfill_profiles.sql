-- =============================================================================
-- Sello · 002_backfill_profiles.sql
-- Users who signed in before 001 ran have no profile row (the trigger did not
-- exist yet). Create the missing ones. Safe to run more than once.
-- =============================================================================

insert into public.profiles (id, display_name)
select u.id,
       left(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', split_part(u.email, '@', 1)), 80)
from auth.users u
on conflict (id) do nothing;
