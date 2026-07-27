# PayPal Settle-Up Handoff — Raw Diagnostic Evidence (2026-07-27)

Raw evidence for the defect described in `../../DEFECT_HANDOFF_VENMO_BALANCES.md`
(status: RESOLVED). Preserved so the investigation does not have to be repeated.

## Files

| File | What it is |
|------|------------|
| `device-diagnostics.log` | Full on-device log from `PaymentDiagnostics`, pulled from the app container on physical iPhone 16 Pro (`00008140-000135EE3432801C`). Contains the pre-fix reproduction **and** the post-fix verification. |
| `device-console-capture.log` | `devicectl … --console` stdout capture from the first launch, showing live `XBILLDIAG` output. |
| `paypal-url-verification.txt` | Independent HTTP verification of the PayPal.Me URL. |

## How to read `device-diagnostics.log`

Sessions are delimited by `===== SESSION START <timestamp> =====`.

- **`00:31:16` session — pre-fix reproduction.** Contains the failing flow:
  `GroupDetailView.openPaymentURL.request … url=https://paypal.me/appreviewer/95USD`
  followed by `openPaymentURL.result accepted=true`, then background → foreground.
  Crucially it contains **no `alert.presented` event** and no failing load: every
  `GroupViewModel.load` / `HomeViewModel.loadAll` reports `.success`, with
  `suggestions=2 hasLoadedBalances=true balanceLoadFailed=false`.
  That is the proof xBill never raised the alert the user saw.
- **`00:52:42` / `00:53:21` sessions — post-fix verification.** After the seeded
  payment handles were set to `NULL`: **no `openPaymentURL` events at all** (no payment
  buttons rendered), still zero `alert.presented`, balances healthy across two
  background/foreground cycles including an App Lock engage/release.

### Useful greps

```bash
grep -c 'alert.presented'      device-diagnostics.log   # expect 0
grep    'openPaymentURL'       device-diagnostics.log   # all hits are pre-fix (00:32–00:37)
grep -c 'balanceLoadFailed=true' device-diagnostics.log # expect 0
grep 'load.catch' device-diagnostics.log | grep -v 'silent=true'  # expect empty
```

Note: `load.catch … silent=true … CancellationError` entries around `00:53:29` are
pull-to-refresh tasks being cancelled by SwiftUI. They are suppressed by design
(`AppError.isSilent`) and are not a defect.

## `paypal-url-verification.txt`

```
appreviewer HTTP=200 final=https://www.paypal.com/paypalme/appreviewer/95USD
random-slug HTTP=404
appreviewer slugDoesNotExist_key_count= 1
random-slug slugDoesNotExist_key_count= 0
```

A nonexistent PayPal.Me profile returns **HTTP 200** serving PayPal.Me's *error* single
page app — whose string table contains
`"pages/error":{"error":{"title":{"header":"Something went wrong", … "slugDoesNotExist":"We can't find this profile"`.
It does **not** return 404. That is the string the user saw, rendered by PayPal.

Reproduce at any time:

```bash
curl -sL "https://paypal.me/<handle>/1USD" | grep -c slugDoesNotExist   # >0 ⇒ handle does not exist
```

## Regenerating this evidence

The instrumentation is DEBUG-only (`xBill/Core/PaymentDiagnostics.swift`) and compiles
out of Release.

```bash
# build + install a Debug build on the device
xcodebuild -scheme xBill -destination 'id=<UDID>' -configuration Debug \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <path/to/xBill.app>

# optional: live console (dies when the app is backgrounded)
xcrun devicectl device process launch --device <UDID> --console \
  --terminate-existing com.vijaygoyal.xbill

# reliable: pull the persisted log (survives backgrounding)
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/payment-diagnostics.log --destination ./device-diagnostics.log
```

`log stream --device-name` does **not** work on macOS 26 — the option was removed. Use
the two channels above.
