-- =============================================================================
-- 006_groups_currency_member_rls.sql
-- 1. Add currency column to groups (default USD)
-- 2. Fix group_members RLS so a group creator can insert themselves as the
--    first member (before they appear in is_group_member)
-- =============================================================================

-- 1. Currency
alter table public.groups
    add column if not exists currency text not null default 'USD';

-- 2. Replace the overly-restrictive insert policy
drop policy if exists "group_members: members can insert" on public.group_members;

create policy "group_members: members can insert"
    on public.group_members for insert
    with check (
        -- Existing members can invite others
        public.is_group_member(group_id)
        or
        -- Group creator can add themselves as the founding member
        (
            auth.uid() = user_id
            and exists (
                select 1 from public.groups g
                where g.id    = group_id
                  and g.created_by = auth.uid()
            )
        )
    );
