# Push notification delivery — scope

**Status:** scope only, nothing built. Raised by the owner: pushes do not arrive for added
expenses, friend requests, or other events.

Two independent defects, either of which alone stops delivery. Both are backend-shaped.

---

## PUSH-01 — the preference gates the wrong person

```swift
// AddExpenseViewModel.swift:232
if CacheService.defaults.bool(forKey: NotificationService.expensePreferenceKey) {
    await notifyExpenseAdded(...)
}
```

Profile shows a toggle titled **"New Expenses"**. Every user reads that as *"notify me when someone
adds an expense."* It actually decides **whether anyone else is notified when *you* add one**, and
`xBillApp.swift` registers it as **`false`**.

Consequences:

- The recipient's own preference is **never consulted**. Turning notifications on does nothing if
  the people you share groups with have theirs off.
- The default is off until iOS permission is granted *and*
  `enableDefaultPreferencesAfterPermissionIfNeeded()` has run on that device. A payer who declined
  the prompt silently suppresses notifications for everyone in the group.
- Same shape for `settlementPreferenceKey` (`GroupViewModel:789`) and `commentPreferenceKey`
  (`CommentService:59`).

**Friend requests are not gated at all** and are awaited inline, which is why that path is
otherwise healthy — it fails only on PUSH-02.

### Root issue
The preference lives in `UserDefaults` on the sender's device, and the only place that can honour a
*recipient's* preference is the server. There is **no server-side preference table**: `public.notifications`
stores delivered rows, not settings.

---

## PUSH-02 — the APNs environment is chosen by the wrong device

```javascript
// all four notify functions
const apnsHost = isDevelopment
  ? 'https://api.sandbox.push.apple.com'
  : 'https://api.push.apple.com'
```

`isDevelopment` is `#if DEBUG` **on the sender's build**. The sandbox/production choice must match
the **recipient's token**, which is a property of how *their* app was signed.

- App Store sender → production host. A recipient on a debug build holds a **sandbox** token →
  `BadDeviceToken`, silently.
- Debug sender → sandbox host. Any recipient on the App Store build → same failure, reversed.

**During testing this is the normal case**, and it is why the owner's own device receives nothing.

`device_tokens` is `(id, user_id, token, platform, created_at)` — **nothing records which
environment a token came from**, so the function cannot route correctly even in principle. The
stale-token cleanup on 410/400 may also be deleting perfectly good tokens that merely went to the
wrong host.

---

## Design

### Environment travels with the token
Add `environment text not null default 'production'` to `device_tokens`, constrained to
`('sandbox','production')`. The client already knows: the entitlement is `development` in a debug
build and `production` otherwise, so `#if DEBUG` at **registration** time is correct — unlike at
send time.

Each notify function then groups the recipients' tokens by environment and posts to the matching
host, instead of taking one host from the request body. `isDevelopment` is dropped from every
payload.

**Existing rows:** defaulting to `production` is wrong for any device currently on a debug build,
and there is no way to tell after the fact. Cheapest correct answer is to let the next launch
re-register — the client upserts on `(user_id, token)` and can write the environment then. Rows not
re-registered will be wrong until their next launch; they are wrong today too.

### Preferences move to the server, and mean "notify me"
New `notification_preferences (user_id, expenses bool, settlements bool, comments bool,
friend_requests bool)`, RLS-scoped to the owner. Each notify function filters recipients by the
relevant column.

The Profile toggles keep their labels — the labels were never wrong, the implementation was — and
write to this table instead of `UserDefaults`. The sender-side `if` statements are removed: **a
sender must not decide whether a recipient hears about something.**

Default: **on** for a user who has granted iOS permission. Leaving them off reproduces today's
behaviour, and the OS-level permission is already the real consent gate.

---

## Decisions needed from the owner

**1. Should the toggle mean "notify me"?** The scope assumes yes. The alternative — that it means
"do not notify others about my activity" — is defensible for privacy but is not what the label says
and not what anyone expects.
*Recommend:* recipient-side, matching the label.

**2. Default for existing users.** Nobody has a row in the new table. Defaulting to **on** starts
sending notifications people have not seen before; defaulting to **off** keeps the current silence
and needs each user to find the setting.
*Recommend:* on where iOS permission is already granted, off otherwise. That treats the OS prompt
as the consent moment, which is what it is.

**3. Whether to re-register tokens eagerly.** A one-off `DELETE FROM device_tokens` would force
every device to re-register with a correct environment on next launch, at the cost of no
notifications until each user opens the app.
*Recommend:* do not. Let them correct on next launch; a wrong row is no worse than today.

**4. Privacy manifest.** Notification preferences are a new stored data category. `PrivacyInfo.xcprivacy`
and the hosted policy may need a line.
*Recommend:* review before submission, per the standing privacy rule in `CLAUDE.md`.

---

## Phasing

**Phase 1 — PUSH-02 only.** Token environment column, client writes it at registration, four
functions route per token. Fixes delivery for everyone whose sender had the preference on. No UI
change, no preference migration.

**Phase 2 — PUSH-01.** Preferences table, functions filter by recipient, Profile writes to the
server, sender-side gates deleted.

Phase 1 is smaller and independently valuable: **it is the reason nothing arrives during testing.**
Phase 2 is the correctness fix for the feature as designed.

---

## Verification plan

- **Read-only production check** that every `device_tokens` row has an environment, and how many
  are of each after a re-registration cycle.
- **Direct function invocation** with a known recipient and a deliberately mismatched environment,
  asserting the response distinguishes "sent" from "bad token" — today both look like `{"sent":0}`.
- **Two real devices, opposite builds**: an App Store sender notifying a debug recipient and the
  reverse. This is the case that fails today and the only one that proves the fix.
- Unit coverage for the recipient-filter logic once Phase 2 lands.

**No simulator can verify this.** APNs does not deliver to a simulator, so every claim here rests
on device testing plus the functions' own responses.

---

## Risks

- **Silence looks identical to success.** Both functions return `{"sent": N}` counted from tokens
  found, not from APNs accepting them. Phase 1 should also surface APNs rejections in the response,
  or the next failure is as invisible as this one.
- **Stale-token cleanup may already have deleted good tokens** on 410/400 caused by the wrong host.
  Worth checking row counts before and after.
- Four functions must change together; one left behind fails silently for that event type only.
