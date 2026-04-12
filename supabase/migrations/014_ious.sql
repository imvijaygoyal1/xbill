-- 1:1 IOU (Friend Mode) (P3-B)
-- lender_id  = person who is owed money (creditor)
-- borrower_id = person who owes money (debtor)
-- created_by  = current user (always one of lender/borrower, enforced by CHECK)

CREATE TABLE public.ious (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    lender_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    borrower_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount      numeric     NOT NULL CHECK (amount > 0),
    currency    text        NOT NULL DEFAULT 'USD',
    description text,
    is_settled  boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ious_creator_is_party
        CHECK (created_by = lender_id OR created_by = borrower_id),
    CONSTRAINT ious_no_self_iou
        CHECK (lender_id <> borrower_id)
);

ALTER TABLE public.ious ENABLE ROW LEVEL SECURITY;

CREATE POLICY "parties can view their ious"
    ON public.ious FOR SELECT
    USING (auth.uid() = lender_id OR auth.uid() = borrower_id);

CREATE POLICY "creator can insert"
    ON public.ious FOR INSERT
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "parties can settle"
    ON public.ious FOR UPDATE
    USING (auth.uid() = lender_id OR auth.uid() = borrower_id);

CREATE POLICY "creator can delete"
    ON public.ious FOR DELETE
    USING (auth.uid() = created_by);
