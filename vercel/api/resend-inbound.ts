import type { VercelRequest, VercelResponse } from "@vercel/node";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }

  const edgeUrl = process.env.SUPABASE_EMAIL_INBOUND_URL;
  const webhookSecret = process.env.EMAIL_WEBHOOK_SECRET;

  if (!edgeUrl || !webhookSecret) {
    return res.status(500).json({ ok: false, error: "Missing server env vars" });
  }

  // NOTE: Aqui puedes agregar validacion de firma de Resend cuando habilites svix.
  const response = await fetch(edgeUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-email-webhook-secret": webhookSecret,
    },
    body: JSON.stringify(req.body ?? {}),
  });

  const text = await response.text();
  if (!response.ok) {
    return res.status(502).json({ ok: false, error: "Supabase inbound failed", details: text });
  }

  return res.status(200).json({ ok: true });
}
