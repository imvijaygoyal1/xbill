# Notification unread lifecycle handoff

## User reproduction

1. In Recent, mark one notification unread.
2. Leave the app so the app-lock screen appears.
3. Reopen and unlock with Face ID.
4. The notification appears read again.

## Latest device evidence

Raw log: `device-diagnostics.log`.

At `2026-07-28T22:31:15Z` onward, the app records:

```text
ActivityService.markRead.failed error={... PostgrestError ... localized=Cannot coerce the result to a single JSON object}
ActivityService.markUnread.failed error={... PostgrestError ... localized=Cannot coerce the result to a single JSON object}
alert.presented ... title=Activity Update Failed
```

This happens repeatedly for both read and unread mutations. The error was introduced by the acknowledgement change in commit `2911833`, which changed the update to:

```swift
update(...).eq("id", value: id).select("id").single().execute()
```

The update response is not a single JSON object in this client/API configuration. Claude should inspect the response shape and use a reliable affected-row acknowledgement without assuming `.single()`.

## Relevant history

- `f90e50b` — explicit JSON `read_at: null` for unread transitions.
- `03eb29c` — defer activity refresh until after unlock.
- `5e649fd` — serialize per-notification read mutations.
- `2911833` — added strict row acknowledgement; current device log shows this response-shape failure.

## Important constraint

Do not treat a green unit suite as device verification. The physical-device log above is the authoritative evidence for this failure.

---

## Resolution — 2026-07-28 (commit `1a197b0`)

The framing above was wrong about the layer. The request shape was fine: `.update()` already
defaults to `Prefer: return=representation`. The update was matching **zero rows**, and
`.single()` reports that as PGRST116 *"Cannot coerce the result to a single JSON object"* —
a message about JSON coercion for what is really "no row matched".

**Root cause.** The Activity list mixes authoritative `public.notifications` rows with
expense-derived history rows synthesised for accounts predating migration 040.
`NotificationItem.expense(...)` uses the **expense id** as the item id, so a read/unread
toggle on a history row issued `UPDATE public.notifications … WHERE id = <expense id>`.
Confirmed read-only against the live database: **12 expenses, 3 notification rows, zero id
overlap**. `ActivityService.fetchRecentActivity` then forced `isRead = true` on every history
row on every refresh, so the post-unlock reload erased the user's unread mark. `2911833` did
not cause this — it converted a silent no-op into a visible alert.

See `AUDIT_REPORT.md` NOTIF-01…NOTIF-08 for the per-defect breakdown.

## Post-fix device evidence

Raw log: `after-fix.log` (same file, pulled after the fix; the pre-fix sessions are retained).

Session `2026-07-28T23:05:58Z` covers a full cycle — active → background → `isLocked=true` →
Face ID unlock → `MainTabView.unlocked.refreshBegin` / `refreshComplete` → active — with:

- **zero** `ActivityService.markRead.failed` / `markUnread.failed`
- **zero** `alert.presented … Activity Update Failed`

The last failures in the file are at `22:31:23Z`, in the pre-fix session. The user confirmed
the unread mark survived the unlock.

**Evidence gap, stated deliberately.** No `ActivityViewModel.readState.localOnly` line
appears in the post-fix session, and a *successful* toggle logs nothing. So the log proves
the absence of failures across a real lock/unlock cycle, but does not by itself show which
row kind was toggled. If the row was server-backed it took the remote path; the history-row
path — the one that produced the original zero-row failures — is best re-checked explicitly
by marking an **older expense row** unread and cycling the lock. `readState.localOnly` in the
log confirms that path was taken.
