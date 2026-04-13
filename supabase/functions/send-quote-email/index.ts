import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  quote_id?: string;
  to_email?: string;
  note?: string;
};

type Role = "super_admin" | "admin" | "staff";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const ownerEmail = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
  if (!isRoleAllowed(callerRole)) {
    return jsonError("User role not allowed to send quote emails.", 403);
  }

  let body: RequestBody = {};
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    body = {};
  }

  const quoteId = (body.quote_id ?? "").trim();
  const toEmail = (body.to_email ?? "").trim().toLowerCase();
  const note = (body.note ?? "").trim();

  if (!quoteId) {
    return jsonError("Missing quote_id.", 400);
  }
  if (!toEmail.includes("@") || !toEmail.includes(".")) {
    return jsonError("Invalid destination email.", 400);
  }

  const { data: quoteRow, error: quoteError } = await adminClient
    .from("quotes")
    .select(
      "id,quote_number,status,subtotal,tax,total,projects:projects(name,code,clients:clients(contact_name,business_name,email))",
    )
    .eq("id", quoteId)
    .single();

  if (quoteError || !quoteRow) {
    return jsonError("Quote not found.", 404);
  }

  const project = (quoteRow.projects as Record<string, unknown> | null) ?? {};
  const client = (project.clients as Record<string, unknown> | null) ?? {};
  const quoteNumber = `${quoteRow.quote_number ?? ""}`.trim();
  const status = `${quoteRow.status ?? ""}`.trim();
  const subtotal = Number(quoteRow.subtotal ?? 0);
  const tax = Number(quoteRow.tax ?? 0);
  const total = Number(quoteRow.total ?? 0);
  const projectName = `${project.name ?? ""}`.trim();
  const projectCode = `${project.code ?? ""}`.trim();
  const contactName = `${client.contact_name ?? ""}`.trim();
  const businessName = `${client.business_name ?? ""}`.trim();
  const recipientName = contactName || businessName || "Cliente";

  const subject = `Cotizacion ${quoteNumber || quoteId} | ${projectName || "Proyecto"}`;
  const html = buildQuoteEmailHtml({
    recipientName,
    quoteNumber,
    projectName,
    projectCode,
    status,
    subtotal,
    tax,
    total,
    note,
  });
  const text = buildQuoteEmailText({
    recipientName,
    quoteNumber,
    projectName,
    projectCode,
    status,
    subtotal,
    tax,
    total,
    note,
  });

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: resendFromEmail,
      to: [toEmail],
      subject,
      html,
      text,
    }),
  });

  const resendData = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    await insertOutboundLog(adminClient, {
      actor_user_id: caller.id,
      actor_email: callerEmail,
      to_email: toEmail,
      subject,
      template_key: "quote_delivery",
      status: "failed",
      payload: {
        quote_id: quoteId,
        quote_number: quoteNumber,
        project_name: projectName,
      },
      error_text: JSON.stringify(resendData),
    });
    return jsonError("Resend delivery failed.", 502, resendData);
  }

  await insertOutboundLog(adminClient, {
    actor_user_id: caller.id,
    actor_email: callerEmail,
    to_email: toEmail,
    subject,
    template_key: "quote_delivery",
    provider_message_id: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: "sent",
    payload: {
      quote_id: quoteId,
      quote_number: quoteNumber,
      project_name: projectName,
      project_code: projectCode,
      status,
      total,
      note,
    },
  });

  return jsonResponse({ ok: true, quote_id: quoteId, to_email: toEmail });
});

function isRoleAllowed(role: Role) {
  return role === "super_admin" || role === "admin" || role === "staff";
}

function readRole(
  appMetadata: Record<string, unknown> | null | undefined,
  userMetadata: Record<string, unknown> | null | undefined,
  email: string,
  owner: string,
): Role {
  if (email === owner) {
    return "super_admin";
  }

  const direct = normalizeRole(appMetadata?.role ?? userMetadata?.role);
  if (direct != null) {
    return direct;
  }

  const appRoles = asStringArray(appMetadata?.roles);
  for (const role of appRoles) {
    const parsed = normalizeRole(role);
    if (parsed != null) return parsed;
  }

  const userRoles = asStringArray(userMetadata?.roles);
  for (const role of userRoles) {
    const parsed = normalizeRole(role);
    if (parsed != null) return parsed;
  }

  return "staff";
}

