# Venmo / PayPal Settle-Up Handoff Defect

## Status: RESOLVED — 2026-07-27

> **Follow-on work:** this defect exposed several gaps that were then built out as a
> feature (shared handle validator, test-your-link, settle-up surface, return prompt,
> unified diagnostics). See **`HANDOFF_PAYMENT_HANDLES.md`** for the current state and
> open items — that is the live handoff; this document is the historical root-cause record.

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

Raw logs are preserved in `diagnostics/2026-07-27-paypal-handoff/` (see `diagnostics/README.md`
for how to read and regenerate them). Decisive excerpt from the **pre-fix reproduction** —
note the handoff to a nonexistent PayPal profile, and that every subsequent load succeeds
with no alert:

```text
[00:32:19.067Z] GroupDetailView.openPaymentURL.request provider=PayPal scheme=https host=paypal.me url=https://paypal.me/appreviewer/95USD group=Tokyo Trip
[00:32:19.158Z] GroupDetailView.openPaymentURL.result provider=PayPal accepted=true
[00:32:19.902Z] ContentView.scenePhase from=inactive to=background appLockEnabled=true isLocked=false
[00:32:36.274Z] ContentView.scenePhase from=background to=inactive appLockEnabled=true isLocked=true
[00:32:36.551Z] MainTabView.didBecomeActive connected=true groups=1
[00:32:36.909Z] GroupViewModel.load.success group=Tokyo Trip expenses=5 suggestions=2 hasLoadedBalances=true balanceLoadFailed=false
[00:32:37.290Z] HomeViewModel.loadAll.success groups=1
```

No `alert.presented` event appears anywhere in that session, or in the whole log.

**Post-fix verification** (handles `NULL`) — no `openPaymentURL` events at all, because no
payment button renders:

```text
[00:53:24.645Z] GroupViewModel.load.success group=Tokyo Trip expenses=5 suggestions=2 hasLoadedBalances=true balanceLoadFailed=false
[00:54:06.114Z] GroupDetailView.scenePhase group=Tokyo Trip from=inactive to=active connected=true expenses=5 suggestions=2 isLoading=false isLoadingBalances=false hasLoadedBalances=true balanceLoadFailed=false
[00:54:06.810Z] GroupViewModel.load.success group=Tokyo Trip expenses=5 suggestions=2 hasLoadedBalances=true balanceLoadFailed=false
[00:54:07.273Z] MainTabView.didBecomeActive.refreshComplete
```

Counters over the full log:

| Check | Pre-fix | Post-fix |
|---|---|---|
| `alert.presented` | 0 | 0 |
| `openPaymentURL` | 6 | 0 |
| `balanceLoadFailed=true` | 0 | 0 |
| non-silent `load.catch` | 0 | 0 |

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

## Open decisions for the next agent

Neither is a defect. Both are product calls the user has been asked about and has not
yet decided. **Do not silently resolve them.**

1. **The demo account now shows no payment buttons at all.** Correct and safe, but the
   settle-up payment feature is no longer demonstrable to an App Store reviewer. The only
   sound way to make it visible is a **real** PayPal.Me / Venmo handle on the reviewer
   profile. A fabricated one will always fail the way this defect did. If a real handle is
   ever added, note that tapping PayPal opens a genuine payment screen for the settlement
   amount (`$95` in the seed) — verification must stop before completing payment.
2. **`PaymentDiagnostics` instrumentation is still in the tree.** DEBUG-only, verified to
   compile out of Release. Retained deliberately because the alert-presentation chokepoint
   is what broke a three-session deadlock. The user was offered removal or trimming to just
   the chokepoint and has not chosen. Options:
   - keep as-is;
   - trim to the chokepoint in `Extensions.swift` + `openPaymentURL` logging, dropping the
     verbose `load.enter`/`load.success`/`scenePhase` entries;
   - remove entirely (also delete `xBill/Core/PaymentDiagnostics.swift` and its call sites
     in `HomeViewModel`, `GroupViewModel`, `GroupDetailView`, `MainTabView`, `ContentView`).

## Reverting the database change, if ever needed

Original values before the fix (only these three seeded demo rows had handles; no real
user data was affected):

| Profile | venmo_handle | paypal_handle | paypal_email |
|---|---|---|---|
| App Reviewer | `appreviewer` | `appreviewer` | `appreviewer@xbill.vijaygoyal.org` |
| Alice Chen | `alicechen` | `null` | `null` |
| Bob Patel | `bobpatel` | `null` | `null` |

Restoring them would reintroduce the defect. Current state:

```bash
supabase db query --linked "select count(*) from public.profiles \
  where venmo_handle is not null or paypal_handle is not null or paypal_email is not null;"
# => 0
```

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
