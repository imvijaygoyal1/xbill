import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { user_id } = await req.json()

  if (!user_id) {
    return new Response(JSON.stringify({ error: 'user_id is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const { error } = await supabase.auth.admin.deleteUser(user_id)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
