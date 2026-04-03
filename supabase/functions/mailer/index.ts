import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  action?: "send_custom";
  to?: string | string[];
  subject?: string;
  html?: string;
  text?: string;
  template_key?: string;
  payload?: Record<string, unknown>;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const ownerEmail = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();

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

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !resendApiKey || !resendFromEmail) {
    return jsonError("Missing environment variables.", 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return jsonError("Missing Authorization bearer token.", 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
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
  const callerRole = readRole(caller.app_metadata, caller.user_metadata, callerEmail, ownerEmail);
  if (callerRole !== "super_admin" && callerRole !== "admin") {
    return jsonError("Only admin/super-admin can send system emails.", 403);
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return jsonError("Invalid request body.", 400);
  }

  if (body.action !== "send_custom") {
    return jsonError("Unsupported action.", 400);
  }

  const recipients = normalizeRecipients(body.to);
  if (recipients.length === 0) {
    return jsonError("Missing recipient email.", 400);
  }

  const subject = (body.subject ?? "").trim();
  if (!subject) {
    return jsonError("Missing subject.", 400);
  }

  const html = body.html?.trim();
  const text = body.text?.trim();
  if (!html && !text) {
    return jsonError("Provide html or text body.", 400);
  }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: resendFromEmail,
      to: recipients,
      subject,
      ...(html ? { html } : {}),
      ...(text ? { text } : {}),
    }),
  });

  const resendData = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    await insertOutboundLog(adminClient, {
      actor_user_id: caller.id,
      actor_email: callerEmail,
      to_email: recipients.join(","),
      subject,
      template_key: body.template_key ?? null,
      status: "failed",
      payload: body.payload ?? {},
      error_text: JSON.stringify(resendData),
    });
    return jsonError("Resend delivery failed.", 502, resendData);
  }

  await insertOutboundLog(adminClient, {
    actor_user_id: caller.id,
    actor_email: callerEmail,
    to_email: recipients.join(","),
    subject,
    template_key: body.template_key ?? null,
    provider_message_id: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: "sent",
    payload: body.payload ?? {},
  });

  return jsonResponse({ ok: true, provider: "resend", data: resendData });
});

async function insertOutboundLog(
  adminClient: ReturnType<typeof createClient>,
  row: {
    actor_user_id: string;
    actor_email: string;
    to_email: string;
    subject: string;
    template_key: string | null;
    provider_message_id?: string;
    status: "sent" | "failed" | "queued";
    payload: Record<string, unknown>;
    error_text?: string;
  },
) {
  await adminClient.from("outbound_email_log").insert({
    actor_user_id: row.actor_user_id,
    actor_email: row.actor_email,
    to_email: row.to_email,
    subject: row.subject,
    template_key: row.template_key,
    provider_message_id: row.provider_message_id,
    status: row.status,
    payload: row.payload,
    error_text: row.error_text,
  });
}

function normalizeRecipients(to: string | string[] | undefined): string[] {
  if (!to) return [];

  const list = Array.isArray(to) ? to : [to];
  return list
    .map((value) => value.trim().toLowerCase())
    .filter((value) => value.includes("@"));
}

type Role = "super_admin" | "admin" | "staff";

function readRole(
  appMetadata: Record<string, unknown> | undefined,
  userMetadata: Record<string, unknown> | undefined,
  email: string,
  owner: string,
): Role {
  if (email === owner) return "super_admin";

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
