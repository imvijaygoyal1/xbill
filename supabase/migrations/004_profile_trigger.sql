-- =============================================================================
-- 004_profile_trigger.sql
-- Auto-create a profiles row whenever a new auth.users row is inserted.
-- Runs as security definer (elevated privileges) so it bypasses RLS.
-- display_name is read from user metadata set during signUp.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, display_name)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(
            new.raw_user_meta_data->>'display_name',
            split_part(coalesce(new.email, ''), '@', 1),
            'User'
        )
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

-- Fire after every new signup
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
