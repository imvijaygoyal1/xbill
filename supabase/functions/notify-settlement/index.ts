import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import {
  isDeadToken, newReport, record, recipientsAllowing, sendToToken,
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
      settlementId,
    } = await req.json()

    if (!settlementId) {
      return new Response(JSON.stringify({ error: 'settlementId required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(
      SUPABASE_URL,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Under the settlements ledger either party may record a payment, so the caller is no
    // longer necessarily the payer. Resolve the event entirely from the trusted row — nothing
    // security-relevant comes from the request body — rather than trusting a body-supplied
    // sender the way the pre-ledger `is_settled` flow used to.
    const { data: settlement, error: settlementError } = await supabase
      .from('settlements')
      .select('id, group_id, from_user_id, to_user_id, amount, currency, recorded_by')
      .eq('id', settlementId)
      .single()

    if (settlementError || !settlement) {
      return new Response(JSON.stringify({ error: 'settlement not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Preserves H-09 and strengthens it: the caller must be the account that recorded this
    // payment, which the settlements table's own RLS also enforces on INSERT. Nothing here
    // trusts the request body for identity.
    if (settlement.recorded_by !== callerID) {
      return new Response(JSON.stringify({ error: 'forbidden' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const groupId    = settlement.group_id
    const fromUserID = settlement.from_user_id
    const toUserID   = settlement.to_user_id
    const amount     = settlement.amount
    const currency   = settlement.currency
    // Notify whichever party did not record it — the recorder already knows they acted.
    const recipientID = callerID === fromUserID ? toUserID : fromUserID

    // Fetch fromName from profiles using the row's from_user_id — never callerID, which may
    // now be the creditor recording a payment on the debtor's behalf.
    const { data: senderProfile, error: profileError } = await supabase
      .from('profiles')
      .select('display_name')
      .eq('id', fromUserID)
      .single()

    if (profileError || !senderProfile) {
      return new Response(JSON.stringify({ error: 'Could not resolve sender profile' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    const fromName: string = senderProfile.display_name ?? 'Someone'

    const { data: group, error: groupError } = await supabase
      .from('groups')
      .select('name')
      .eq('id', groupId)
      .single()
    if (groupError || !group) {
      return new Response(JSON.stringify({ error: 'Group not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // The recipient is either the payee (recipientID === toUserID, the common case where the
    // debtor recorded their own payment) or the payer (recipientID === fromUserID, when the
    // creditor recorded the payment on the debtor's behalf). Copy must not tell the debtor
    // "<their own name> paid you" — resolve the recorder's name for that branch instead.
    const recipientIsPayer = recipientID === fromUserID
    let recorderName = fromName
    if (recipientIsPayer) {
      const { data: recorderProfile } = await supabase
        .from('profiles')
        .select('display_name')
        .eq('id', toUserID)
        .maybeSingle()
      recorderName = recorderProfile?.display_name ?? 'Someone'
    }
    const alertTitle = recipientIsPayer ? `${recorderName} marked you as paid` : `${fromName} settled up`
    const alertBody  = recipientIsPayer
      ? `You paid ${formatCurrency(amount, currency)} in ${group.name}`
      : `Paid you ${formatCurrency(amount, currency)} in ${group.name}`

    const { error: notificationError } = await supabase.from('notifications').upsert({
      recipient_id: recipientID,
      dedupe_key: `settlement:${settlementId}:${recipientID}`,
      event_type: 'settlementMade',
      title: alertTitle,
      subtitle: `${group.name} · ${recipientIsPayer ? 'You paid' : 'Paid you'} ${formatCurrency(amount, currency)}`,
      amount,
      currency,
      category: 'other',
      group_id: groupId,
    }, { onConflict: 'dedupe_key', ignoreDuplicates: true })
    if (notificationError) throw notificationError

    // Push whichever party did not record the payment.
    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token, environment')
      .eq('user_id', recipientID)

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

    // Badge: count unread in-app notifications for the recipient.
    const { count: badgeCount } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('recipient_id', recipientID)
      .is('read_at', null)
    const badge = badgeCount ?? 0

    const apnsPayload = {
      aps: {
        alert: {
          title: alertTitle,
          body:  alertBody,
        },
        sound: 'default',
        badge,
      },
      groupId,
    }

    const report = newReport()

    // PUSH-01: the RECIPIENT decides whether they hear about this, not the sender. The in-app
    // `notifications` rows above are written regardless — muting a push means "do not interrupt
    // me", not "hide this from my history", and a row never written cannot be caught up on.
    const preference = await recipientsAllowing(supabase, [recipientID], 'settlements')
    if (preference.lookupFailed) report.preferenceLookupFailed = true
    if (!preference.allowed.has(recipientID)) {
      report.muted = 1
      return new Response(
        JSON.stringify(report),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    for (const row of (tokenRows as DeviceTokenRow[])) {
      try {
        // PUSH-02: the host comes from THIS token's environment, not from the sender's build.
        const reason = await sendToToken({ row, jwt, bundleId, expiration, payload: apnsPayload })
        record(report, reason)

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

function formatCurrency(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount)
  } catch {
    return `${currency} ${amount.toFixed(2)}`
  }
}
