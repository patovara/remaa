import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const inboundSecret = Deno.env.get("EMAIL_WEBHOOK_SECRET") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-email-webhook-secret",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed.", 405);
  }

  if (!supabaseUrl || !serviceRoleKey || !inboundSecret) {
    return jsonError("Missing environment variables.", 500);
  }

  const providedSecret = extractInboundSecret(req);
  if (!constantTimeEquals(providedSecret, inboundSecret)) {
    return jsonError("Invalid webhook secret.", 401);
  }

  const rawBody = await req.text();
  if (!rawBody || rawBody.trim().length === 0) {
    return jsonError("Empty payload.", 400);
  }

  const payload = safeParseJson(rawBody);
  if (!payload || typeof payload !== "object") {
    return jsonError("Invalid JSON payload.", 400);
  }

  const normalized = normalizeInboundPayload(payload as Record<string, unknown>);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error } = await adminClient.from("inbound_email_events").insert({
    provider: "resend",
    message_id: normalized.messageId,
    from_email: normalized.from,
    to_email: normalized.to,
    subject: normalized.subject,
    text_body: normalized.textBody,
    html_body: normalized.htmlBody,
    raw_payload: payload,
  });

  if (error) {
    return jsonError(error.message, 500);
  }

  return jsonResponse({ ok: true });
});

function normalizeInboundPayload(payload: Record<string, unknown>) {
  const data = asRecord(payload.data);
  const from = coalesceString(data?.from, data?.from_email, payload.from, payload.from_email);
  const to = coalesceString(data?.to, data?.to_email, payload.to, payload.to_email);
  const subject = coalesceString(data?.subject, payload.subject);
  const textBody = coalesceString(data?.text, data?.text_body, payload.text, payload.text_body);
  const htmlBody = coalesceString(data?.html, data?.html_body, payload.html, payload.html_body);
  const messageId = coalesceString(data?.id, data?.message_id, payload.id, payload.message_id);

  return { from, to, subject, textBody, htmlBody, messageId };
}

function safeParseJson(raw: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

function extractInboundSecret(req: Request): string {
  const headerSecret = req.headers.get("x-email-webhook-secret")?.trim() ?? "";
  if (headerSecret) return headerSecret;

  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) return "";

  return authorization.slice("Bearer ".length).trim();
}

function constantTimeEquals(a: string, b: string): boolean {
  if (!a || !b) return false;

  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  if (aBytes.length !== bBytes.length) return false;

  let diff = 0;
  for (let i = 0; i < aBytes.length; i += 1) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function coalesceString(...values: unknown[]): string | null {
  for (const value of values) {
    const parsed = toStringOrNull(value);
    if (parsed) return parsed;
  }
  return null;
}

function toStringOrNull(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  if (Array.isArray(value)) {
    const flattened = value
      .map((item) => (typeof item === "string" ? item.trim() : ""))
      .filter((item) => item.length > 0);
    if (flattened.length > 0) return flattened.join(",");
  }

  return null;
}

function jsonResponse(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status: number) {
  return jsonResponse({ ok: false, error: message }, status);
}
