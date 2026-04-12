import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("INVITE_FROM_EMAIL") ?? "noreply@yourdomain.com";

interface InviteRequest {
  groupName: string;
  groupEmoji: string;
  inviterName: string;
  emails: string[];
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
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
      "Access-Control-Allow-Origin": "*",
    },
  });
}
