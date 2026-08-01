-- Migration 041: settlements ledger.
--
-- Replaces `splits.is_settled` as the record of who has paid whom. A payment is its own
-- row — attributable, deletable, and an arbitrary amount — so balances are derived by
-- arithmetic rather than by flipping flags on individual expense shares.
--
-- See docs/superpowers/specs/2026-07-28-settlements-ledger-design.md
-- `splits.is_settled` is intentionally left in place, unread and unwritten, for one
-- release so the original state can be re-derived if the backfill proves wrong.

CREATE TABLE IF NOT EXISTS public.settlements (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    from_user_id uuid NOT NULL,
    to_user_id   uuid NOT NULL,
    amount       numeric(20, 2) NOT NULL CHECK (amount > 0),
    currency     text NOT NULL,
    recorded_by  uuid NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlements_distinct_parties CHECK (from_user_id <> to_user_id)
);

-- No FK on the three user columns: migration 035 set this precedent for splits.user_id.
-- If an account is deleted the payment history must survive, or every other member's
-- balance silently changes.
--
-- Scope of that guarantee: existing settlement rows survive. Recording a NEW settlement
-- involving a deleted account is NOT possible, because the INSERT policy's group_members
-- EXISTS checks depend on rows that DO cascade on account deletion (migration 001).
-- Historical balances stay correct; new payments to or from a deleted account cannot be
-- recorded. Accepted.

CREATE INDEX IF NOT EXISTS settlements_group_created_idx
    ON public.settlements (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS settlements_group_pair_idx
    ON public.settlements (group_id, from_user_id, to_user_id);

ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "settlements: group members read" ON public.settlements;
CREATE POLICY "settlements: group members read"
    ON public.settlements FOR SELECT
    USING (public.is_group_member(group_id));

DROP POLICY IF EXISTS "settlements: a party records their own" ON public.settlements;
CREATE POLICY "settlements: a party records their own"
    ON public.settlements FOR INSERT
    WITH CHECK (
        recorded_by = auth.uid()
        AND auth.uid() IN (from_user_id, to_user_id)
        AND public.is_group_member(group_id)
        -- Both parties must belong to the group, or a member could insert a payment
        -- against an arbitrary UUID. is_active is deliberately NOT required: someone who
        -- has left the group can still owe money that needs settling.
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = from_user_id)
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = to_user_id)
    );

DROP POLICY IF EXISTS "settlements: recorder deletes" ON public.settlements;
CREATE POLICY "settlements: recorder deletes"
    ON public.settlements FOR DELETE
    USING (recorded_by = auth.uid());

-- No UPDATE policy: corrections are delete-then-record.

-- Backfill: one settlement per settled split. recorded_by is the debtor because, under the
-- RLS in force until now (auth.uid() = user_id), only the debtor could have settled it.
INSERT INTO public.settlements
    (group_id, from_user_id, to_user_id, amount, currency, recorded_by, created_at)
SELECT e.group_id, s.user_id, e.paid_by, s.amount, e.currency, s.user_id,
       COALESCE(s.settled_at, e.created_at)
FROM public.splits s
JOIN public.expenses e ON e.id = s.expense_id
WHERE s.is_settled
  AND e.paid_by IS NOT NULL
  AND e.paid_by <> s.user_id
  -- `splits.amount` permits 0.00 (`CHECK (amount >= 0)`); `settlements.amount` requires
  -- `> 0`. A single settled 0.00 non-payer split would therefore violate the CHECK and roll
  -- the ENTIRE migration back -- table, policies, indexes and all. Excluding it is not a
  -- balance change: a 0.00 split contributes 0 under both models, so there is nothing for a
  -- settlement row to offset. Verified read-only against production 2026-07-31: zero splits
  -- of any kind have amount = 0, so this guard is insurance against future data, not a fix
  -- for existing rows.
  AND s.amount > 0
  -- One-time backfill. The INSERT has no natural key to conflict on, so a second run would
  -- insert a duplicate set and silently double the offset, corrupting every balance. This
  -- project has already had one migration-history desync (031_remote_history_placeholder.sql),
  -- so guard explicitly rather than rely on `db push` running each file once.
  AND NOT EXISTS (SELECT 1 FROM public.settlements);
