-- Migration 040: server-backed in-app notifications.
-- Edge Functions insert rows with the service role; clients can only read and
-- mutate their own rows. The recipient-scoped dedupe key makes retries
-- idempotent across APNs and Activity refreshes.

CREATE TABLE IF NOT EXISTS public.notifications (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    dedupe_key   text NOT NULL UNIQUE,
    event_type   text NOT NULL CHECK (event_type IN ('expenseAdded', 'settlementMade', 'commentAdded', 'friendRequest')),
    title        text NOT NULL,
    subtitle     text NOT NULL,
    amount       numeric(20, 2) NOT NULL DEFAULT 0,
    currency     text NOT NULL DEFAULT 'USD',
    category     text NOT NULL DEFAULT 'other',
    group_id     uuid REFERENCES public.groups(id) ON DELETE SET NULL,
    expense_id   uuid REFERENCES public.expenses(id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    read_at      timestamptz
);

CREATE INDEX IF NOT EXISTS notifications_recipient_created_idx
    ON public.notifications (recipient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS notifications_recipient_unread_idx
    ON public.notifications (recipient_id)
    WHERE read_at IS NULL;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own notifications" ON public.notifications;
CREATE POLICY "Users read own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "Users update own notifications" ON public.notifications;
CREATE POLICY "Users update own notifications"
    ON public.notifications FOR UPDATE
    USING (auth.uid() = recipient_id)
    WITH CHECK (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "Users delete own notifications" ON public.notifications;
CREATE POLICY "Users delete own notifications"
    ON public.notifications FOR DELETE
    USING (auth.uid() = recipient_id);
