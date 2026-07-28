# Payment Handles & Settle-Up Handoff — Agent Handoff

**Status:** Feature complete and pushed. One path still unverified on device (see [Open items](#open-items)).
**Branch:** `main`. **Last commit:** `f375847`.
**Related:** `DEFECT_HANDOFF_VENMO_BALANCES.md` (the original defect that started this — RESOLVED),
`docs/superpowers/specs/2026-07-26-payment-handles-and-diagnostics-design.md` (design),
`docs/superpowers/plans/2026-07-26-payment-handles-and-diagnostics.md` (plan),
`diagnostics/2026-07-27-paypal-handoff/` (raw device evidence),
`AUDIT_REPORT.md` entries `PAY-01`…`PAY-29`.

---

## 1. Read this first — the five findings that cost the most time

These are third-party and language behaviours that are **not obvious**, each of which produced a real bug. Do not re-derive them.

| # | Finding | Consequence if forgotten |
|---|---|---|
| 1 | **A fabricated payment handle is a live deep link.** Seeding `venmo_handle`/`paypal_handle` with a fake value makes the third-party app resolve it, fail, and show *its own* error. | Reads as an xBill defect. Cost three failed fix attempts before anyone checked whether xBill raised the alert at all. |
| 2 | **PayPal.Me ignores an amount that is not two decimal places.** `paypal.me/x/1.9USD` silently renders the plain profile page; `/1.90USD` opens a payment screen. Swift's `Decimal` interpolation drops trailing zeros, so `$95.00` became `95USD`. | Every round settlement amount produced a link with no amount. |
| 3 | **PayPal will not render a payment screen for a self-payment.** If the PayPal app is signed in as the same handle, you get the profile page regardless of amount. | Two rounds of seed rescaling were spent chasing this as if it were an amount problem. **Not an xBill bug.** |
| 4 | **Swift's synthesized `Encodable` omits nil optionals.** A PATCH that omits `venmo_handle` leaves the column untouched. | "Delete handle and Save" silently did nothing. |
| 5 | **`try?` flattening (SE-0230).** `(try? decodeIfPresent(.a)) ?? (try? decodeIfPresent(.b))` collapses to a plain `String?`, so an explicit JSON `null` for `.a` **falls through to `.b`**. | Clearing a PayPal handle resurrected the value from the legacy `paypal_email` column. Made reachable *by* the fix for #4. |

**Meta-lesson:** every serious bug this session was found by a human testing on device or by an independent reviewer — never by a passing test suite. The unit suite and the 15-test UI suite were green through all of it.

---

## 2. What the feature does

Users save a Venmo / PayPal.Me handle in Profile; xBill renders it as an outbound deep link on a group's Settle Up tab, and asks on return whether the payment completed.

| Piece | Where |
|---|---|
| Single source of truth for handle rules | `xBill/Services/PaymentHandleValidator.swift` |
| Link + profile-link construction, amount formatting | `xBill/Services/PaymentLinkService.swift` |
| Handle entry, validation messages, "Test your link" rows | `xBill/Views/Profile/ProfileView.swift`, `ProfileViewModel.swift` |
| Settle-up buttons, no-handle explanation, return prompt | `xBill/Views/Groups/GroupDetailView.swift` |
| DEBUG-only device diagnostics | `xBill/Core/AppDiagnostics.swift` |
| Demo/reviewer seed data | `supabase/seed_app_store_review_account.sql`, `SETUP_REVIEW_ACCOUNT.md` |

### Provider rules — sourced, not guessed

| Provider | Rule | Source |
|---|---|---|
| PayPal.Me | **3–20**, ASCII letters + digits only | PayPal.Me UI copy: "between 3 and 20 characters", "only using letters and numbers" |
| Venmo | **5–30**, ASCII letters, digits, `-`, `_` | [Venmo help](https://help.venmo.com/cs/articles/check-or-edit-your-username-vhel208) |

`-`/`_` are legal for Venmo and **illegal** for PayPal. `.` is illegal for **both**. Never merge the charsets. A leading `@` is stripped, never required.

### Verified URL shapes — do not change without re-verifying

```
PayPal payment:  https://paypal.me/<handle>/<amount><CURRENCY>   amount MUST be 2dp
PayPal profile:  https://paypal.me/<handle>                      no amount
Venmo payment:   venmo://paycharge?txn=pay&recipients=<handle>&amount=<amount>&note=<note>
Venmo profile:   https://venmo.com/u/<handle>                    returns 404 for a bad handle
```

`paypal.me/<bad-handle>` returns **HTTP 200** serving PayPal's *error* SPA (marker `slugDoesNotExist`), not a 404. Check with:
`curl -sL "https://paypal.me/<handle>/1.00USD" | grep -c slugDoesNotExist` — `>0` means the handle does not exist.

---

## 3. Open items

### Unverified on device — do this first
**"Mark as Settled" has never been exercised on a real device.** It is also the exact path a review found a defect in (`PAY-23`: the action re-read `@State` the alert's own binding clears, so it could record nothing while appearing to succeed). It is fixed and unit-covered, but nobody has tapped it.

Steps: Settle Up → tap PayPal → return → unlock → **Mark as Settled** → confirm the settlement disappears from Settle Up and the balance updates.

Note the demo profiles currently have **NULL** handles, so no payment button renders. To test, enter a real handle in Profile → Payment Handles first — and be aware re-running the seed wipes it back to NULL.

### Accepted residuals (low severity, deliberately not fixed)
- `GroupDetailView` `.asking` staleness guard uses `Date()` rather than a monotonic clock; a backward system-clock jump could delay recovery.
- Reading the return-prompt alert for >2 s across a background/foreground cycle re-presents the same prompt. Harmless — same payload.
- `HapticManager.success()` is gated on `vm.errorAlert == nil`; a stale undismissed unrelated error can suppress the haptic on a genuinely successful settle.
- `ProfileViewModel.isEditing` is **never assigned `true`** anywhere. Its two guards are inert, so pull-to-refresh on Profile discards unsaved field edits. No wrong write results — `saveProfile` snapshots before its first `await`. Either wire it up or delete it and its guards.
- `xBill/Views/Groups/SettleUpView.swift` is **dead code** (only its own `#Preview` references it). It did *not* receive any of this work — no handle on the button, no no-handle explanation, no return prompt. It will mislead the next reader. Delete it or bring it forward.
- `SETUP_REVIEW_ACCOUNT.md` — the App Store review notes were corrected to stop promising Venmo links, but re-check them before submission.

### Decision deferred to the user
Demo/reviewer account handles are **NULL** so a reviewer sees "Ask … to add a payment handle" and no link into anyone's personal PayPal. If you ever want the feature demonstrable to a reviewer, the *only* sound option is a real PayPal.Me/Venmo profile — a fabricated one recreates finding #1.

---

## 4. Verification playbook

### Test suites
```bash
# Unit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:xBillTests

# UI regression — MUST go through the script. Raw `xcodebuild test` does NOT inject
# XBILL_TEST_EMAIL/PASSWORD (they live in gitignored xBillUITests/UITestCredentials.plist),
# and 8 tests fail on auth bootstrap at ~20s each, which looks like a product failure.
scripts/run-coverage.sh regression-ui
```
Last known good: unit `TEST SUCCEEDED`; UI **15/15**, 0 failed, 0 skipped.

### Physical device (iPhone 16 Pro, `00008140-000135EE3432801C`)
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme xBill -destination 'id=<UDID>' -configuration Debug \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphoneos/xBill.app
```

### Reading the device log — the highest-leverage debugging tool here
```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/xbill-diagnostics.log --destination ./dev.log
```
`log stream --device-name` **does not exist on macOS 26**. The other channel is
`xcrun devicectl device process launch --console --terminate-existing com.vijaygoyal.xbill`,
which captures `print()` live but dies when the app is backgrounded — so the file is the reliable one.

Useful greps:
```bash
grep -c 'alert.presented'   dev.log   # which code path raised a user-visible alert, with file:line
grep    '\[payment\]'       dev.log   # openPaymentURL request/result + handoffPrompt lifecycle
grep    'handoffPrompt'     dev.log   # deferred -> arming -> presented
```
**`AppDiagnostics` is `#if DEBUG` only** — it records group names and money amounts and must never ship. The `Category` enum is deliberately *outside* `#if DEBUG` so Release compiles. Verify with a Release build after touching it.

### Database
```bash
supabase db query --file supabase/seed_app_store_review_account.sql --linked   # idempotent; re-NULLs handles
supabase db query --linked "select count(*) from public.profiles \
  where venmo_handle is not null or paypal_handle is not null or paypal_email is not null;"   # expect 0
```

---

## 5. Traps for the next agent

1. **The alert-presentation chokepoint is your first stop for any "unexpected alert" report.** `View.errorAlert(...)` in `xBill/Core/Extensions.swift` logs every alert actually shown with its `#fileID:#line`. Zero entries proved the original defect was not xBill's at all — after three sessions of guessing.
2. **`GroupListView.swift:89` binds `.errorAlert` *outside* the NavigationStack on the shared `HomeViewModel`,** and `MainTabView` runs `homeVM.loadAll()` on every `didBecomeActive` with errors shown. A `HomeViewModel` error therefore presents an alert **over a pushed `GroupDetailView`**, even though that view loads with `showError: false`. Check this before blaming the group screen.
3. **`xcodegen generate` no longer wipes device signing** — `DEVELOPMENT_TEAM` was added to `project.yml`. It previously lived only in `project.pbxproj`; that was the recurring "signing churn".
4. **Scope test runs to the whole suite, not the file you touched.** Two defects this session came from verifying a claim against one file and generalising.
5. **Do not scrape a provider's website to validate a handle.** It was considered and rejected: the marker lives in an undocumented JS bundle. Offer the user a "test your link" action instead — the payment app is the only reliable authority on its own links.
6. **SwiftUI presentation from a descendant during a transition gets dropped.** Setting the prompt while `ContentView` animates `AppLockView` away (0.3 s) loses it silently. A `.cancel`-role button inside `confirmationDialog` also does not reliably render with its own title — use `.alert` for a binary question.
7. **`.superpowers/sdd/` is gitignored.** The subagent-driven-development ledger for this work is preserved at `diagnostics/2026-07-27-paypal-handoff/sdd-ledger.md`; anything left in `.superpowers/` will not survive.

---

## 6. Commit trail

| Commit | What |
|---|---|
| `8fc8b1c` | Root-cause fix: fabricated seed handles → `NULL` |
| `3731c05` | Preserve raw device diagnostic evidence |
| `9f0fed1`, `4674cb2` | Design spec + verified provider rules |
| `8262f8b` | Implementation plan |
| `cded124` | `PaymentHandleValidator` |
| `ddb7f1c` | `PaymentLinkService` adopts it; `profileLink` |
| `b90a6b9` | `ProfileView` validation + test-your-link |
| `7c4beac`, `95d00d3` | Settle-up surface + return prompt |
| `18b02a9` | Seed amounts ÷50 |
| `94b00fd`, `dc787fc` | `AppDiagnostics` + atomic rotation |
| `ed62cc5` | Venmo validation test + docs |
| `6f70b62` | Two-decimal amount formatting |
| `be3bbd5` | Prompt presentation deferral; `confirmationDialog` → `.alert` |
| `abe037f` | Final-review fixes: handle wipe, `presenting:` overload, `HandoffState` enum |
| `4422a31` | `encodeNil` so clearing a handle writes NULL |
| `0fd42f5` | **Critical:** `paypal_email` lockstep; `.asking` recovery |
| `f375847` | `AUDIT_REPORT.md` `PAY-22`…`PAY-29` |
