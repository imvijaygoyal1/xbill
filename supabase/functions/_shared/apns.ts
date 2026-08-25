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
