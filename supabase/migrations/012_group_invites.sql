-- Group invite links (P2-C)
CREATE TABLE public.group_invites (
  token      text        PRIMARY KEY DEFAULT replace(gen_random_uuid()::text, '-', ''),
  group_id   uuid        NOT NULL REFERENCES public.groups(id)   ON DELETE CASCADE,
  created_by uuid        NOT NULL REFERENCES auth.users(id)      ON DELETE CASCADE,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days')
);

ALTER TABLE public.group_invites ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read invite tokens (required to validate a link before joining)
CREATE POLICY "authenticated users can read invites"
  ON public.group_invites FOR SELECT
  TO authenticated
  USING (true);

-- Group members can create invites
CREATE POLICY "group members can create invites"
  ON public.group_invites FOR INSERT
  WITH CHECK (
    auth.uid() = created_by
    AND is_group_member(group_id)
  );

-- Creator can delete their own invites
CREATE POLICY "invite creator can delete"
  ON public.group_invites FOR DELETE
  USING (auth.uid() = created_by);

-- SECURITY DEFINER RPC: validates token, then adds the current user to the group
CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id   uuid;
  v_expires_at timestamptz;
BEGIN
  SELECT group_id, expires_at
    INTO v_group_id, v_expires_at
    FROM group_invites
   WHERE token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid invite token';
  END IF;

  IF v_expires_at < now() THEN
    RAISE EXCEPTION 'Invite link has expired';
  END IF;

  -- Idempotent: skip if already a member
  INSERT INTO group_members (group_id, user_id)
  VALUES (v_group_id, auth.uid())
  ON CONFLICT DO NOTHING;

  RETURN v_group_id;
END;
$$;
