# Venmo / PayPal Settle-Up Handoff Defect

## Status: RESOLVED — 2026-07-27

Root cause identified, fixed, and verified on a physical device.

**The defect was not in xBill.** The "Something went wrong" message was produced by the
**PayPal app itself**, because xBill handed it a PayPal.Me handle that does not exist.

## Root cause

`supabase/seed_app_store_review_account.sql` seeded fabricated payment handles for the
demo profiles:

```sql
(reviewer_id, 'App Reviewer', null, 'appreviewer', 'appreviewer@…', 'appreviewer', …)
```

`PaymentLinkService` renders those handles as live outbound deep links:

- `https://paypal.me/appreviewer/95USD`
- `venmo://paycharge?txn=pay&recipients=appreviewer&amount=95&…`

A fabricated handle is **not** an inert placeholder. The PayPal app resolved the
universal link, found no such profile, and displayed its own error screen.

Venmo used the same fabricated handle, but its app degrades quietly rather than
hard-failing — which is why Venmo appeared to be "fixed" by earlier changes and PayPal
did not. Both were broken; only one said so.

## Evidence

On-device instrumentation (`PaymentDiagnostics`, DEBUG-only) across three
background/foreground cycles during a live reproduction:

- `alert.presented` events: **0** — xBill never raised an alert
- every `GroupViewModel.load` / `HomeViewModel.loadAll`: **success**
- `suggestions=2`, `hasLoadedBalances=true`, `balanceLoadFailed=false`, no spinner
- `openPaymentURL.result accepted=true`, `scheme=https host=paypal.me`

User confirmed the message appeared **inside the PayPal app**, not as an xBill dialog.

Independent verification of the URL:

| URL | Result |
|-----|--------|
| `paypal.me/appreviewer/95USD` | HTTP 200, serves PayPal.Me **error** bundle (`slugDoesNotExist`, header `"Something went wrong"`) |
| `paypal.me/zzqq-not-a-real-slug-9931/95USD` | HTTP 404 |

## Why the three previous fixes could not have worked

They all edited code that is already silenced on the payment-return path:

- `GroupDetailView.task` → `vm.load(showError: false)`
- `GroupDetailView.onChange(of: scenePhase)` → `vm.refresh(showError: false)`
- `createDueRecurringInstances` → logs, never alerts

`GroupViewModel` cannot raise that alert on return. The investigation assumed an xBill
alert without first confirming one was ever presented.

## Fix

1. **`supabase/seed_app_store_review_account.sql`** — all seeded payment handles are now
   `NULL`, with a comment explaining why a fabricated handle is dangerous. With `NULL`,
   `PaymentLinkService.paymentLink` returns `nil` and `GroupDetailView` renders no
   payment button, so no broken link is reachable.
2. **Live database** — the same change applied to the three seeded demo profiles.
   `profiles_with_handles` is now `0`. Only seeded demo rows were affected; no real user
   data was touched. Original values recorded for reversal: App Reviewer
   `venmo=appreviewer paypal=appreviewer`, Alice `venmo=alicechen`, Bob `venmo=bobpatel`.
3. **`project.yml`** — added the missing `DEVELOPMENT_TEAM`. It previously existed only
   in `project.pbxproj`, so every `xcodegen generate` wiped device signing. This was the
   recurring "signing/project churn" noted in the original handoff.

This also removes an App Store review risk: a reviewer following the settle-up flow on
the demo account would have landed on PayPal's error screen.

## Regression coverage

- **`xBillTests/PaymentHandoffTests.swift`** (new) — 40 cases, all passing. Pins the
  contract that makes the fix work: no handle / blank handle / unsafe handle ⇒ `nil`
  link ⇒ no button. Also covers PayPal.Me URL format, `@`-prefix stripping, decimal
  amount rendering (no scientific notation), and the Venmo `venmo://paycharge` scheme.
- **`xBillUITests/RegressionUITests.swift`** — the payment-return test now explicitly
  asserts that no `"Something went wrong"` and no `"Some balances may be stale"` alert
  appears after reactivation.

## Verification

- `xcodebuild test -only-testing:xBillTests` → `** TEST SUCCEEDED **`
- `xBillTests/PaymentHandoffTests` → 40 cases, 0 failures
- Release build → `** BUILD SUCCEEDED **` (DEBUG-only diagnostics compile out)
- **Physical device** (iPhone 16 Pro, `00008140-000135EE3432801C`): Tokyo Trip settle-up
  shows "Mark as Settled" with **no Venmo/PayPal buttons**; backgrounding and returning
  produces no alert and no stuck spinner. Post-fix device log: 0 alerts, 0 payment
  links, 0 `balanceLoadFailed`, `suggestions=2` throughout.
- Settlements remain unmarked — no settlement was recorded at any point.

## Note for future payment work

If a payment handle is ever re-introduced for a demo/seed account, it must correspond to
a **real** Venmo / PayPal.Me profile, or the flow will fail inside the third-party app
and read as an xBill defect.

## Diagnostics retained

`xBill/Core/PaymentDiagnostics.swift` is DEBUG-only and compiles out of Release. Retrieve
the on-device log with:

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/payment-diagnostics.log --destination ./payment-diagnostics.log
```

The alert-presentation chokepoint in `View.errorAlert(...)` (`Extensions.swift`) records
every alert actually shown, with its call site. That single hook is what settled this
defect after three failed attempts, and is the first thing to consult for any future
"unexpected alert" report.
