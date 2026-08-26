// APNs delivery, shared by all four notify functions.
//
// PUSH-02. Every function used to pick its host like this:
//
//     const apnsHost = isDevelopment
//       ? 'https://api.sandbox.push.apple.com'
//       : 'https://api.push.apple.com'
//
// `isDevelopment` is `#if DEBUG` **on the sender's build**. The sandbox/production choice is a
// property of the **recipient's token** — of how *their* app was signed — and the sender has no
// way to know that. An App Store sender notifying someone on a debug build posted a sandbox token
// to the production host and got `BadDeviceToken`; a debug sender did the reverse. Both silently.
// During testing, where one person runs a debug build and everyone else runs the App Store build,
// the mismatch is the **normal** case, which is why nothing arrived.
//
// The environment now travels with the token (`device_tokens.environment`, migration 048), written
// by the client at registration where `#if DEBUG` genuinely does describe the local entitlement:
// `xBill.Debug.entitlements` declares `aps-environment: development`, `xBill.entitlements`
// declares `production`.
//
// This lives in `_shared` rather than being copied into each function on purpose. Four copies of
// one rule is how `INV-05` converted the emailed invite link to https and left the group QR on the
// custom scheme for two more days.

export type ApnsEnvironment = 'sandbox' | 'production'

const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  sandbox:    'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
}

/** A `device_tokens` row, as every notify function selects it. */
export interface DeviceTokenRow {
  token: string
  user_id: string
  environment: string | null
}

/**
 * Host for a token's own environment.
 *
 * Falls back to production for an unrecognised or missing value, which is what migration 048
 * defaults existing rows to: every real user is on the App Store build, and a row is only
 * corrected once that device next launches an app version that writes the column.
 */
export function apnsHost(environment: string | null | undefined): string {
  return APNS_HOSTS[environment as ApnsEnvironment] ?? APNS_HOSTS.production
}

export interface SendReport {
  /** Tokens APNs accepted. Not "notifications a person saw" — APNs does not report that. */
  sent: number
  /** Tokens APNs rejected. */
  failed: number
  /** Rejection reason → count, e.g. `{ "BadDeviceToken": 2 }`. Never contains a token. */
  reasons: Record<string, number>
  /** Recipients skipped because they muted this category (PUSH-01). Not a failure. */
  muted?: number
  /** True when the preference lookup errored and everyone was allowed through as a result. */
  preferenceLookupFailed?: boolean
}

/**
 * Post one payload to one token, on the host that token belongs to.
 *
 * Returns the APNs reason string on rejection, `null` on success. The caller aggregates.
 */
export async function sendToToken(args: {
  row: DeviceTokenRow
  jwt: string
  bundleId: string
  expiration: string
  payload: unknown
}): Promise<string | null> {
  const { row, jwt, bundleId, expiration, payload } = args
  try {
    const res = await fetch(`${apnsHost(row.environment)}/3/device/${row.token}`, {
      method: 'POST',
      headers: {
        authorization:     `bearer ${jwt}`,
        'apns-topic':      bundleId,
        'apns-push-type':  'alert',
        'apns-expiration': expiration,
        'content-type':    'application/json',
      },
      body: JSON.stringify(payload),
    })
    if (res.ok) return null
    const body = await res.json().catch(() => ({}))
    return (body as { reason?: string }).reason ?? `HTTP ${res.status}`
  } catch (err) {
    return `NetworkError: ${(err as Error).message}`
  }
}

/**
 * Whether a rejection means the token is genuinely dead and should be deleted.
 *
 * **Only `Unregistered`.** The previous code also deleted on `BadDeviceToken`, which is exactly
 * what a correctly-registered token returns when it is posted to the wrong host — so the
 * environment bug above was *deleting good tokens* every time it fired. A user whose device had
 * been notified by a mismatched sender had to reopen the app before they could be reached again,
 * and nothing recorded that it had happened.
 *
 * `BadDeviceToken` is now left in place and reported. If routing is correct it should not occur;
 * if it does, that is a signal worth seeing rather than a row worth destroying.
 */
export function isDeadToken(reason: string): boolean {
  return reason === 'Unregistered'
}

/** Accumulate one result into a report. */
export function record(report: SendReport, reason: string | null): void {
  if (reason === null) {
    report.sent++
  } else {
    report.failed++
    report.reasons[reason] = (report.reasons[reason] ?? 0) + 1
  }
}

export function newReport(): SendReport {
  return { sent: 0, failed: 0, reasons: {} }
}

// ---------------------------------------------------------------------------
// PUSH-01 — the recipient decides, not the sender
// ---------------------------------------------------------------------------

/** Column of `public.notification_preferences` a given event type is governed by. */
export type PreferenceColumn = 'expenses' | 'settlements' | 'comments' | 'friend_requests'

/**
 * Of `userIDs`, those who have not muted this category.
 *
 * Each notify function used to be gated on the **sender's** `UserDefaults` — a Profile toggle
 * labelled "New Expenses" that actually decided whether *other people* were notified, defaulting
 * to off. A sender must not decide whether a recipient hears about something, and the recipient's
 * own choice can only live somewhere the server can read.
 *
 * **A missing row means allowed.** iOS is the real consent gate: nothing displays without
 * notification permission, and the client deletes its device token when it finds permission
 * revoked, so a token only exists for someone who agreed. Treating "no row" as opt-out would
 * reproduce exactly the silence this replaces.
 *
 * **A failed lookup also means allowed**, and says so in the report. The two ways to be wrong are
 * not symmetrical: notifying someone who opted out is an annoyance they can correct in one tap,
 * while suppressing everyone on a transient database error is the failure that went unnoticed for
 * a month. Erring toward delivery keeps the failure visible.
 */
export async function recipientsAllowing(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userIDs: string[],
  column: PreferenceColumn,
): Promise<{ allowed: Set<string>; lookupFailed: boolean }> {
  const unique = [...new Set(userIDs)]
  if (unique.length === 0) return { allowed: new Set(), lookupFailed: false }

  const { data, error } = await supabase
    .from('notification_preferences')
    .select(`user_id, ${column}`)
    .in('user_id', unique)

  if (error) {
    return { allowed: new Set(unique), lookupFailed: true }
  }

  const muted = new Set(
    ((data ?? []) as Record<string, unknown>[])
      .filter(r => r[column] === false)
      .map(r => r.user_id as string),
  )
  return { allowed: new Set(unique.filter(id => !muted.has(id))), lookupFailed: false }
}

