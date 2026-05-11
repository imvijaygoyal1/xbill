# App Store Review — Test Account Setup

## Goal
Create and fully seed the test account so Apple reviewers can explore every
feature of xBill without needing to invite friends or add their own data.

Credentials:
  Email:    appreviewer@xbill.vijaygoyal.org
  Password: xBillReview2026!

---

## Step 1 — Create the auth user in Supabase

Run in Supabase Dashboard → SQL Editor:

```sql
-- Create the reviewer auth user
-- NOTE: if the user already exists, skip to Step 2
SELECT supabase.auth.admin.create_user(
  email := 'appreviewer@xbill.vijaygoyal.org',
  password := 'xBillReview2026!',
  email_confirm := true   -- skip email confirmation
);
```

Or via Supabase Dashboard → Authentication → Users → "Invite user", then
manually confirm the email in the dashboard.

Save the returned user UUID — you will need it in every INSERT below.
Replace every occurrence of <REVIEWER_UUID> with the actual UUID.

---

## Step 2 — Create reviewer profile

```sql
INSERT INTO public.profiles (id, display_name, avatar_url, venmo_handle, paypal_email)
VALUES (
  '<REVIEWER_UUID>',
  'App Reviewer',
  null,
  'appreviewer',
  'appreviewer@xbill.vijaygoyal.org'
)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  venmo_handle = EXCLUDED.venmo_handle;
```

---

## Step 3 — Create two seed users (as reviewer's friends)

These users exist only to populate splits and balances — Apple reviewers do not
need to log in as them.

```sql
-- Seed user 1
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role)
VALUES (
  'aaaaaaaa-0001-0001-0001-000000000001',
  'alice.seed@xbill.vijaygoyal.org',
  crypt('SeedPass123!', gen_salt('bf')),
  now(),
  'authenticated'
) ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, display_name, venmo_handle)
VALUES ('aaaaaaaa-0001-0001-0001-000000000001', 'Alice Chen', 'alicechen')
ON CONFLICT DO NOTHING;

-- Seed user 2
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role)
VALUES (
  'aaaaaaaa-0002-0002-0002-000000000002',
  'bob.seed@xbill.vijaygoyal.org',
  crypt('SeedPass123!', gen_salt('bf')),
  now(),
  'authenticated'
) ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, display_name, venmo_handle)
VALUES ('aaaaaaaa-0002-0002-0002-000000000002', 'Bob Patel', 'bobpatel')
ON CONFLICT DO NOTHING;
```

---

## Step 4 — Create a group with all three members

```sql
-- Group
INSERT INTO public.groups (id, name, emoji, currency, created_by)
VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'Tokyo Trip',
  '🗼',
  'USD',
  '<REVIEWER_UUID>'
) ON CONFLICT DO NOTHING;

-- Members
INSERT INTO public.group_members (group_id, user_id)
VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '<REVIEWER_UUID>'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-0001-0001-0001-000000000001'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-0002-0002-0002-000000000002')
ON CONFLICT DO NOTHING;
```

---

## Step 5 — Seed expenses with splits

These expenses give the reviewer a non-zero balance and demonstrate all
split types (equal, custom, percentage).

```sql
-- Expense 1: Reviewer paid, split equally
INSERT INTO public.expenses (id, group_id, paid_by, amount, description, category, created_at)
VALUES (
  'eeeeeeee-0001-0001-0001-000000000001',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '<REVIEWER_UUID>',
  180.00,
  'Flights to Tokyo',
  'travel',
  now() - interval '5 days'
);

INSERT INTO public.splits (expense_id, user_id, amount, is_settled)
VALUES
  ('eeeeeeee-0001-0001-0001-000000000001', '<REVIEWER_UUID>', 60.00, true),
  ('eeeeeeee-0001-0001-0001-000000000001', 'aaaaaaaa-0001-0001-0001-000000000001', 60.00, false),
  ('eeeeeeee-0001-0001-0001-000000000001', 'aaaaaaaa-0002-0002-0002-000000000002', 60.00, false);

-- Expense 2: Alice paid, split equally — reviewer owes
INSERT INTO public.expenses (id, group_id, paid_by, amount, description, category, created_at)
VALUES (
  'eeeeeeee-0002-0002-0002-000000000002',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'aaaaaaaa-0001-0001-0001-000000000001',
  90.00,
  'Hotel — Night 1',
  'accommodation',
  now() - interval '4 days'
);

INSERT INTO public.splits (expense_id, user_id, amount, is_settled)
VALUES
  ('eeeeeeee-0002-0002-0002-000000000002', '<REVIEWER_UUID>', 30.00, false),
  ('eeeeeeee-0002-0002-0002-000000000002', 'aaaaaaaa-0001-0001-0001-000000000001', 30.00, true),
  ('eeeeeeee-0002-0002-0002-000000000002', 'aaaaaaaa-0002-0002-0002-000000000002', 30.00, false);

-- Expense 3: Reviewer paid, custom split
INSERT INTO public.expenses (id, group_id, paid_by, amount, description, category, created_at)
VALUES (
  'eeeeeeee-0003-0003-0003-000000000003',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '<REVIEWER_UUID>',
  120.00,
  'Sushi dinner',
  'food',
  now() - interval '3 days'
);

INSERT INTO public.splits (expense_id, user_id, amount, is_settled)
VALUES
  ('eeeeeeee-0003-0003-0003-000000000003', '<REVIEWER_UUID>', 50.00, true),
  ('eeeeeeee-0003-0003-0003-000000000003', 'aaaaaaaa-0001-0001-0001-000000000001', 40.00, false),
  ('eeeeeeee-0003-0003-0003-000000000003', 'aaaaaaaa-0002-0002-0002-000000000002', 30.00, false);

-- Expense 4: Bob paid, split equally — reviewer owes
INSERT INTO public.expenses (id, group_id, paid_by, amount, description, category, created_at)
VALUES (
  'eeeeeeee-0004-0004-0004-000000000004',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'aaaaaaaa-0002-0002-0002-000000000002',
  60.00,
  'Day trip to Nikko',
  'transport',
  now() - interval '2 days'
);

INSERT INTO public.splits (expense_id, user_id, amount, is_settled)
VALUES
  ('eeeeeeee-0004-0004-0004-000000000004', '<REVIEWER_UUID>', 20.00, false),
  ('eeeeeeee-0004-0004-0004-000000000004', 'aaaaaaaa-0001-0001-0001-000000000001', 20.00, false),
  ('eeeeeeee-0004-0004-0004-000000000004', 'aaaaaaaa-0002-0002-0002-000000000002', 20.00, true);

-- Expense 5: Reviewer paid, recent — shows in activity feed
INSERT INTO public.expenses (id, group_id, paid_by, amount, description, category, created_at)
VALUES (
  'eeeeeeee-0005-0005-0005-000000000005',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '<REVIEWER_UUID>',
  45.00,
  'Convenience store run',
  'shopping',
  now() - interval '1 day'
);

INSERT INTO public.splits (expense_id, user_id, amount, is_settled)
VALUES
  ('eeeeeeee-0005-0005-0005-000000000005', '<REVIEWER_UUID>', 15.00, true),
  ('eeeeeeee-0005-0005-0005-000000000005', 'aaaaaaaa-0001-0001-0001-000000000001', 15.00, false),
  ('eeeeeeee-0005-0005-0005-000000000005', 'aaaaaaaa-0002-0002-0002-000000000002', 15.00, false);
```

