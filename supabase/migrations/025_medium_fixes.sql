-- Migration 025: Medium severity fixes
--
-- M-32: send_friend_request bidirectional duplicate check
--   The old function only checked UNIQUE(requester_id, addressee_id), so if A→B is pending
--   and B sends to A a second row could be inserted (different direction, different UNIQUE key).
--   The updated function checks for an existing row in EITHER direction before inserting.
--
-- M-33: lookup_profiles_by_email email column removed from response
--   The old function returned the email column, letting any authenticated user confirm whether
--   a given email address belongs to an xBill account.  The new version still searches by email
--   but omits the address from the SELECT list and RETURNS TABLE so callers never receive it.

-- ─────────────────────────────────────────────────────────────────────────────
-- M-32: send_friend_request — bidirectional duplicate guard
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    p_requester_id uuid := auth.uid();
BEGIN
    -- Check for an existing relationship in EITHER direction (pending or accepted).
    -- This prevents the UNIQUE(requester_id, addressee_id) gap where B→A would create a
    -- second row even though A→B already exists.
    IF EXISTS (
        SELECT 1
        FROM   friends
        WHERE  status IN ('pending', 'accepted')
          AND  (
                  (requester_id = p_requester_id AND addressee_id = p_addressee_id)
               OR (requester_id = p_addressee_id AND addressee_id = p_requester_id)
               )
    ) THEN
        RETURN; -- already a pending or accepted relationship — do nothing
    END IF;

    INSERT INTO friends (requester_id, addressee_id, status)
    VALUES (p_requester_id, p_addressee_id, 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_friend_request(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.send_friend_request(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- M-33: lookup_profiles_by_email — remove email from response columns
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.lookup_profiles_by_email(p_emails text[])
RETURNS TABLE(
    id           uuid,
    display_name text,
    avatar_url   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.display_name,
    p.avatar_url
  FROM profiles p
  WHERE p.email = ANY(p_emails)
    AND p.id != auth.uid();
$$;

-- Only authenticated users may call this function.
REVOKE EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) TO authenticated;
