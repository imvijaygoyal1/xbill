import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ---------------------------------------------------------------------------
// APNs JWT cache — reuse for up to 55 minutes to avoid per-request P-256 ops
// ---------------------------------------------------------------------------

let cachedJWT: string | null = null
let jwtExpiresAt = 0

async function getAPNsJWT(teamId: string, keyId: string, pem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJWT && now < jwtExpiresAt) return cachedJWT
  cachedJWT = await generateAPNsJWT(teamId, keyId, pem)
  jwtExpiresAt = now + 55 * 60
  return cachedJWT
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
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
      Deno.env.get('SUPABASE_URL')!,
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

    let sent = 0
    for (const row of (tokenRows as { token: string; user_id: string }[])) {
      // Don't notify the person who added the expense
      if (row.user_id === payerId) continue

      try {
        const badge = await getUnreadCount(supabase, row.user_id)
        const apnsPayload = {
          aps: {
            alert: {
              title: `${payerName} added an expense`,
              body:  `${expenseTitle} — ${formatCurrency(amount, currency)}`,
            },
            sound: 'default',
            badge,
          },
          expenseId,
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
// Unread badge count — counts unsettled splits for a given user
// ---------------------------------------------------------------------------

async function getUnreadCount(supabase: ReturnType<typeof createClient>, userID: string): Promise<number> {
  const { count } = await supabase
    .from('splits')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userID)
    .eq('is_settled', false)
  return count ?? 1
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
