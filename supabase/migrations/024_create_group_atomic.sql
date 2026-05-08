-- H-07: atomic group creation
-- Replaces the two round-trips (INSERT groups → INSERT group_members) with a
-- single SECURITY DEFINER transaction so there is no window where the group
-- exists but the creator is not yet a member.

CREATE OR REPLACE FUNCTION public.create_group_with_member(
  p_name     text,
  p_emoji    text,
  p_currency text
)
RETURNS SETOF public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_group   public.groups%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  INSERT INTO public.groups (name, emoji, currency, created_by)
  VALUES (p_name, p_emoji, p_currency, v_user_id)
  RETURNING * INTO v_group;

  INSERT INTO public.group_members (group_id, user_id)
  VALUES (v_group.id, v_user_id);

  RETURN NEXT v_group;
END;
$$;

REVOKE ALL ON FUNCTION public.create_group_with_member(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_group_with_member(text, text, text) TO authenticated;
