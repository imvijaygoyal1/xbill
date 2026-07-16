-- Migration 038: block-user RPC and friend-request block enforcement
-- Adds a first-party moderation path required for App Store review readiness.

CREATE OR REPLACE FUNCTION public.block_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_id uuid := auth.uid();
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF caller_id = p_user_id THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;

    DELETE FROM public.friends
    WHERE (requester_id = caller_id AND addressee_id = p_user_id)
       OR (requester_id = p_user_id AND addressee_id = caller_id);

    -- Store the blocked row with the blocked user as requester and caller as
    -- addressee so existing "addressee can update" policy remains compatible.
    INSERT INTO public.friends (requester_id, addressee_id, status)
    VALUES (p_user_id, caller_id, 'blocked')
    ON CONFLICT (requester_id, addressee_id) DO UPDATE
    SET status = 'blocked';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.block_user(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.block_user(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    p_requester_id uuid := auth.uid();
BEGIN
    IF p_requester_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_requester_id = p_addressee_id THEN
        RAISE EXCEPTION 'Cannot friend yourself';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.friends
        WHERE status = 'blocked'
          AND (
              (requester_id = p_requester_id AND addressee_id = p_addressee_id)
           OR (requester_id = p_addressee_id AND addressee_id = p_requester_id)
          )
    ) THEN
        RETURN;
    END IF;

    INSERT INTO public.friends (requester_id, addressee_id, status)
    VALUES (p_requester_id, p_addressee_id, 'pending')
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_friend_request(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.send_friend_request(uuid) TO authenticated;
