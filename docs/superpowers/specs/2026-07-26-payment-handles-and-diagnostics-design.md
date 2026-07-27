# Payment Handle Experience + Unified Diagnostics — Design

**Date:** 2026-07-26
**Status:** Approved, pending implementation plan

> Date note: related artifacts (`diagnostics/2026-07-27-paypal-handoff/`, the 2026-07-27
> `CLAUDE.md` entry) are named from **UTC** device-log timestamps. Local date is
> 2026-07-26. Same work, one day apart in naming.

## Background

On 2026-07-26 a PayPal settle-up handoff showed "Something went wrong". The message came
from the **PayPal app**, not xBill: `seed_app_store_review_account.sql` seeded a
fabricated handle (`appreviewer`), `PaymentLinkService` turned it into a live deep link,
and PayPal failed to resolve it. Three prior fix attempts edited xBill lifecycle code and
none worked. Full detail: `DEFECT_HANDOFF_VENMO_BALANCES.md`.

The seed is fixed (handles `NULL`). This design covers what was *exposed* by that
investigation: xBill cannot tell a user whether a payment handle works, never learns the
outcome of a handoff, and hides the payment button with no explanation. It also unifies
diagnostics so the next investigation has one place to look.

## Goals

1. Make an unusable payment handle discoverable **at entry time**, by the person who owns it.
2. Stop third-party failures reading as xBill failures.
3. Close the loop after a handoff so debts don't silently stay open.
4. Explain the absent-payment-button state instead of rendering nothing.
5. Make on-device testing of the real handoff safe, by scaling seeded amounts down so a
   stray tap cannot send meaningful money.
6. One diagnostic log file per app, usable by any future agent for any investigation.

## Non-goals

- Seeding payment handles. Seeded handles stay `NULL`; a fabricated handle is what caused
  the defect. The demo account's handle is entered by the user through the app.
- Programmatic verification by scraping PayPal (see Approach A, rejected).
- Changing the existing `Logger`/os_log call sites — they remain useful in Release.
- A "Don't ask again" escape on the return prompt. Deliberately omitted (YAGNI): it costs a
  persisted preference, a settings toggle to undo it, and a support question, to save one
  tap on an infrequent action. Add it if the prompt proves annoying in practice — that
  would be evidence rather than speculation.
- **Cross-app agent handoff logging — deferred to Spec 2.** Shady Spade's own
  `AppDiagnostics` log plus a `Stop` hook in `settings.json` so the per-app agent handoff
  log is updated whenever an agent session ends. Agreed approach: **option C** — the hook
  appends a mechanical session record (timestamp, branch, commits, files changed) and emits
  a non-blocking reminder for the agent to add narrative context. Blocking the stop until a
  narrative exists was rejected: Stop hooks that refuse to stop are a known source of loops
  and can strand an agent that is genuinely finished. A hook runs a shell command, not a
  model, so it can guarantee the facts but cannot write the "why" — that stays the agent's
  job, prompted by a `CLAUDE.md` convention. Separate repo, separate concern; it shares
  nothing with this spec but the word "log".

---

## 1. `PaymentHandleValidator` — one validator, two distinct rule sets

**Problem.** Handle rules exist in two places that disagree:

- `ProfileView.paypalValidationMessage` — allows `. - _`, minimum 2 chars
- `PaymentLinkService.normalizedHandle` — `^[a-zA-Z0-9._-]{2,}$`, then `paypalLink`
  re-validates with a *third* regex

PayPal.Me actually requires **3–20 letters and digits**. So `a.b` passes entry today and
can never produce a working link.

**Design.** New `xBill/Services/PaymentHandleValidator.swift`, the single source of truth,
consumed by both `ProfileView` (input) and `PaymentLinkService` (output).

```swift
enum PaymentHandleValidator {
    enum Provider { case venmo, paypal }
    enum Result: Equatable { case valid(String), invalid(reason: String), empty }
    static func validate(_ raw: String?, for provider: Provider) -> Result
}
```

Both rule sets are taken from the providers' own documentation, not inferred:

