import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("INVITE_FROM_EMAIL") ?? "noreply@yourdomain.com";

// H4 + M4: restrict CORS to project origin
const corsHeaders = {
  "Access-Control-Allow-Origin": SUPABASE_URL,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

interface InviteRequest {
  groupName: string;
  groupEmoji: string;
  inviterName: string;
  emails: string[];
}

// H4: verify the caller is an authenticated Supabase user
async function requireAuth(req: Request): Promise<boolean> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return false
  const jwt = authHeader.replace('Bearer ', '')
  const adminClient = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const { data: { user }, error } = await adminClient.auth.getUser(jwt)
  return !error && !!user
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // H4: reject unauthenticated callers
  if (!(await requireAuth(req))) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const { groupName, groupEmoji, inviterName, emails }: InviteRequest = await req.json();

    if (!emails?.length || !groupName || !inviterName) {
      return json({ error: "Missing required fields" }, 400);
    }

    const results = await Promise.allSettled(
      emails.map((email) =>
        sendInvite({ email, groupName, groupEmoji, inviterName })
      )
    );

    const failed = results
      .map((r, i) => ({ email: emails[i], result: r }))
      .filter((x) => x.result.status === "rejected")
      .map((x) => x.email);

    return json({ sent: emails.length - failed.length, failed });
  } catch (err) {
    console.error(err);
    return json({ error: "Internal server error" }, 500);
  }
});

async function sendInvite({
  email,
  groupName,
  groupEmoji,
  inviterName,
}: {
  email: string;
  groupName: string;
  groupEmoji: string;
  inviterName: string;
}) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [email],
      subject: `${inviterName} invited you to ${groupEmoji} ${groupName} on xBill`,
      html: `
        <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
          <h2 style="margin-bottom: 8px;">${groupEmoji} You're invited!</h2>
          <p style="color: #555; margin-top: 0;">
            <strong>${inviterName}</strong> has invited you to join
            <strong>${groupName}</strong> on <strong>xBill</strong> — the easiest way to split expenses with friends.
          </p>
          <p style="margin-top: 24px; color: #888; font-size: 13px;">
            Download xBill and sign in with this email address to join the group automatically.
          </p>
        </div>
      `,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend error ${res.status}: ${body}`);
  }
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}
