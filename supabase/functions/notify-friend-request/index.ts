import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import {
  deliver, isDeadToken, newReport, record, recipientsAllowing,
  type DeviceTokenRow,
} from '../_shared/apns.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const ALLOWED_ORIGIN = SUPABASE_URL  // M4: restrict CORS to project origin

const corsHeaders = {
  'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ---------------------------------------------------------------------------
// APNs JWT cache — reuse for up to 55 minutes to avoid per-request P-256 ops
// ---------------------------------------------------------------------------

// Note: Deno Edge Functions spin up a new isolate per invocation, so this
// module-level cache is request-scoped. It only helps within a single
// request that calls getAPNsJWT() multiple times.
let cachedJWT: string | null = null
let jwtExpiresAt = 0

async function getAPNsJWT(teamId: string, keyId: string, pem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJWT && now < jwtExpiresAt) return cachedJWT
  cachedJWT = await generateAPNsJWT(teamId, keyId, pem)
  jwtExpiresAt = now + 55 * 60
  return cachedJWT
}

// ---------------------------------------------------------------------------
// H1: verify the caller is an authenticated Supabase user
// ---------------------------------------------------------------------------

async function requireAuth(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return null
  const jwt = authHeader.replace('Bearer ', '')
  const adminClient = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const { data: { user }, error } = await adminClient.auth.getUser(jwt)
  if (error || !user) return null
  return user.id
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // H1: reject unauthenticated callers
  const callerID = await requireAuth(req)
  if (!callerID) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const {
      toUserID,
    } = await req.json()

    const supabase = createClient(
      SUPABASE_URL,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    if (!toUserID) throw new Error('toUserID is required')

    const { data: requestRow, error: requestError } = await supabase
      .from('friends')
      .select('id, status')
      .eq('requester_id', callerID)
      .eq('addressee_id', toUserID)
      .maybeSingle()

    if (requestError) throw requestError
    if (!requestRow || requestRow.status !== 'pending') {
      return new Response(JSON.stringify({ sent: 0, failed: 0, reasons: {} }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: sender } = await supabase
      .from('profiles')
      .select('display_name')
      .eq('id', callerID)
      .maybeSingle()
    const fromName = sender?.display_name ?? 'Someone'

    const { error: notificationError } = await supabase.from('notifications').upsert({
        recipient_id: toUserID,
        dedupe_key: `friendRequest:${requestRow.id}:${toUserID}`,
        event_type: 'friendRequest',
        title: 'Friend Request',
        subtitle: `${fromName} wants to split expenses with you`,
        amount: 0,
        currency: 'USD',
        category: 'other',
      }, { onConflict: 'dedupe_key', ignoreDuplicates: true })
    if (notificationError) throw notificationError

    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token, environment')
      .eq('user_id', toUserID)

    if (!tokenRows?.length) {
      return new Response(JSON.stringify({ sent: 0, failed: 0, reasons: {} }), { headers: corsHeaders })
    }

    const teamId   = Deno.env.get('APNS_TEAM_ID')!
    const keyId    = Deno.env.get('APNS_KEY_ID')!
    const pem      = Deno.env.get('APNS_PRIVATE_KEY')!
    const bundleId = 'com.vijaygoyal.xbill'
    // M-23: 24 h expiration so notifications survive an offline device (was 1 h)
    const expiration = String(Math.floor(Date.now() / 1000) + 86400)

    const jwt = await getAPNsJWT(teamId, keyId, pem)

    const { count: unreadCount } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('recipient_id', toUserID)
      .is('read_at', null)

    const apnsPayload = {
      aps: {
        alert: {
          title: 'Friend Request',
          body:  `${fromName} wants to split expenses with you`,
        },
        sound: 'default',
        badge: unreadCount ?? 0,
      },
    }

    const report = newReport()

    // PUSH-01: the RECIPIENT decides whether they hear about this, not the sender. The in-app
    // `notifications` rows above are written regardless — muting a push means "do not interrupt
    // me", not "hide this from my history", and a row never written cannot be caught up on.
    const preference = await recipientsAllowing(supabase, [toUserID], 'friend_requests')
    if (preference.lookupFailed) report.preferenceLookupFailed = true
    if (!preference.allowed.has(toUserID)) {
      report.muted = 1
      return new Response(
        JSON.stringify(report),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    for (const row of (tokenRows as DeviceTokenRow[])) {
      try {
        // PUSH-02: the host comes from THIS token's environment, not from the sender's build —
        // and if that environment turns out to be wrong, `deliver` finds the right one and tells
        // us, so the row can be corrected instead of the user staying silent until they update.
        const { reason, correctedEnvironment } =
          await deliver({ row, jwt, bundleId, expiration, payload: apnsPayload })
        record(report, reason)

        if (correctedEnvironment) {
          await supabase.from('device_tokens')
            .update({ environment: correctedEnvironment })
            .eq('token', row.token)
          report.corrected = (report.corrected ?? 0) + 1
        }

        // Delete only what APNs calls Unregistered. `BadDeviceToken` is what a perfectly good
        // token returns when posted to the wrong host, so the old condition was destroying
        // working registrations every time the environment mismatched — silently.
        if (reason !== null && isDeadToken(reason)) {
          await supabase.from('device_tokens').delete().eq('token', row.token)
        }
      } catch (err) {
        // Reached only by something other than the APNs post — `sendToToken` handles network
        // failure itself. This used to swallow the error, and the token simply vanished from
        // the count with nothing recorded anywhere.
        record(report, `UnexpectedError: ${(err as Error).message}`)
      }
    }

    // Log the OUTCOME, not just failures. A 200 from this function says only that it did not
    // crash — it says nothing about whether APNs accepted anything, and `function_edge_logs`
    // records the status code but never the body. Without this line, "delivered" and "silently
    // rejected by APNs" are indistinguishable from outside. Same lesson as the 2026-07-28
    // notification work: log the success path or you can prove an absence of errors and still
    // not know which path ran. Counts only — never a token, never a recipient id.
    console.log(`[notify-friend-request] ${JSON.stringify(report)}`)

    return new Response(
      JSON.stringify(report),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: corsHeaders }
    )
  }
})

// ---------------------------------------------------------------------------
// APNs JWT (ES256) using Web Crypto API
// ---------------------------------------------------------------------------

async function generateAPNsJWT(teamId: string, keyId: string, privateKeyPem: string): Promise<string> {
  const toBase64Url = (input: ArrayBuffer | string): string => {
    const bytes = typeof input === 'string'
      ? input
      : String.fromCharCode(...new Uint8Array(input))
    return btoa(bytes).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  }

  const header  = JSON.stringify({ alg: 'ES256', kid: keyId })
  const payload = JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })

  const headerB64  = toBase64Url(header)
  const payloadB64 = toBase64Url(payload)
  const signingInput = `${headerB64}.${payloadB64}`

  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  const encoder   = new TextEncoder()
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: { name: 'SHA-256' } },
    privateKey,
    encoder.encode(signingInput)
  )

  return `${signingInput}.${toBase64Url(signature)}`
}
