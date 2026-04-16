import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req: Request) => {

  // Extract JWT from Authorization header
  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(
      JSON.stringify({ error: 'Missing or invalid authorization header' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } }
    )
  }

  const jwt = authHeader.replace('Bearer ', '')

  // Create a client with the ANON key to verify the JWT
  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } }
  )

  // Get the authenticated user from the verified JWT.
  // Never trust a user_id from the request body — always derive from the token.
  const { data: { user }, error: userError } = await supabaseClient.auth.getUser()

  if (userError || !user) {
    return new Response(
      JSON.stringify({ error: 'Could not verify user identity' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } }
    )
  }

  // Use the service role client for privileged deletion operations
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Delete profile row (cascades to splits, device_tokens via DB/RLS)
  const { error: profileError } = await supabaseAdmin
    .from('profiles')
    .delete()
    .eq('id', user.id)

  if (profileError) {
    return new Response(
      JSON.stringify({ error: profileError.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }

  // Delete the Auth user — only possible with service role key
  const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id)

  if (deleteError) {
    return new Response(
      JSON.stringify({ error: deleteError.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ success: true }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
})
