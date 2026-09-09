-- 056_respond_friend_request_guard.sql
--
-- SECDEF-03, last remaining function. `respond_to_friend_request` is SECURITY DEFINER — it bypasses
-- RLS on `friends` — and carries **no** `auth.uid()` guard of any kind. Both branches filter on
-- `addressee_id = auth.uid()`, which for an anonymous caller is `= NULL` → NULL → never true, so
-- zero rows match and PostgREST answers **204 No Content**: success, to a caller with no identity.
--
-- Nothing is exploitable today. But the protection is SQL three-valued logic rather than intent,
-- and this schema has now produced that shape three times — SECDEF-01 (`WHERE p.id != auth.uid()`,
-- one `IS DISTINCT FROM` away from an unauthenticated enumeration oracle over every display name),
-- `add_expense_with_splits` (`auth.uid() <> p_paid_by`, inert for NULL — closed by migration 055),
-- and this. An explicit guard costs one line and cannot be refactored into a hole.
--
-- Signature and defaults are UNCHANGED (2 args, 0 defaults — confirmed against production), so
-- CREATE OR REPLACE replaces rather than adding an overload. Migration 055's first attempt failed
-- because it dropped 8 defaults from a different function; there are none here to drop.
create or replace function public.respond_to_friend_request(
    p_requester_id uuid,
    p_accept boolean
) returns void
language plpgsql security definer set search_path = public as $$
DECLARE
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'You need to be signed in' USING ERRCODE = '42501';
    END IF;

    IF p_accept THEN
        UPDATE public.friends
           SET status = 'accepted'
         WHERE requester_id = p_requester_id
           AND addressee_id = v_caller
           AND status = 'pending';
    ELSE
        DELETE FROM public.friends
         WHERE requester_id = p_requester_id
           AND addressee_id = v_caller
           AND status = 'pending';
    END IF;
END;
$$;

-- Second layer. Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE on every new function in
-- `public`, and `REVOKE ... FROM PUBLIC` does not remove an explicit grant — revoke by name.
revoke execute on function public.respond_to_friend_request(uuid, boolean) from anon;
