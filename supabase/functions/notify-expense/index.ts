import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

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
      expenseId,
      groupId,
      payerId,
      payerName,
      expenseTitle,
      amount,
      currency,
      isDevelopment,
    } = await req.json()

    const supabase = createClient(
      SUPABASE_URL,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Fetch all group members
    const { data: members, error: membersError } = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', groupId)

    if (membersError || !members?.length) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: corsHeaders })
    }

    const memberIDs = members.map((m: { user_id: string }) => m.user_id)

    // Fetch device tokens — user_id retained for sender exclusion and badge
    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token, user_id')
      .in('user_id', memberIDs)

    if (!tokenRows?.length) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: corsHeaders })
    }

    const teamId   = Deno.env.get('APNS_TEAM_ID')!
    const keyId    = Deno.env.get('APNS_KEY_ID')!
    const pem      = Deno.env.get('APNS_PRIVATE_KEY')!
    const bundleId = 'com.vijaygoyal.xbill'
    const apnsHost = isDevelopment
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com'
    const expiration = String(Math.floor(Date.now() / 1000) + 3600)

    const jwt = await getAPNsJWT(teamId, keyId, pem)

    // H-05: batch all badge counts in ONE query before the send loop to avoid
    // O(N) round-trips (one per device token).
    // H-08: use callerID (verified JWT identity) for sender exclusion,
    // not the body-supplied payerId which is untrusted.
    const recipientIDs = (tokenRows as { token: string; user_id: string }[])
      .map(r => r.user_id)
      .filter(id => id !== callerID)
    const badgeMap = await batchUnreadCounts(supabase, recipientIDs)

    let sent = 0
    for (const row of (tokenRows as { token: string; user_id: string }[])) {
      // Don't notify the person who added the expense (use verified callerID, not body payerId)
      if (row.user_id === callerID) continue

      try {
        const badge = badgeMap.get(row.user_id) ?? 0
        const apnsPayload = {
          aps: {
            alert: {
              title: `${payerName} added an expense`,
              body:  `${expenseTitle} — ${formatCurrency(amount, currency)}`,
            },
            sound: 'default',
            badge,
          },
          groupId,
        }
        const res = await fetch(`${apnsHost}/3/device/${row.token}`, {
          method: 'POST',
          headers: {
            authorization:     `bearer ${jwt}`,
            'apns-topic':      bundleId,
            'apns-push-type':  'alert',
            'apns-expiration': expiration,
            'content-type':    'application/json',
          },
          body: JSON.stringify(apnsPayload),
        })

        if (res.ok) {
          sent++
        } else if (res.status === 410 || res.status === 400) {
          const body = await res.json().catch(() => ({}))
          if (body.reason === 'Unregistered' || body.reason === 'BadDeviceToken') {
            await supabase.from('device_tokens').delete().eq('token', row.token)
          }
        }
      } catch {
        // Network error — skip this token silently
      }
    }

    return new Response(
      JSON.stringify({ sent }),
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
// H-05: batch badge counts — one query for all recipients, aggregated in JS.
// Avoids O(N) round-trips (old code issued one query per device token).
// Badge = unsettled split count; fallback 0 (not 1) avoids phantom badges on error.
// ---------------------------------------------------------------------------

async function batchUnreadCounts(
  supabase: ReturnType<typeof createClient>,
  userIDs: string[]
): Promise<Map<string, number>> {
  const map = new Map<string, number>()
  if (!userIDs.length) return map
  const { data } = await supabase
    .from('splits')
    .select('user_id')
    .in('user_id', userIDs)
    .eq('is_settled', false)
  for (const row of (data ?? []) as { user_id: string }[]) {
    map.set(row.user_id, (map.get(row.user_id) ?? 0) + 1)
  }
  return map
}

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

function formatCurrency(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount)
  } catch {
    return `${currency} ${amount.toFixed(2)}`
  }
}
