# xBill Release Verification

Use this runbook before App Store submission or after backend changes. It is intentionally manual-friendly: each section states what to check and what result is expected.

## 1. Backend Verification

Run from `/Users/vijaygoyal/MyiOSApp/xBill`.

### Supabase Project Reachability

```bash
curl -I --max-time 15 https://rhdhazevigbchmwzesok.supabase.co
dig +short rhdhazevigbchmwzesok.supabase.co
```

Expected:

- Host resolves.
- Supabase responds. A root `HTTP 404` is acceptable because the project root is not an app route.

### Local App Credentials

Check that `Secrets.xcconfig` exists and points to the production Supabase project. Do not print the anon key.

Expected:

- `SUPABASE_URL` resolves to `https://rhdhazevigbchmwzesok.supabase.co`.
- `SUPABASE_ANON_KEY` is present.

### Keep-Alive

```bash
# GitHub Actions should run every 3 days:
curl -s 'https://api.github.com/repos/imvijaygoyal1/xbill/actions/runs?per_page=5'
```

Expected:

- Recent `Supabase Keep-Alive` runs are `completed` / `success`.
- Manual Supabase keep-alive PATCH/read-back updates `public.keep_alive.updated_at`.

### Migrations

```bash
supabase migration list --linked
```

Expected:

- Local and remote migration numbers match.
- Current expected latest migration: `039`.

### Realtime Publication

```bash
supabase db query --linked <<'SQL'
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
order by tablename;
SQL
```

Expected rows:

- `comments`
- `group_members`
- `groups`

### Edge Functions

```bash
supabase functions list --project-ref rhdhazevigbchmwzesok
supabase secrets list --project-ref rhdhazevigbchmwzesok
```

Expected active functions:

- `delete-account`
- `invite-member`
- `notify-expense`
- `notify-settlement`
- `notify-comment`
- `notify-friend-request`

Expected secret names:

- `RESEND_API_KEY`
- `INVITE_FROM_EMAIL`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY`
- `APNS_TEAM_ID`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

### Public Web Pages

```bash
for u in \
  https://xbill.vijaygoyal.org \
  https://xbill.vijaygoyal.org/invite \
  https://xbill.vijaygoyal.org/privacy \
  https://xbill.vijaygoyal.org/terms
do
  curl -L -I --max-time 15 "$u"
