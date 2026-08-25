-- 048_device_token_environment.sql
--
-- PUSH-02. Push notifications were not delivered, for a reason no client change alone can fix.
--
-- All four notify functions chose the APNs host from `isDevelopment`, a flag the **sender's** app
-- puts in the request body from its own `#if DEBUG`. But sandbox-vs-production is a property of
-- the **recipient's token** — of how *their* copy of the app was signed. An App Store sender
-- notifying a debug-build recipient posted a sandbox token to the production host; a debug sender
-- did the reverse. APNs answers `BadDeviceToken` and the function counted it as nothing.
--
-- `device_tokens` recorded no environment at all, so the function could not have routed correctly
-- even if it had wanted to. This column is the missing fact.
--
-- Existing rows default to 'production'. That is right for every user on the App Store build, and
-- wrong only for a device currently running a debug build — which is already wrong today, and
-- corrects itself the next time that device launches a version that writes the column. There is
-- no way to recover the true value for a row written before it existed, and deleting every token
-- to force re-registration would silence everyone until they next opened the app.

ALTER TABLE public.device_tokens
    ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production';

-- A typo here is a silent non-delivery, not an error: `apnsHost()` falls back to production for
-- any unrecognised value. Make the database refuse the typo instead.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'device_tokens_environment_check'
    ) THEN
        ALTER TABLE public.device_tokens
            ADD CONSTRAINT device_tokens_environment_check
            CHECK (environment IN ('sandbox', 'production'));
    END IF;
END $$;

COMMENT ON COLUMN public.device_tokens.environment IS
    'APNs environment this token is valid in, from the registering build''s aps-environment '
    'entitlement (Debug = development/sandbox, Release = production). Chosen by the client at '
    'registration; the sender of a notification cannot know it. See migration 048.';

-- No RLS change. The existing "Users manage own tokens" policy (016) and the WITH CHECK added by
-- 027 already scope every operation to `auth.uid() = user_id`, and this column is written by the
-- same upsert that writes the token.
