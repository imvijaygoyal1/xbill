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
