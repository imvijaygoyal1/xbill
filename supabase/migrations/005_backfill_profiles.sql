-- =============================================================================
-- 005_backfill_profiles.sql
-- Create profiles rows for any auth.users that don't have one yet.
-- Covers accounts created before the trigger in migration 004 was set up.
-- =============================================================================
insert into public.profiles (id, email, display_name)
select
    au.id,
    coalesce(au.email, ''),
    coalesce(
        au.raw_user_meta_data->>'display_name',
        split_part(coalesce(au.email, ''), '@', 1),
        'User'
    )
from auth.users au
left join public.profiles p on p.id = au.id
where p.id is null;
