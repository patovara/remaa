import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Role = "super_admin" | "admin" | "staff";

type SendEmailBody = {
  to?: string | string[];
  subject?: string;
  html?: string;
  text?: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const OWNER_EMAIL = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();

const MAX_RECIPIENTS = 10;
const MAX_SUBJECT_LENGTH = 180;
const MAX_BODY_LENGTH = 100_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed.", 405);
  }

  if (
    !SUPABASE_URL ||
    !SUPABASE_ANON_KEY ||
    !SUPABASE_SERVICE_ROLE_KEY ||
    !RESEND_API_KEY ||
    !RESEND_FROM_EMAIL
  ) {
    return jsonError("Missing environment variables.", 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return jsonError("Missing Authorization bearer token.", 401);
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user: caller },
    error: callerError,
  } = await userClient.auth.getUser();

  if (callerError || !caller) {
    return jsonError("Unauthorized user.", 401);
  }

  const callerEmail = (caller.email ?? "").trim().toLowerCase();
  const callerRole = readRole(caller.app_metadata, caller.user_metadata, callerEmail, OWNER_EMAIL);
  if (callerRole !== "super_admin" && callerRole !== "admin") {
    return jsonError("Only admin/super-admin can send system emails.", 403);
  }

  let body: SendEmailBody;
  try {
    body = (await req.json()) as SendEmailBody;
  } catch {
    return jsonError("Invalid JSON body.", 400);
  }

  const recipients = normalizeRecipients(body.to);
  if (recipients.length === 0) {
    return jsonError("Missing recipient email.", 400);
  }
  if (recipients.length > MAX_RECIPIENTS) {
    return jsonError(`Too many recipients. Max allowed: ${MAX_RECIPIENTS}.`, 400);
  }

  const subject = (body.subject ?? "").trim();
  if (!subject) {
    return jsonError("Missing subject.", 400);
  }
  if (subject.length > MAX_SUBJECT_LENGTH) {
    return jsonError(`Subject too long. Max allowed: ${MAX_SUBJECT_LENGTH}.`, 400);
  }

  const html = body.html?.trim();
  const text = body.text?.trim();
  if (!html && !text) {
    return jsonError("Provide html or text body.", 400);
  }

  if ((html?.length ?? 0) > MAX_BODY_LENGTH || (text?.length ?? 0) > MAX_BODY_LENGTH) {
    return jsonError(`Email body too large. Max allowed: ${MAX_BODY_LENGTH} chars.`, 400);
  }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: RESEND_FROM_EMAIL,
      to: recipients,
      subject,
      ...(html ? { html } : {}),
      ...(text ? { text } : {}),
    }),
  });

  const resendData = await resendResponse.json().catch(() => ({}));

  await adminClient.from("outbound_email_log").insert({
    actor_user_id: caller.id,
    actor_email: callerEmail,
    to_email: recipients.join(","),
    subject,
    template_key: "mailer_safe",
    provider: "resend",
    provider_message_id: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: resendResponse.ok ? "sent" : "failed",
    payload: {
      recipients_count: recipients.length,
      has_html: Boolean(html),
      has_text: Boolean(text),
    },
    error_text: resendResponse.ok ? null : JSON.stringify(resendData),
  });

  if (!resendResponse.ok) {
    return jsonError("Resend delivery failed.", 502, resendData);
  }

  return jsonResponse({ ok: true, provider: "resend", data: resendData });
});

function normalizeRecipients(to: string | string[] | undefined): string[] {
  if (!to) return [];

  const list = Array.isArray(to) ? to : [to];
  return list
    .map((value) => value.trim().toLowerCase())
    .filter((value) => value.includes("@"))
    .slice(0, MAX_RECIPIENTS);
}

function readRole(
  appMetadata: Record<string, unknown> | undefined,
  userMetadata: Record<string, unknown> | undefined,
  email: string,
  ownerEmail: string,
): Role {
  if (email === ownerEmail) return "super_admin";

  const appRole = parseRole(appMetadata?.role);
  if (appRole) return appRole;

  const userRole = parseRole(userMetadata?.role);
  if (userRole) return userRole;

  return "staff";
}

function parseRole(raw: unknown): Role | null {
  const value = `${raw ?? ""}`.trim().toLowerCase();
  if (value === "super_admin" || value === "superadmin" || value === "owner") return "super_admin";
  if (value === "admin" || value === "administrator") return "admin";
  if (value === "staff" || value === "user") return "staff";
  return null;
}

function jsonResponse(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status: number, details?: unknown) {
  return jsonResponse(
    {
      ok: false,
      error: message,
      ...(details ? { details } : {}),
    },
    status,
  );
}
