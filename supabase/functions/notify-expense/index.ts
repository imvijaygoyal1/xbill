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
      expenseId,
    } = await req.json()

    const supabase = createClient(
      SUPABASE_URL,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    if (!expenseId) throw new Error('expenseId is required')

    // Resolve the event from trusted rows. The caller may only notify for an
    // expense in a group they belong to; display and money fields must not be
    // accepted from the client because this function uses the service role.
    const { data: expense, error: expenseError } = await supabase
      .from('expenses')
      .select('id, group_id, paid_by, title, amount, currency')
      .eq('id', expenseId)
      .single()
    if (expenseError || !expense) throw new Error('Expense not found')

    const { data: callerMembership } = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', expense.group_id)
      .eq('user_id', callerID)
      .maybeSingle()
    if (!callerMembership) {
      return new Response(JSON.stringify({ error: 'Caller is not a group member' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: group, error: groupError } = await supabase
      .from('groups')
      .select('name')
      .eq('id', expense.group_id)
      .single()
    if (groupError || !group) throw new Error('Group not found')

    const { data: payer } = expense.paid_by
      ? await supabase.from('profiles').select('display_name').eq('id', expense.paid_by).maybeSingle()
      : { data: null }
    const payerName = payer?.display_name ?? 'Someone'
    const groupId = expense.group_id
    const groupName = group.name
    const expenseTitle = expense.title
    const amount = expense.amount
    const currency = expense.currency

    // Fetch all group members
    const { data: members, error: membersError } = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', groupId)

    if (membersError || !members?.length) {
      return new Response(JSON.stringify({ sent: 0, failed: 0, reasons: {} }), { headers: corsHeaders })
    }

    const memberIDs = members.map((m: { user_id: string }) => m.user_id)

    const recipientIDsForNotification = memberIDs.filter(id => id !== callerID)
    const { error: notificationError } = await supabase.from('notifications').upsert(
      recipientIDsForNotification.map(recipient_id => ({
        recipient_id,
        dedupe_key: `expense:${expenseId}:${recipient_id}`,
        event_type: 'expenseAdded',
        title: `${payerName} added an expense`,
        subtitle: `${groupName} · ${expenseTitle}`,
        amount,
        currency,
        category: 'other',
        group_id: groupId,
        expense_id: expenseId,
      })),
      { onConflict: 'dedupe_key', ignoreDuplicates: true },
    )
    if (notificationError) throw notificationError

    // Fetch device tokens — user_id retained for sender exclusion and badge
    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token, user_id, environment')
      .in('user_id', memberIDs)

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

    // Badge is the unread in-app notification count, not the unsettled split count.
    // H-08: use callerID (verified JWT identity) for sender exclusion,
    // not the body-supplied payerId which is untrusted.
    const recipientIDs = (tokenRows as DeviceTokenRow[])
      .map(r => r.user_id)
      .filter(id => id !== callerID)
    const badgeMap = await batchUnreadCounts(supabase, recipientIDs)

    const report = newReport()

    // PUSH-01: the RECIPIENT decides whether they hear about this, not the sender. The in-app
    // `notifications` rows above are written regardless — muting a push means "do not interrupt
    // me", not "hide this from my history", and a row never written cannot be caught up on.
    const preference = await recipientsAllowing(supabase, recipientIDs, 'expenses')
    if (preference.lookupFailed) report.preferenceLookupFailed = true
    // Counted once per PERSON, not per token — a user may now have several devices (PUSH-03),
    // and "3 muted" meaning "one person with three phones" would be a misleading number.
    report.muted = new Set(recipientIDs).size - preference.allowed.size

    for (const row of (tokenRows as DeviceTokenRow[])) {
      // Don't notify the person who added the expense (use verified callerID, not body payerId)
      if (row.user_id === callerID) continue

      if (!preference.allowed.has(row.user_id)) continue

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
// Batch badge counts — one query for all recipients, aggregated in JS.
// ---------------------------------------------------------------------------

async function batchUnreadCounts(
  supabase: ReturnType<typeof createClient>,
  userIDs: string[]
): Promise<Map<string, number>> {
  const map = new Map<string, number>()
  if (!userIDs.length) return map
  const { data } = await supabase
    .from('notifications')
    .select('recipient_id')
    .in('recipient_id', userIDs)
    .is('read_at', null)
  for (const row of (data ?? []) as { recipient_id: string }[]) {
    map.set(row.recipient_id, (map.get(row.recipient_id) ?? 0) + 1)
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
