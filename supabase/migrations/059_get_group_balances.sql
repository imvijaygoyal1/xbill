-- 059_get_group_balances.sql
--
-- PERF-02. The home screen computed balances with **four round trips per group** — expenses,
-- members, splits, settlements — so somebody in ten groups made forty requests to render one
-- screen. PERF-01 stopped them queueing; only this reduces the count.
--
-- Returns one row per (group, member) for the caller's active, non-archived groups, carrying the
-- member's profile and their net balance in that group. That replaces the members, splits and
-- settlements fetches outright. Expenses are still fetched per group, for the Recent Expenses
-- list, which needs the rows themselves.
--
-- SECURITY INVOKER, deliberately. Every table read here is already readable by the caller through
-- the per-table queries this replaces, so RLS does the work and the function needs no privilege of
-- its own. A SECURITY DEFINER version would have to re-derive every policy it bypasses — see
-- INV-01/07/09, three production defects that came from exactly that. Anonymous callers get
-- `auth.uid() = null`, so `caller_groups` is empty and no rows come back; EXECUTE is still revoked
-- from PUBLIC and anon by name, because Supabase's ALTER DEFAULT PRIVILEGES grants it explicitly
-- and `REVOKE ... FROM PUBLIC` alone does not remove an explicit grant (migration 057 learned this
-- the hard way and had to be re-done as 058).
--
-- ## Faithfulness to the client calculation it replaces
--
-- `SplitCalculator.netBalances` is reproduced exactly, including three things that are easy to
-- miss and were each verified against production before this was written:
--
--   * `paid_by` is NULLABLE (migration 017 nulls it when a payer's account is deleted) and the
--     client SKIPS the whole expense. `where e.paid_by is not null` does the same. 0 such rows
--     today, but the column allows them.
--   * a split belonging to the payer is skipped — `s.user_id <> e.paid_by`. **45 rows in
--     production** are self-splits, so omitting this would have inflated every payer's balance.
--   * balances are keyed on members, not on whoever appears in a split. Checked: **0** users have
--     split or settlement activity in a group without a `group_members` row, so nothing is lost.
--     Membership rows are soft-deleted (`is_active`), never removed.
--
-- No rounding is applied and none is needed: `splits.amount` is `numeric(10,2)` and
-- `settlements.amount` is `numeric(20,2)`, so stored values are always exactly two decimals and
-- the client's `NSDecimalRound(2, .bankers)` is a no-op on them. Bankers' rounding and Postgres's
-- half-away-from-zero differ only at an exact half-cent, which cannot be stored.
--
-- ## Why `balance` is TEXT
--
-- PostgREST renders `numeric` as a JSON number, and decoding a JSON number into `Decimal` goes
-- through a binary floating-point representation on the way. This app's standing rule is that money
-- crosses every JSON boundary as a decimal string, so this casts to text with the scale pinned to 2
-- and the client parses it with `Decimal(string:)`.

create or replace function public.get_group_balances()
returns table (
    group_id      uuid,
    currency      text,
    user_id       uuid,
    email         text,
    display_name  text,
    avatar_url    text,
    venmo_handle  text,
    paypal_handle text,
    is_active     boolean,
    created_at    timestamptz,
    balance       text
)
language sql
stable
security invoker
set search_path = public
as $$
    with caller_groups as (
        select g.id, g.currency
          from public.groups g
          join public.group_members gm on gm.group_id = g.id
         where gm.user_id = auth.uid()
           and gm.is_active
           and g.is_archived = false
    ),
    deltas as (
        -- the payer is owed every other member's share
        select e.group_id, e.paid_by as uid, s.amount as delta
          from public.splits s
          join public.expenses e  on e.id = s.expense_id
          join caller_groups cg   on cg.id = e.group_id
         where e.paid_by is not null
           and s.user_id <> e.paid_by
        union all
        -- and each of those members owes their share
        select e.group_id, s.user_id, -s.amount
          from public.splits s
          join public.expenses e  on e.id = s.expense_id
          join caller_groups cg   on cg.id = e.group_id
         where e.paid_by is not null
           and s.user_id <> e.paid_by
        union all
        -- a recorded payment cancels debt in the direction it was made
        select st.group_id, st.from_user_id, st.amount
          from public.settlements st
          join caller_groups cg on cg.id = st.group_id
        union all
        select st.group_id, st.to_user_id, -st.amount
          from public.settlements st
          join caller_groups cg on cg.id = st.group_id
    ),
    totals as (
        select deltas.group_id, uid, sum(delta) as balance
          from deltas
         group by deltas.group_id, uid
    )
    select
        cg.id,
        cg.currency,
        gm.user_id,
        -- A member whose profile row is gone, or is invisible to the caller under the `profiles`
        -- policy, falls back to the snapshot `group_members` keeps for exactly this. Mirrors
        -- `GroupService.fetchMembers`, including the empty email it substitutes.
        coalesce(p.email, ''),
        coalesce(p.display_name, gm.display_name_snapshot, 'Deleted User'),
        coalesce(p.avatar_url, gm.avatar_url_snapshot),
        p.venmo_handle,
        p.paypal_handle,
        -- membership activeness, NOT profiles.is_active — the client overwrites the profile's flag
        -- with this one, and the two mean different things.
        gm.is_active,
        coalesce(p.created_at, gm.joined_at),
        round(coalesce(t.balance, 0), 2)::text
      from caller_groups cg
      join public.group_members gm on gm.group_id = cg.id
      left join public.profiles p  on p.id = gm.user_id
      left join totals t           on t.group_id = cg.id and t.uid = gm.user_id;
$$;

comment on function public.get_group_balances() is
    'Home screen balances: one row per (group, member) for the caller''s active, non-archived '
    'groups, with the member profile and their net balance. Replaces the per-group members, '
    'splits and settlements fetches. SECURITY INVOKER — RLS enforces access.';

revoke execute on function public.get_group_balances() from public;
revoke execute on function public.get_group_balances() from anon;
grant  execute on function public.get_group_balances() to authenticated;
