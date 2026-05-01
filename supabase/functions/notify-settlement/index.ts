import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      settlementId,
      groupId,
      groupName,
      fromUserID,
      fromName,
      toUserID,
      amount,
      currency,
    } = await req.json()

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Push only the creditor (toUserID) — they are being paid
    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', toUserID)

    if (!tokenRows?.length) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: corsHeaders })
    }

    const teamId   = Deno.env.get('APNS_TEAM_ID')!
    const keyId    = Deno.env.get('APNS_KEY_ID')!
    const pem      = Deno.env.get('APNS_PRIVATE_KEY')!
    const bundleId = 'com.vijaygoyal.xbill'

    const jwt = await generateAPNsJWT(teamId, keyId, pem)

    // Badge: count unsettled splits for the creditor
    const { count: badgeCount } = await supabase
      .from('splits')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', toUserID)
      .eq('is_settled', false)
    const badge = badgeCount ?? 1

    const payload = {
      aps: {
        alert: {
          title: `${fromName} settled up`,
          body:  `Paid you ${formatCurrency(amount, currency)} in ${groupName}`,
        },
        sound: 'default',
        badge,
      },
      settlementId,
      groupId,
    }

    let sent = 0
    for (const row of (tokenRows as { token: string }[])) {
      try {
        const res = await fetch(`https://api.push.apple.com/3/device/${row.token}`, {
          method: 'POST',
          headers: {
            authorization:    `bearer ${jwt}`,
            'apns-topic':     bundleId,
            'apns-push-type': 'alert',
            'content-type':   'application/json',
          },
          body: JSON.stringify(payload),
        })
        if (res.ok) sent++
      } catch {
        // Skip failed tokens silently
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

  const encoder  = new TextEncoder()
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