---

## Step 6 — Seed a Friend IOU

Demonstrates the Friends tab:

```sql
INSERT INTO public.iou (id, from_user, to_user, amount, description, is_settled)
VALUES (
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  'aaaaaaaa-0001-0001-0001-000000000001',  -- Alice owes reviewer
  '<REVIEWER_UUID>',
  25.00,
  'Concert tickets',
  false
) ON CONFLICT DO NOTHING;
```

---

## Step 7 — Verify balances look correct

Run this after seeding to confirm what the reviewer will see on the Home screen:

```sql
-- What reviewer is owed (should be positive)
SELECT
  e.paid_by,
  SUM(s.amount) as total_owed_to_reviewer
FROM splits s
JOIN expenses e ON s.expense_id = e.id
WHERE s.user_id != '<REVIEWER_UUID>'
  AND e.paid_by = '<REVIEWER_UUID>'
  AND s.is_settled = false
GROUP BY e.paid_by;

-- What reviewer owes others (should be positive = reviewer owes this)
SELECT
  e.paid_by,
  SUM(s.amount) as reviewer_owes
FROM splits s
JOIN expenses e ON s.expense_id = e.id
WHERE s.user_id = '<REVIEWER_UUID>'
  AND e.paid_by != '<REVIEWER_UUID>'
  AND s.is_settled = false
GROUP BY e.paid_by;
```

Expected result for reviewer Home screen:
  Owed to you:  ~$155.00  (Alice + Bob owe across 3 expenses reviewer paid)
  You owe:      ~$50.00   (reviewer owes Alice $30 + Bob $20)
  Net:          ~+$105.00

---

## Step 8 — Write App Store review notes

Add this to App Store Connect → App Review Information → Notes:

```
TEST ACCOUNT
Email:    appreviewer@xbill.vijaygoyal.org
Password: xBillReview2026!

The account has been pre-seeded with:
  • 1 group: "Tokyo Trip 🗼" with 3 members
  • 5 expenses across Food, Travel, Accommodation, Transport, Shopping categories
  • Mixed split types (equal and custom amounts)
  • Positive net balance (owed $155, owes $50) so the Home screen shows real data
  • 1 Friend IOU in the Friends tab

Key features to review:
  1. Home — balance hero card, group list
  2. Groups → Tokyo Trip — expense feed, per-member balances
  3. Groups → Tokyo Trip → Settle Up — minimized transaction suggestions + Venmo links
  4. Add Expense (+ button) — amount, category, split type, receipt scan
  5. Receipt Scan — camera viewfinder (use any receipt photo)
  6. Friends tab — IOU from Alice Chen
  7. Activity tab — expense history grouped by date
  8. Profile → Delete Account — end-to-end account deletion (creates a new account to test)

Privacy Policy: https://xbill.vijaygoyal.org/privacy
```

---

## Acceptance criteria
- [ ] Reviewer can sign in with appreviewer@xbill.vijaygoyal.org / xBillReview2026!
- [ ] Home screen shows non-zero "You are owed" balance
- [ ] Tokyo Trip group shows 5 expenses
- [ ] Settle Up shows 2–3 suggested payments
- [ ] Friends tab shows 1 IOU from Alice Chen
- [ ] Activity feed shows expenses grouped by date
- [ ] Delete account flow completes without error (test separately before submission)
- [ ] Review notes written in App Store Connect with credentials + feature walkthrough