done
```

Expected:

- Each URL ends at `HTTP 200`.
- Privacy and Terms pages render raw HTML, not escaped/Cocoa HTML output.

### Exchange Rate API

```bash
curl -s --max-time 15 'https://open.er-api.com/v6/latest/USD'
```

Expected:

- JSON response has `"result":"success"`.
- `rates` contains common currencies such as `INR`.

## 2. Reviewer Account Verification

Reviewer account:

- Email: `appreviewer@xbill.vijaygoyal.org`
- Password: stored outside git in Supabase Auth and App Store Connect review notes.

Verify seed data:

```bash
supabase db query --linked <<'SQL'
select
  (select count(*) from auth.users where email = 'appreviewer@xbill.vijaygoyal.org') as auth_users,
  (select count(*) from public.profiles where email = 'appreviewer@xbill.vijaygoyal.org') as profiles,
  (select count(*) from public.groups where name = 'Tokyo Trip') as tokyo_groups,
  (select count(*) from public.group_members where group_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') as tokyo_members,
  (select count(*) from public.expenses where group_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') as tokyo_expenses,
  (select count(*) from public.splits where expense_id in (select id from public.expenses where group_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')) as tokyo_splits,
  (select count(*) from public.comments where expense_id in (select id from public.expenses where group_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')) as tokyo_comments,
  (select count(*) from public.ious) as ious_total;
SQL
```

Expected:

- `auth_users = 1`
- `profiles = 1`
- `tokyo_groups = 1`
- `tokyo_members = 3`
- `tokyo_expenses = 5`
- `tokyo_splits = 15`
- `tokyo_comments = 2`
- `ious_total >= 1`

## 3. Simulator Smoke Test

Use a fresh install when possible.

### Launch

- Build Debug or Release.
- Install on simulator.
- Launch app.

Expected:

- App opens without crash.
- Auth screen appears for fresh install.
- Privacy and Terms links open correctly.

### Sign In

- Sign in with `appreviewer@xbill.vijaygoyal.org` and the rotated reviewer password.

Expected:

- Sign-in succeeds.
- Home loads without backend errors.
- `Tokyo Trip` appears.

### Core Tabs

Check:

- Home
- Groups
- Friends
- Activity
- Profile

Expected:

- Each tab loads.
- No blocking error alerts.
- Profile shows reviewer display name and legal/settings entries.

### Group Flow

Open `Tokyo Trip`.

Expected:

- 3 members visible.
- 5 expenses visible.
- Existing comments visible.
- Balances are non-zero and reasonable for seeded data.

### Expense Flow

Create a small test expense in a disposable group or clearly named test group.

Expected:

- Expense saves.
- Splits are created.
- Group balance updates.
- Activity updates.

### Comment Flow

Add a comment to an expense.

Expected:

- Comment appears immediately.
- Reopening the expense still shows the comment.

### Receipt Flow

Check both paths:

- Manual receipt entry.
- OCR scan path if simulator/device image flow is practical.

Expected:

- Manual entry reaches review/add-expense flow.
- OCR-only behavior remains true: receipt image is not uploaded or attached.

## 4. Automated UI Regression Suite

The primary end-to-end UI regression target is `xBillUITests/RegressionUITests.swift`. It uses the local ignored `xBillUITests/UITestCredentials.plist` or the `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` environment variables for email sign-in.

Run from `/Users/vijaygoyal/MyiOSApp/xBill`:

```bash
scripts/run-coverage.sh full
```

For a faster UI-only pass:

```bash
scripts/run-coverage.sh regression-ui
```

Current `RegressionUITests` coverage:

- `testAuthValidationRegression` — verifies signed-out email-auth validation, forgot-password sheet, create-account mode, and password mismatch messaging.
- `testMainTabsLoadRegression` — verifies Home, Groups, Friends, Recent Activity, and Profile through real tab navigation.
- `testCreateGroupValidationRegression` — verifies New Group form disabled/enabled state and Back navigation.
- `testExpenseFormValidationRegression` — verifies Add Expense required-field behavior and Back navigation.
- `testSplitModeControlsRegression` — verifies Equal, Exact, By %, and Shares split-mode controls on Add Expense.
- `testCoreGroupExpenseArchiveRegression` — creates a group, adds an expense, verifies the expense row and group balance tabs, then archives the group.
- `testExpenseDetailCommentsRegression` — creates a group and expense, posts a comment in expense detail, and verifies the comment persists after reopening the expense.
- `testArchiveUnarchiveRegression` — creates and archives a group, finds it in the archived section, unarchives it, verifies it returns to the active list, then archives cleanup data.
- `testReceiptManualReviewRegression` — verifies receipt scan entry, manual review, merchant/total fields, add-item controls, and cancel path.
- `testGroupSettingsInviteAndCurrencyLockRegression` — verifies Manage Group, invite email/link routes, and post-expense currency lock messaging.
- `testSettleUpAndActivitySurfacesRegression` — verifies Settle Up empty-state behavior and Activity filter surfaces.
- `testFriendsAddSearchRegression` — verifies Friends tab, Add Friend sheet, no-results search state, and Import Contacts action.
- `testProfileEditAndPaymentHandleValidationRegression` — verifies Profile tab, Edit Profile sheet, Venmo validation, and Sign Out row reachability.
- `testProfileQRCodeAndAccountCancelRegression` — verifies QR-code route, delete-account confirmation cancel, and sign-out confirmation cancel.

Expected skips:

- None when credentials are present. Missing `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` or local ignored `xBillUITests/UITestCredentials.plist` should fail auth bootstrap instead of producing misleading skipped regression coverage.

Most recent verified result:

- Date: 2026-07-15
- Result bundle: `TestResults/Coverage/2026.07.15_22-03-05-full.xcresult`
- Coverage reports: `TestResults/Coverage/2026.07.15_22-03-05-full-report.txt` and `TestResults/Coverage/2026.07.15_22-03-05-full-report.json`
- Structured result: `168` total tests, `168` passed, `0` failed, `0` skipped.
- Top-level coverage: `xBill.app 60.33% (17335/28734)`, `xBillTests.xctest 99.25% (1727/1740)`, `xBillUITests.xctest 77.83% (1552/1994)`, `xBillWidgetCore.framework 26.99% (61/226)`, `xBillWidgetTests.xctest 100.00% (104/104)`, `xBillWidget.appex 0.00% (0/3)`.

Notes:

- The suite creates uniquely named disposable groups and archives cleanup groups so the active list is not polluted.
- The suite uses clean signed-out relaunches before credential entry when a test needs authentication and the app is not already signed in.
- Stable UI identifiers exist for auth fields/actions, Add Expense fields/actions, split controls, receipt scan/review, group settings/invites, expense-detail comments, profile edit/payment/QR/delete/sign-out rows, Add Friend search/import contacts, and `XBillSearchBar` identifier injection.
- The suite does not cover push notification delivery, offline behavior, multi-user realtime sync, payment-provider handoff, App Store review metadata, or visual screenshot diffing. Keep those as separate manual or targeted checks.

## 5. UI Test Data Cleanup

UI regression tests create disposable groups with approved prefixes such as `Regression-`, `ExpenseForm-`, `ArchiveCycle-`, `ExpenseDetail-`, `ReceiptManual-`, `SplitModes-`, `GroupSettings-`, `SettleSurface-`, `UITest-`, and `ArchiveTest-`.

Preview cleanup for the UI test account:

```bash
scripts/purge-ui-test-groups.sh
```

Execute cleanup:

```bash
scripts/purge-ui-test-groups.sh --execute
```

Expected:

- Dry-run lists only groups owned by the UI test account and matching approved test prefixes.
- `--execute` permanently deletes those groups.
- Existing foreign keys cascade cleanup to `group_members`, `group_invites`, `expenses`, `splits`, and `comments`.
- Real user groups are not targeted because both owner and prefix checks are required.

## 6. Realtime Verification

The backend publication must include `groups`, `group_members`, and `comments`.

Recommended manual test:

1. Launch app and sign in.
2. Open Home or Groups.
3. From another client/session, make a group update or membership change.
4. Wait without pull-to-refresh.

Expected:

- App refreshes affected group/member state automatically.

For comments:

1. Open an expense detail.
2. Add a comment from another session/device.

Expected:

- Comment appears via realtime.

## 7. Account Deletion Verification

Do not use the reviewer account for destructive deletion tests.

Use a disposable account.

Expected:

- Delete Account action is available in Profile.
- App explains that profile/avatar/payment handles/device tokens are removed.
- Shared expense records remain for other group members.
- Deletion succeeds.
- User is signed out.
- Deleted user cannot sign back in with the same credentials unless recreated.

Backend expectations:

- Auth user removed.
- `profiles` row removed.
- Device tokens removed.
- Avatar object removed if present.
- Historical shared expense/member snapshots remain readable where product policy requires it.

## 8. App Store Readiness

### Privacy

- App Store Connect privacy labels match `APPSTORE_PRIVACY_RECONCILIATION.md`.
- Public privacy policy URL is `https://xbill.vijaygoyal.org/privacy`.
- Privacy policy covers Supabase, Resend, APNs/device tokens, selected contacts, avatar uploads, OCR-only receipts, exchange-rate API, local/widget cache, account deletion, and retained shared history.
- `xBill/PrivacyInfo.xcprivacy` and `xBillWidget/PrivacyInfo.xcprivacy` are included in built products.

### Review Notes

Include:

- Reviewer account email and rotated password.
- Backend is live.
- Seeded `Tokyo Trip` data is available.
- Receipt scanning is OCR-only and does not upload receipt images.
- Account deletion removes account/profile/avatar/device tokens while retaining shared expense history for other group members.
- Contact import uses Apple's contact picker and only selected contact emails are checked.

### Assets and Metadata

- Screenshots uploaded for required devices.
- Description, keywords, category, support URL, privacy policy URL, and copyright complete.
- No placeholder URLs such as `id0000000000`, `example.com`, `localhost`, or `127.0.0.1`.

Run:

```bash
rg -n "id0000000000|placeholder|example\\.com|localhost|127\\.0\\.0\\.1|TODO|FIXME" .
```

Review any findings before submission.

## 9. Known Non-Blocking Notes

- `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET is unset` can appear from local Supabase CLI config. It is not a hosted-backend failure if Apple provider settings are configured in the Supabase dashboard.
- Older `GroupFlowUITests` notes mention iOS 26 simulator/XCTest tab-bar issues. The current preferred path is `scripts/run-coverage.sh full` or `scripts/run-coverage.sh regression-ui`; the latest full baseline passed on 2026-07-15 with `168` executed tests and `0` skips.
- Supabase free-tier pause prevention is not guaranteed by GitHub keep-alive traffic. Keep the project active before review.