| Provider | Rule | Source | `@` prefix |
|---|---|---|---|
| PayPal.Me | 3–20 chars, `[A-Za-z0-9]` only | PayPal.Me UI copy: "between 3 and 20 characters", "only using letters and numbers" | stripped if present |
| Venmo | 5–30 chars, `[A-Za-z0-9_-]` | [Venmo help](https://help.venmo.com/cs/articles/check-or-edit-your-username-vhel208): "must be between 5 and 30 characters", "no special characters other than `-` and `_`" | stripped if present |

**The two charsets must stay separate.** `-` and `_` are legal for Venmo and illegal for
PayPal, so a shared charset would be wrong for one provider. Note also that `.` is illegal
for **both** — today's code allows it for both, and allows 2-character handles that neither
provider permits.

`validate` trims whitespace and returns the normalised handle on success, so callers never
re-normalise.

**Compatibility.** Tightening either rule cannot invalidate a stored handle: after the seed
fix, `select count(*) … where venmo_handle is not null or paypal_handle is not null`
returns `0`. This is the free moment to tighten — the window closes as soon as a real
handle is entered.

## 2. Test-your-link

Once a **saved** handle validates, `ProfileView` shows a row: **"Test your PayPal link"** /
**"Test your Venmo link"**. It opens the handle's profile URL — `https://paypal.me/<handle>`
with **no amount**, so no payment screen appears.

Rationale: the ground truth is "does the payment app accept this link", so the payment app
answers it. Nothing to break, no scraping, works for both providers.

Shown only when the saved value validates and there are no unsaved edits, so it always
tests what is actually stored.

### Rejected: live reachability check

`GET https://paypal.me/<handle>` and detect PayPal's `slugDoesNotExist` marker. Rejected:
the marker lives in an undocumented JS bundle, so PayPal can rename it and the check
silently starts passing bad handles; it adds a network call to profile save; Venmo has no
equivalent, leaving half the feature unverified. It is another unverifiable assumption
about a third party — the shape of the original bug. May be revisited later as an
advisory-only, fail-open check.

## 3. Settle-up surface

In `GroupDetailView.settlementRow`:

- **Button shows the destination:** `PayPal · @handle`, so a payer can spot a wrong
  recipient before leaving the app.
- **No usable handle:** render `"Ask <Name> to add a payment handle"` instead of nothing.
  Informational text, not a button.
- Both driven by `PaymentHandleValidator`, so a button appears only when the link is
  actually buildable.

## 4. Return prompt

`GroupDetailView` records a pending handoff when `openURL`'s completion reports
`accepted == true`. On the next `scenePhase == .active` it presents:

> **Did you complete this payment?** → *Mark as Settled* / *Not yet*

*Mark as Settled* calls the existing `recordSettlement(_:)`. Default is **unmarked**;
nothing auto-settles.

Guards:

| Guard | Why |
|---|---|
| Only when `accepted == true` | No prompt if the payment app never opened. |
| Cleared after one answer | Otherwise it re-asks on every later foreground. |
| Suppressed while `AppLockService.isLocked`, deferred until unlock | The dialog would otherwise render behind the lock overlay. App Lock is enabled on the primary test device, so this path is hit every time. |

State lives in `GroupDetailView` as `@State private var pendingHandoff: PendingHandoff?`
(`suggestion` + `providerName`). It is view state, not model state — a handoff has no
meaning once the screen is gone.

## 5. Seeded amounts scaled ÷50

Once a real handle is entered on the demo account, tapping PayPal in Tokyo Trip opens a
**genuine payment screen** for the settlement amount. At today's `$95.00` a stray tap
during testing sends real money. All seeded amounts are divided by 50.

Every value lands on an exact 2-decimal result, so splits still sum to their expense
totals and no `is_settled` flag or rounding behaviour changes:

| Row | Now | ÷50 |
|---|---|---|
| Flights / Hotel / Sushi / Nikko / Store | 180 / 90 / 120 / 60 / 45 | 3.60 / 1.80 / 2.40 / 1.20 / 0.90 |
| Equal splits (60 / 30 / 20 / 15) | 60.00 etc. | 1.20 / 0.60 / 0.40 / 0.30 |
| Sushi's uneven split | 50 / 40 / 30 | 1.00 / 0.80 / 0.60 |
| IOU | 25.00 | 0.50 |
| **Settlement suggestion** | **95.00** | **1.90** |

Tokyo Trip stays structurally intact: 5 expenses, 15 splits, 3 members, 2 comments, 1 IOU,
same settled/unsettled pattern. Only magnitudes change.

**Why ÷50 rather than ÷100** (which would give `$0.95`): PayPal.Me may enforce a $1.00
minimum. That is **unverified** — it cannot be tested without a real handle — so the scale
deliberately stays above any dollar floor rather than risk "minimum" reintroducing a
broken-link failure. `$1.90` is trivial to fumble and safely above it.

`SETUP_REVIEW_ACCOUNT.md` documents expected balances (owed `$220` / owes `$50` /
net `$170`). These become owed `$4.40` / owes `$1.00` / net `$3.40` and must be updated in
the same change, or the doc silently contradicts the seed.

## 6. Unified diagnostics

`PaymentDiagnostics` → **`AppDiagnostics`** (`xBill/Core/AppDiagnostics.swift`).

- **File:** `Documents/xbill-diagnostics.log` — investigation-neutral, one per app.
- **API:** `AppDiagnostics.log(.payment, "openPaymentURL.request", [("url", url)])`
- **Line format:** `[ISO8601] [category] event key=value key=value`
- **Categories:** `.payment .auth .balance .lifecycle .sync`
- **Rotation:** 2 MB cap; on overflow retain the newest half. Bounded by construction.
- **`#if DEBUG` only** — records group names and amounts; must never ship.
- **Retained:** the alert-presentation chokepoint in `View.errorAlert(...)`
  (`Extensions.swift`), which records every alert shown with its `#fileID:#line`. That hook
  is what identified this defect after three failed attempts.

**Repo side:** `diagnostics/README.md` is the per-app index. Each agent appends a dated
entry linking to its own artifact folder. One place to look, without a single
ever-appended file generating permanent merge conflicts.

## Testing

**Unit — `PaymentHandleValidatorTests` (new)**

- PayPal length boundaries: 2 rejected, 3 accepted, 20 accepted, 21 rejected
- Venmo length boundaries: 4 rejected, 5 accepted, 30 accepted, 31 rejected
- PayPal rejects `.`, `-`, `_`, spaces, `@`-infix, unicode
- Venmo accepts `-` and `_`; rejects `.`, spaces, `/`
- Cross-check: a handle legal for one provider and illegal for the other resolves
  correctly per provider (e.g. `my_handle` valid for Venmo, invalid for PayPal)
- `@` prefix stripped for both; whitespace trimmed
- Empty/nil → `.empty`, distinct from `.invalid`

**Unit — `PaymentHandoffTests` (extend)**

- `PaymentLinkService` accepts exactly what the validator accepts (no divergence)
- **No existing expectation inverts.** The current suite only exercises PayPal handles that
  are alphanumeric (`realhandle`, `@realhandle`) or contain `space / @ % ? #` — all still
  rejected under the new rule. `.`, `-`, `_` and the 3–20 length bounds are simply
  *uncovered* today; they are new cases, not changed ones. The existing 40 cases should
  still pass unmodified, which is a useful signal that the validator swap was behaviour-
  preserving where it should be.
- Test-link URL omits the amount and matches `https://paypal.me/<handle>`

**UI — `RegressionUITests` (extend)**

- Settle-up button shows the handle
- No-handle recipient shows the "Ask … to add a payment handle" text and no button
- Return prompt appears after a handoff; *Not yet* leaves the settlement unmarked

**Manual, physical device**

- Enter a real PayPal handle in Profile → "Test your PayPal link" resolves to a real profile
- Tokyo Trip settle-up shows `PayPal · @handle`
- Handoff → return → prompt appears after Face ID unlock, not behind the lock overlay

## Risks

| Risk | Mitigation |
|---|---|
| Return prompt is new behaviour for every user after every handoff | Two plain options, defaults to unmarked, dismissible; cleared after one answer. |
| Tightened PayPal rule rejects a legitimate handle | No stored handles exist (verified `count = 0`). Rule matches PayPal's own published constraint. |
| Prompt fires when the user never actually left | Gated on `accepted == true`. |
| Diagnostics log grows unbounded on device | 2 MB cap with rotation; DEBUG-only. |
| Scaled seed amounts drift from documented expected balances | `SETUP_REVIEW_ACCOUNT.md` updated in the same change; ÷50 is exact at 2dp so splits still reconcile. |
| `$1.90` falls below an unverified PayPal.Me minimum | ÷50 chosen over ÷100 specifically to stay above a possible $1.00 floor; confirmed on-device with a real handle during manual verification. |
