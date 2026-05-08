import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!

const corsHeaders = {
  'Access-Control-Allow-Origin': SUPABASE_URL,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  // L-22: handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // 1. Extract JWT from Authorization header
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return new Response(
      JSON.stringify({ error: 'Missing or invalid authorization header' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const jwt = authHeader.replace('Bearer ', '')

  // Use the service role client for JWT verification.
  // The anon client only supports HS256 and rejects Apple Sign-In tokens (ES256).
  const adminClient = createClient(
    SUPABASE_URL,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt)
  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: 'Could not verify user identity' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // 2. Delete device tokens — non-fatal
  const { error: tokenError } = await adminClient
    .from('device_tokens')
    .delete()
    .eq('user_id', user.id)
  if (tokenError) console.error('device_tokens delete:', tokenError.message)

  // 3. Delete profile row — non-fatal
  const { error: profileError } = await adminClient
    .from('profiles')
    .delete()
    .eq('id', user.id)
  if (profileError) console.error('profile delete:', profileError.message)

  // 4. Delete auth user — always last; fatal if this fails
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id)
  if (deleteError) {
    return new Response(
      JSON.stringify({ error: deleteError.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ success: true }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
})
