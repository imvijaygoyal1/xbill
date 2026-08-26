-- 049_notification_preferences.sql
--
-- PUSH-01. The Profile toggle titled "New Expenses" decided whether **other people** were
-- notified when **you** added an expense:
--
--     // AddExpenseViewModel.swift
--     if CacheService.defaults.bool(forKey: NotificationService.expensePreferenceKey) {
--         await notifyExpenseAdded(...)
--     }
--
-- Nobody reads that label that way, and `xBillApp.swift` registered the default as **false**. So a
-- payer who had never opened Profile silently suppressed notifications for their whole group, and
-- the recipient's own preference was never consulted at any point.
--
-- It could not have been consulted: the preference lived in `UserDefaults` on the sender's device,
-- and the only place that can honour a *recipient's* choice is the server. `public.notifications`
-- stores delivered rows, not settings. This table is the missing place.
--
-- Scope: **push only.** The in-app Activity row is still written for every event regardless of
-- these columns. Turning off a push means "do not interrupt me", not "hide this from my history" —
-- and a notification row that was never recorded cannot be caught up on later.

CREATE TABLE IF NOT EXISTS public.notification_preferences (
    user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    expenses        boolean     NOT NULL DEFAULT true,
    settlements     boolean     NOT NULL DEFAULT true,
    comments        boolean     NOT NULL DEFAULT true,
    friend_requests boolean     NOT NULL DEFAULT true,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Defaults are ON, and a **missing row also means on** — the functions treat "no row" as consent.
--
-- That is not a shortcut. iOS is the real consent gate: nothing is displayed unless the user
-- granted notification permission, and this app deletes its device token when it finds permission
-- revoked, so a token only exists for someone who said yes. Defaulting to off would reproduce the
-- exact silence this migration exists to end, and would require every existing user to discover a
-- setting in order to receive anything.

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Owner-only, in every direction. These are settings, not shared data: nobody else may read what
-- you have muted, and nobody else may mute you. The notify functions run with the service role,
-- which bypasses RLS, and read this table on the recipient's behalf.
DROP POLICY IF EXISTS "Users read own notification preferences"   ON public.notification_preferences;
DROP POLICY IF EXISTS "Users insert own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "Users update own notification preferences" ON public.notification_preferences;

CREATE POLICY "Users read own notification preferences"
    ON public.notification_preferences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users insert own notification preferences"
    ON public.notification_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- WITH CHECK as well as USING: without it a user could update their row to carry someone else's
-- `user_id`. That is the gap migration 027 closed on four other tables (CRIT-03…CRIT-07).
CREATE POLICY "Users update own notification preferences"
    ON public.notification_preferences FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- No DELETE policy, deliberately. Deleting a row means "reset to defaults", which is what setting
-- every column back to true already does — and a second way to express one state is a second thing
-- that can disagree. Same reasoning as the absent UPDATE policy on `settlements` (041).
--
-- ⚠️ Consequence, observed while verifying this migration: a client DELETE matches zero rows and
-- PostgREST answers **204 No Content** — indistinguishable from having deleted something. Do not
-- add a delete path to the app believing it works; reset with an UPDATE setting every column true.
-- This is the same trap as using `.single()` as an affected-row check (`NOTIF-01`): the status
-- code describes the request, not whether any row was touched.

CREATE OR REPLACE FUNCTION public.touch_notification_preferences()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notification_preferences_touch ON public.notification_preferences;
CREATE TRIGGER notification_preferences_touch
    BEFORE UPDATE ON public.notification_preferences
    FOR EACH ROW EXECUTE FUNCTION public.touch_notification_preferences();

COMMENT ON TABLE public.notification_preferences IS
    'Per-recipient push preferences. A missing row means all categories are on — iOS permission '
    'is the real consent gate. Read by the notify Edge Functions with the service role; the '
    'sender never decides whether a recipient hears about something. See migration 049.';
