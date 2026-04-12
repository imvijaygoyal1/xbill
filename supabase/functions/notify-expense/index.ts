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
    const { expenseId, groupId, payerName, expenseTitle, amount, currency } = await req.json()

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

    // Fetch device tokens (all members — APNs deduplicates if same device)
    const { data: profiles } = await supabase
      .from('profiles')
      .select('device_token')
      .in('id', memberIDs)
      .not('device_token', 'is', null)

    const tokens: string[] = (profiles ?? [])
      .map((p: { device_token: string | null }) => p.device_token)
      .filter(Boolean)

    if (!tokens.length) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: corsHeaders })
    }

    const teamId  = Deno.env.get('APNS_TEAM_ID')!
    const keyId   = Deno.env.get('APNS_KEY_ID')!
    const pem     = Deno.env.get('APNS_PRIVATE_KEY')!
    const bundleId = 'com.vijaygoyal.xbill'

    const jwt = await generateAPNsJWT(teamId, keyId, pem)

    const payload = {
      aps: {
        alert: {
          title: `${payerName} added an expense`,
          body:  `${expenseTitle} — ${formatCurrency(amount, currency)}`,
        },
        sound: 'default',
        badge: 1,
      },
      expenseId,
      groupId,
    }

    let sent = 0
    for (const token of tokens) {
      try {
        const res = await fetch(`https://api.push.apple.com/3/device/${token}`, {
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

  // Strip PEM headers and decode
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
