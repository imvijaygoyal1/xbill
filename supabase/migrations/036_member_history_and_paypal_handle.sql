-- Member history + PayPal handle cleanup.
--
-- Active group membership controls access. Inactive rows remain as historical
-- display records so old expenses/splits keep stable names after removal or
-- account deletion.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS paypal_handle text;

UPDATE public.profiles
SET paypal_handle = paypal_email
WHERE paypal_handle IS NULL
  AND paypal_email IS NOT NULL
  AND paypal_email NOT LIKE '%@%';

ALTER TABLE public.group_members
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS removed_at timestamptz,
  ADD COLUMN IF NOT EXISTS display_name_snapshot text,
  ADD COLUMN IF NOT EXISTS avatar_url_snapshot text;

UPDATE public.group_members gm
SET display_name_snapshot = COALESCE(gm.display_name_snapshot, p.display_name),
    avatar_url_snapshot = COALESCE(gm.avatar_url_snapshot, p.avatar_url)
FROM public.profiles p
WHERE p.id = gm.user_id;

CREATE OR REPLACE FUNCTION public.set_group_member_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  SELECT COALESCE(NEW.display_name_snapshot, p.display_name),
         COALESCE(NEW.avatar_url_snapshot, p.avatar_url)
  INTO NEW.display_name_snapshot, NEW.avatar_url_snapshot
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS group_members_snapshot_before_write ON public.group_members;
CREATE TRIGGER group_members_snapshot_before_write
BEFORE INSERT OR UPDATE OF user_id, display_name_snapshot, avatar_url_snapshot
ON public.group_members
FOR EACH ROW
EXECUTE FUNCTION public.set_group_member_snapshot();

CREATE OR REPLACE FUNCTION public.is_group_member(group_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = $1
          AND gm.user_id = auth.uid()
          AND gm.is_active = true
    );
$$;

DROP POLICY IF EXISTS "Group members can read each other's profiles" ON public.profiles;
CREATE POLICY "Group members can read each other's profiles"
    ON public.profiles
    FOR SELECT
    USING (
        auth.uid() = id
        OR EXISTS (
            SELECT 1
            FROM public.group_members gm1
            JOIN public.group_members gm2
              ON gm1.group_id = gm2.group_id
            WHERE gm1.user_id = auth.uid()
              AND gm1.is_active = true
              AND gm2.user_id = profiles.id
        )
    );

DROP POLICY IF EXISTS "creator or member can read invites" ON public.group_invites;
CREATE POLICY "creator or member can read invites"
    ON public.group_invites FOR SELECT
    USING (
        auth.uid() = created_by
        OR group_id IN (
            SELECT group_id FROM public.group_members
            WHERE user_id = auth.uid()
              AND is_active = true
        )
    );

DROP POLICY IF EXISTS "creator can remove members" ON public.group_members;
DROP POLICY IF EXISTS "group_members: own row delete" ON public.group_members;

CREATE OR REPLACE FUNCTION public.add_or_reactivate_group_member(
  p_group_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;

  IF NOT (
    public.is_group_member(p_group_id)
    OR EXISTS (
      SELECT 1 FROM public.groups
      WHERE id = p_group_id
        AND created_by = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'caller is not allowed to add members to this group';
  END IF;

  INSERT INTO public.group_members (group_id, user_id, is_active, removed_at)
  VALUES (p_group_id, p_user_id, true, NULL)
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET
    is_active = true,
    removed_at = NULL,
    display_name_snapshot = EXCLUDED.display_name_snapshot,
    avatar_url_snapshot = EXCLUDED.avatar_url_snapshot;
END;
$$;

REVOKE ALL ON FUNCTION public.add_or_reactivate_group_member(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_or_reactivate_group_member(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_group_member(
  p_group_id uuid,
  p_user_id uuid
)
RETURNS TABLE(user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.groups
    WHERE id = p_group_id
      AND created_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the group creator can remove other members.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.groups
    WHERE id = p_group_id
      AND created_by = p_user_id
  ) THEN
    RAISE EXCEPTION 'The group creator cannot be removed.';
  END IF;

  RETURN QUERY
  UPDATE public.group_members gm
  SET is_active = false,
      removed_at = now()
  WHERE gm.group_id = p_group_id
    AND gm.user_id = p_user_id
    AND gm.is_active = true
  RETURNING gm.user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.deactivate_group_member(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deactivate_group_member(uuid, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.join_group_via_invite(text);
CREATE FUNCTION public.join_group_via_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.group_invites%ROWTYPE;
BEGIN
    SELECT * INTO v_invite
    FROM public.group_invites
    WHERE token = p_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    INSERT INTO public.group_members (group_id, user_id, is_active, removed_at)
    VALUES (v_invite.group_id, auth.uid(), true, NULL)
    ON CONFLICT (group_id, user_id)
    DO UPDATE SET
      is_active = true,
      removed_at = NULL,
      display_name_snapshot = EXCLUDED.display_name_snapshot,
      avatar_url_snapshot = EXCLUDED.avatar_url_snapshot;

    DELETE FROM public.group_invites WHERE token = p_token;

    RETURN v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;