function normalizeRole(value: unknown): Role | null {
  const role = `${value ?? ""}`.trim().toLowerCase();
  if (role === "owner" || role === "super_admin" || role === "superadmin") {
    return "super_admin";
  }
  if (role === "admin" || role === "administrator") {
    return "admin";
  }
  if (role === "staff" || role === "user") {
    return "staff";
  }
  return null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => `${item ?? ""}`).filter((item) => item.trim().length > 0);
}

function buildQuoteEmailHtml(params: {
  recipientName: string;
  quoteNumber: string;
  projectName: string;
  projectCode: string;
  status: string;
  subtotal: number;
  tax: number;
  total: number;
  note: string;
}) {
  return `
    <div style="font-family:Arial,sans-serif;max-width:760px;margin:0 auto;color:#1f1f1f;">
      <h2 style="margin:0 0 8px;">Cotizacion ${escapeHtml(params.quoteNumber)}</h2>
      <p style="margin:0 0 16px;">Hola ${escapeHtml(params.recipientName)}, te compartimos el resumen de tu cotizacion.</p>

      <table style="width:100%;border-collapse:collapse;margin-bottom:18px;">
        <tr><td style="padding:8px;border:1px solid #ddd;"><strong>Proyecto</strong></td><td style="padding:8px;border:1px solid #ddd;">${escapeHtml(params.projectCode)} ${escapeHtml(params.projectName)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #ddd;"><strong>Estatus</strong></td><td style="padding:8px;border:1px solid #ddd;">${escapeHtml(params.status)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #ddd;"><strong>Subtotal</strong></td><td style="padding:8px;border:1px solid #ddd;">$${params.subtotal.toFixed(2)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #ddd;"><strong>IVA</strong></td><td style="padding:8px;border:1px solid #ddd;">$${params.tax.toFixed(2)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #ddd;"><strong>Total</strong></td><td style="padding:8px;border:1px solid #ddd;"><strong>$${params.total.toFixed(2)}</strong></td></tr>
      </table>

      ${
        params.note.length > 0
          ? `<p style="margin:0 0 12px;"><strong>Mensaje:</strong> ${escapeHtml(params.note)}</p>`
          : ""
      }

      <p style="margin:16px 0 0;color:#555;">REMA Arquitectura</p>
    </div>
  `;
}

function buildQuoteEmailText(params: {
  recipientName: string;
  quoteNumber: string;
  projectName: string;
  projectCode: string;
  status: string;
  subtotal: number;
  tax: number;
  total: number;
  note: string;
}) {
  const lines = [
    `Hola ${params.recipientName},`,
    "",
    `Te compartimos el resumen de tu cotizacion ${params.quoteNumber}.`,
    `Proyecto: ${params.projectCode} ${params.projectName}`.trim(),
    `Estatus: ${params.status}`,
    `Subtotal: $${params.subtotal.toFixed(2)}`,
    `IVA: $${params.tax.toFixed(2)}`,
    `Total: $${params.total.toFixed(2)}`,
  ];

  if (params.note.length > 0) {
    lines.push("", `Mensaje: ${params.note}`);
  }

  lines.push("", "REMA Arquitectura");
  return lines.join("\n");
}

async function insertOutboundLog(
  adminClient: ReturnType<typeof createClient>,
  payload: {
    actor_user_id?: string;
    actor_email?: string;
    to_email: string;
    subject: string;
    template_key?: string;
    provider_message_id?: string;
    status: "sent" | "failed";
    payload?: Record<string, unknown>;
    error_text?: string;
  },
) {
  await adminClient.from("outbound_email_log").insert({
    actor_user_id: payload.actor_user_id,
    actor_email: payload.actor_email,
    to_email: payload.to_email,
    subject: payload.subject,
    template_key: payload.template_key,
    provider: "resend",
    provider_message_id: payload.provider_message_id,
    status: payload.status,
    payload: payload.payload ?? {},
    error_text: payload.error_text,
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function jsonError(message: string, status = 400, details?: unknown) {
  return jsonResponse(
    {
      error: message,
      details,
    },
    status,
  );
}
