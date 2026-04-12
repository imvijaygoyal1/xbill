-- Expense comments (P2-B)
CREATE TABLE public.comments (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id uuid        NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id)      ON DELETE CASCADE,
  text       text        NOT NULL
                         CHECK (char_length(trim(text)) > 0 AND char_length(text) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group members can view comments"
  ON public.comments FOR SELECT
  USING (is_expense_group_member(expense_id));

CREATE POLICY "group members can insert comments"
  ON public.comments FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND is_expense_group_member(expense_id)
  );

CREATE POLICY "comment author can delete their own"
  ON public.comments FOR DELETE
  USING (auth.uid() = user_id);

ALTER PUBLICATION supabase_realtime ADD TABLE public.comments;
