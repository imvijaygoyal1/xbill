# Device diagnostics — index

Raw on-device evidence from `AppDiagnostics` (DEBUG-only; compiles out of Release).
Preserved so investigations do not have to be repeated.

## Conventions — read before adding anything here

1. **This is the only README under `diagnostics/`.** Dated folders hold **raw evidence
   only** — logs, captures, verification output. Do not add a second README; append to the
   index below instead. (Broken once, on 2026-07-28, which produced two competing handoff
   documents for one defect.)
2. **Findings never live here.** `../AUDIT_REPORT.md` is the single source: every defect gets
   an ID, file, issue, status and fix. This file says *what evidence exists and how to read
   it*, and points at the audit entry for *what it means*.
3. **Never claim a lifecycle behaviour from a passing test suite.** Every serious defect in
   this project was found by a human on a physical device or by an independent reviewer, with
   the unit and UI suites green throughout. Pull the log.
4. **Log the success path, not just failures.** A log that only records errors can prove the
   absence of a failure but never which code path ran. That gap cost an extra device
   round-trip in the 2026-07-28 investigation.

## Index of investigations

| Date | Investigation | Outcome | Evidence | Findings |
|------|---------------|---------|----------|----------|
| 2026-07-26 | PayPal settle-up handoff — fabricated seed handles | ✅ Resolved. Not an xBill defect: a seeded fake handle is a live deep link and PayPal rendered *its own* error. | `2026-07-27-paypal-handoff/` | `../AUDIT_REPORT.md` → Payment Handoff Defect; `../HANDOFF_PAYMENT_HANDLES.md` |
| 2026-07-27 | Payment handle feature: validator, test-link, return prompt, diagnostics | ✅ Shipped | `2026-07-27-paypal-handoff/sdd-ledger.md` | `../AUDIT_REPORT.md` → `PAY-01`…`PAY-29` |
| 2026-07-28 | Notification unread state lost across an app-lock cycle | ✅ Resolved, device-verified on every path | `2026-07-28-notification-unread/` | `../AUDIT_REPORT.md` → `NOTIF-01`…`NOTIF-12` |

Append a row at the end of each investigation.

## Pulling a log

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/xbill-diagnostics.log --destination ./device-diagnostics.log
```

`log stream --device-name` does **not** work on macOS 26 — the option was removed. The other
channel is `xcrun devicectl device process launch --console --terminate-existing
com.vijaygoyal.xbill`, which captures `print()` live but dies when the app is backgrounded,
so the file above is the reliable one.

Rebuild and install a Debug build first — the instrumentation is `#if DEBUG`:

```bash
xcodebuild -scheme xBill -destination 'id=<UDID>' -configuration Debug \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <path/to/xBill.app>
```

Sessions in every log are delimited by `===== SESSION START <timestamp> =====`.
Physical device throughout: iPhone 16 Pro `00008140-000135EE3432801C`.

---

## `2026-07-27-paypal-handoff/`

A settle-up handoff ended in a PayPal error screen. **Root cause and findings:
`../AUDIT_REPORT.md` → `PAY-01`…`PAY-29`.** Provider rules and URL shapes:
`../HANDOFF_PAYMENT_HANDLES.md`.

| File | What it is |
|------|------------|
| `device-diagnostics.log` | Full `AppDiagnostics` log. Contains the pre-fix reproduction **and** the post-fix verification. |
| `device-console-capture.log` | `devicectl … --console` stdout from the first launch, showing live `XBILLDIAG` output. |
| `paypal-url-verification.txt` | Independent HTTP verification of the PayPal.Me URL. |
| `sdd-ledger.md` | Preserved per-task ledger (its original home under `.superpowers/` is gitignored). |

- **`00:31:16` session — pre-fix reproduction.** `GroupDetailView.openPaymentURL.request …
  url=https://paypal.me/appreviewer/95USD` then `openPaymentURL.result accepted=true`, then
  background → foreground. Crucially **no `alert.presented` event** and no failing load:
  every `GroupViewModel.load` / `HomeViewModel.loadAll` reports `.success` with
  `suggestions=2 hasLoadedBalances=true balanceLoadFailed=false`. That is the proof xBill
  never raised the alert the user saw.
- **`00:52:42` / `00:53:21` sessions — post-fix verification.** With seeded handles set to
  `NULL`: no `openPaymentURL` events at all (no payment buttons rendered), still zero
  `alert.presented`, balances healthy across two background/foreground cycles including an
  App Lock engage/release.

```bash
grep -c 'alert.presented'        device-diagnostics.log   # expect 0
grep    'openPaymentURL'         device-diagnostics.log   # all hits are pre-fix (00:32–00:37)
grep -c 'balanceLoadFailed=true' device-diagnostics.log   # expect 0
grep 'load.catch' device-diagnostics.log | grep -v 'silent=true'   # expect empty
```

`load.catch … silent=true … CancellationError` around `00:53:29` is pull-to-refresh being
cancelled by SwiftUI — suppressed by design (`AppError.isSilent`), not a defect.

**`paypal-url-verification.txt`** records that a nonexistent PayPal.Me profile returns
**HTTP 200** serving PayPal's *error* SPA rather than a 404 — the source of the string the
user saw. The rule and the `slugDoesNotExist` reproduction command live in
`../HANDOFF_PAYMENT_HANDLES.md` §2.

---

## `2026-07-28-notification-unread/`

Marking a Recent notification unread reverted to read after backgrounding, Face ID unlock and
returning. **Root cause, all 12 defects and the device-verification matrix:
`../AUDIT_REPORT.md` → `NOTIF-01`…`NOTIF-12`.** Fixed in `1a197b0` + `9ffc781`.

| File | What it is |
|------|------------|
| `device-diagnostics.log` | Pre-fix. The original reproduction. |
| `after-fix.log` | First post-fix pull. |
| `after-followup.log` | Final. Supersedes the other two. |

| Session | Shows |
|---------|-------|
| `22:31:15Z` (`device-diagnostics.log`) | Pre-fix failures: `markRead.failed` / `markUnread.failed`, each followed by `alert.presented … Activity Update Failed`. |
| `23:05:58Z` (`after-fix.log`) | Lock → Face ID → unlock cycle, zero failures — but a successful toggle logged nothing, so it cannot show *which* row kind ran (`NOTIF-12`). |
| `23:47:42Z` + `00:30:11Z` (`after-followup.log`) | Final verification, both row kinds and both actions. |

```bash
grep -E '\.failed|rowNotFound|Activity Update Failed' after-followup.log   # expect empty post-fix
grep -E 'readState\.|delete\.'                        after-followup.log   # which path each action took
```

`readState.localOnly` / `delete.localOnly` mean an expense-derived history row;
`readState.remote … succeeded=true` means a `public.notifications` row. Ids beginning
`EEEEEEEE-` are seeded demo data, hence history rows.

> **Reading `device-diagnostics.log`:** the obvious reading of its `Cannot coerce the result
> to a single JSON object` errors is wrong, and the handoff that opened this investigation
> repeated it. The message names JSON; the fault is a row count. See `NOTIF-04`.
