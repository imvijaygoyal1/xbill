-- Migration 020: friends table + friend-request RPCs
-- requester_id = person who sent the request
-- addressee_id = person who received the request
-- status: 'pending' | 'accepted' | 'blocked'
-- A friendship is represented by a SINGLE row regardless of direction.
-- The requester is always the one who initiated; accept flips status to 'accepted'.

CREATE TABLE public.friends (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    addressee_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status       text        NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT friends_no_self        CHECK (requester_id <> addressee_id),
    CONSTRAINT friends_unique_pair    UNIQUE (requester_id, addressee_id)
);

ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;

-- Both parties can see the row
CREATE POLICY "parties can view"
    ON public.friends FOR SELECT
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Only the requester can insert (requester_id must equal caller)
CREATE POLICY "requester can insert"
    ON public.friends FOR INSERT
    WITH CHECK (auth.uid() = requester_id);

-- Only the addressee can update (to accept/block)
CREATE POLICY "addressee can update"
    ON public.friends FOR UPDATE
    USING (auth.uid() = addressee_id);

-- Either party can delete (unfriend or cancel request)
CREATE POLICY "either party can delete"
    ON public.friends FOR DELETE
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: send_friend_request
-- Inserts a pending row. Idempotent — does nothing if a row already exists.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO friends (requester_id, addressee_id, status)
    VALUES (auth.uid(), p_addressee_id, 'pending')
    ON CONFLICT (requester_id, addressee_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_friend_request(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.send_friend_request(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: respond_to_friend_request
-- p_accept = true  → sets status to 'accepted'
-- p_accept = false → deletes the row (decline)
-- Caller must be the addressee; silently no-ops if row not found.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.respond_to_friend_request(
    p_requester_id uuid,
    p_accept       boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_accept THEN
        UPDATE friends
        SET status = 'accepted'
        WHERE requester_id = p_requester_id
          AND addressee_id = auth.uid()
          AND status = 'pending';
    ELSE
        DELETE FROM friends
        WHERE requester_id = p_requester_id
          AND addressee_id = auth.uid()
          AND status = 'pending';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.respond_to_friend_request(uuid, boolean) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.respond_to_friend_request(uuid, boolean) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: search_profiles
-- Partial match on email OR display_name (case-insensitive).
-- Excludes current user. Used by AddFriendView search.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.search_profiles(p_query text)
RETURNS TABLE(
    id           uuid,
    email        text,
    display_name text,
    avatar_url   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.email, p.display_name, p.avatar_url
  FROM   profiles p
  WHERE  p.id != auth.uid()
    AND  (
           p.email        ILIKE '%' || p_query || '%'
        OR p.display_name ILIKE '%' || p_query || '%'
         )
  LIMIT 20;
$$;

REVOKE EXECUTE ON FUNCTION public.search_profiles(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.search_profiles(text) TO authenticated;
