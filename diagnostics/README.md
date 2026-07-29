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

**`paypal-url-verification.txt`:**

```
appreviewer HTTP=200 final=https://www.paypal.com/paypalme/appreviewer/95USD
random-slug HTTP=404
appreviewer slugDoesNotExist_key_count= 1
random-slug slugDoesNotExist_key_count= 0
```

A nonexistent PayPal.Me profile returns **HTTP 200** serving PayPal.Me's *error* SPA, whose
string table contains `"pages/error":{"error":{"title":{"header":"Something went wrong", …
"slugDoesNotExist":"We can't find this profile"`. It does **not** return 404. That is the
string the user saw, rendered by PayPal. Reproduce with
`curl -sL "https://paypal.me/<handle>/1USD" | grep -c slugDoesNotExist` — `>0` means the
handle does not exist.

---

## `2026-07-28-notification-unread/`

Marking a Recent notification unread reverted to read after backgrounding, Face ID unlock and
returning. Findings: `../AUDIT_REPORT.md` → `NOTIF-01`…`NOTIF-12`. Fixed in `1a197b0` +
`9ffc781`.

| File | What it is |
|------|------------|
| `device-diagnostics.log` | Pre-fix. The original reproduction. |
| `after-fix.log` | First post-fix pull. Read state verified, but see the gap below. |
| `after-followup.log` | Final. Every path verified; supersedes the other two. |

### The original theory was wrong — do not repeat it

The handoff that opened this investigation concluded *"the update response is not a single
JSON object in this client/API configuration"* and directed the next agent to inspect the
response shape. That is the wrong layer. `.update()` already defaults to
`Prefer: return=representation`; the request was fine. The update was matching **zero rows**,
because the id being written was an *expense* id and no such row exists in
`public.notifications` (verified read-only against the live DB: 12 expenses, 3 notification
rows, zero id overlap). `.single()` reports a zero-row match as PGRST116 *"Cannot coerce the
result to a single JSON object"* — a message about JSON for what is really a row count.

Worth remembering: the error message named the wrong layer, and the handoff repeated it.

### Reading the logs

| Session | Shows |
|---------|-------|
| `22:31:15Z` (`device-diagnostics.log`) | Pre-fix. Repeated `markRead.failed` / `markUnread.failed` with the coercion message, each followed by `alert.presented … Activity Update Failed`. |
| `23:05:58Z` (`after-fix.log`) | Post-fix. Full lock → Face ID → unlock cycle, zero failures. **But** a successful toggle logged nothing, so it could not show *which* row kind ran — the gap that motivated the success-path logging in `9ffc781`. |
| `23:47:42Z` + `00:30:11Z` (`after-followup.log`) | Final verification, gap closed. |

```text
23:48:04  readState.localOnly  id=EEEEEEEE-0001-…  isRead=false  serverBacked=false
23:48:17  readState.remote     id=2D660169-8B56-…  isRead=true   succeeded=true
23:48:19  readState.remote     id=2D660169-8B56-…  isRead=false  succeeded=true
00:30:11  delete.localOnly     id=EEEEEEEE-0001-…
00:30:22  isLocked=true  →  unlocked.refreshBegin / refreshComplete  →  active
```

**0 failure lines** in that session. The `EEEEEEEE-0001-…` id is a seeded demo expense, so
both the unread mark and the delete provably exercised the expense-derived history path — the
one whose zero-row writes started this.

| | History row | Server row |
|---|---|---|
| Mark unread | ✅ `readState.localOnly`, survived unlock | ✅ `readState.remote succeeded=true`, survived unlock |
| Delete | ✅ `delete.localOnly`, stayed deleted | Unit-tested only |

Deleting a **server-backed** row was deliberately not exercised on device: it permanently
removes one of only three real notification rows, and its acknowledgement is the same
`acknowledgeAffectedRows(_:id:)` path confirmed live by the read-state update.

```bash
grep -E '\.failed|rowNotFound|Activity Update Failed' after-followup.log   # expect empty post-fix
grep -E 'readState\.|delete\.'                        after-followup.log   # which path each action took
```
