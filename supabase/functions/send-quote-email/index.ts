import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { FIRMAMVAZQUEZ_PNG_BASE64 } from "./firma_base64.ts";

type RequestBody = {
  quote_id?: string;
  to_email?: string;
  note?: string;
};

type ResendAttachment = {
  filename: string;
  content: string;
  content_type: string;
  content_id?: string;
  inline?: boolean;
  cid?: string;
  disposition?: string;
};

type Role = "super_admin" | "admin" | "staff";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const appPublicUrl = (Deno.env.get("APP_PUBLIC_URL") ?? "").replace(/\/$/, "");
const ownerEmail = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();

const SYSTEM_FROM_EMAIL = "system@noreply.gruporemaa.com";
const REPLY_TO = "cotizaciones@gruporemaa.com";
const INTERNAL_CC = "mvazquez@gruporemaa.com";

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

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !resendApiKey) {
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
  const toEmailRaw = (body.to_email ?? "").trim();
  const note = (body.note ?? "").trim();

  if (!quoteId) {
    return jsonError("Missing quote_id.", 400);
  }

  // Parse comma-separated recipient emails
  const toEmails = toEmailRaw
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e.length > 0);

  if (toEmails.length === 0 || toEmails.some((e) => !isValidEmail(e))) {
    return jsonError("One or more destination emails are invalid.", 400);
  }

  // Internal CC unless already listed in to
  const ccEmails = [INTERNAL_CC].filter((cc) => !toEmails.includes(cc));

  const { data: quoteRow, error: quoteError } = await adminClient
    .from("quotes")
    .select(
      "id,quote_number,approval_pdf_path,projects:projects(name,code,clients:clients(contact_name,business_name,email))",
    )
    .eq("id", quoteId)
    .single();

  if (quoteError || !quoteRow) {
    return jsonError("Quote not found.", 404);
  }

  const project = (quoteRow.projects as Record<string, unknown> | null) ?? {};
  const client = (project.clients as Record<string, unknown> | null) ?? {};
  const quoteNumber = `${quoteRow.quote_number ?? ""}`.trim();
  const projectName = `${project.name ?? ""}`.trim();
  const projectCode = `${project.code ?? ""}`.trim();
  const contactName = `${client.contact_name ?? ""}`.trim();
  const businessName = `${client.business_name ?? ""}`.trim();
  const recipientName = contactName || businessName || "Cliente";
  const pdfPath = `${quoteRow.approval_pdf_path ?? ""}`.trim();
  const allRecipients = [...toEmails, ...ccEmails].join(",");

  const subject = `Cotizacion REMA | ${projectName || "Proyecto"}`;

  // Download approval PDF from storage and attach it if it exists
  let pdfAttachment: ResendAttachment | null = null;
  if (pdfPath) {
    try {
      const { data: pdfBlob, error: pdfDownloadError } = await adminClient.storage
        .from("quote-approvals")
        .download(pdfPath);
      if (!pdfDownloadError && pdfBlob) {
        const pdfBuffer = await pdfBlob.arrayBuffer();
        const uint8 = new Uint8Array(pdfBuffer);
        let binary = "";
        for (let i = 0; i < uint8.length; i++) {
          binary += String.fromCharCode(uint8[i]);
        }
        const base64 = btoa(binary);
        const fileName = pdfPath.split("/").pop() ?? `cotizacion-${quoteNumber || quoteId}.pdf`;
        pdfAttachment = { filename: fileName, content: base64, content_type: "application/pdf" };
      }
    } catch {
      // Continue without attachment if download fails
    }
  }

  const footerImageAttachment: ResendAttachment = {
    filename: "firmamvazquez.png",
    content: FIRMAMVAZQUEZ_PNG_BASE64,
    content_type: "image/png",
    content_id: "footer-image",
    cid: "footer-image",
    inline: true,
    disposition: "inline",
  };
  const hasFooterImage = true;
  const html = buildQuoteEmailHtml({ recipientName, projectName, note, hasFooterImage });
  const text = buildQuoteEmailText({ recipientName, projectName, note });

  const attachments: ResendAttachment[] = [];
  attachments.push(footerImageAttachment);
  if (pdfAttachment) attachments.push(pdfAttachment);

  const resendBody: Record<string, unknown> = {
    from: SYSTEM_FROM_EMAIL,
    to: toEmails,
    cc: ccEmails.length > 0 ? ccEmails : undefined,
    reply_to: REPLY_TO,
    subject,
    html,
    text,
  };
  if (attachments.length > 0) resendBody.attachments = attachments;

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(resendBody),
  });

  const resendData = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    await insertOutboundLog(adminClient, {
      actor_user_id: caller.id,
      actor_email: callerEmail,
      to_email: allRecipients,
      subject,
      template_key: "quote_delivery",
      status: "failed",
      payload: { quote_id: quoteId, quote_number: quoteNumber, project_name: projectName },
      error_text: JSON.stringify(resendData),
    });
    return jsonError("Resend delivery failed.", 502, resendData);
  }

  await insertOutboundLog(adminClient, {
    actor_user_id: caller.id,
    actor_email: callerEmail,
    to_email: allRecipients,
    subject,
    template_key: "quote_delivery",
    provider_message_id: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: "sent",
    payload: {
      quote_id: quoteId,
      quote_number: quoteNumber,
      project_name: projectName,
      project_code: projectCode,
      had_pdf_attachment: pdfAttachment !== null,
      note,
    },
  });

  return jsonResponse({ ok: true, quote_id: quoteId, to_emails: toEmails, cc_emails: ccEmails });
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
  projectName: string;
  note: string;
  hasFooterImage: boolean;
}) {
  const projectLabel = escapeHtml(params.projectName || "Proyecto");

  return `
    <div style="font-family:Arial,Helvetica,sans-serif;max-width:600px;margin:0 auto;color:#1f1f1f;line-height:1.6;">
      <p style="margin:0 0 16px;">Buen d&iacute;a, un gusto saludarte!</p>

      <p style="margin:0 0 16px;">
        Te comparto la cotizaci&oacute;n: <strong>${projectLabel}</strong>
      </p>

      ${
        params.note.length > 0
          ? `<p style="margin:0 0 16px;">${escapeHtml(params.note)}</p>`
          : ""
      }

      <p style="margin:0 0 8px;">Quedo atento a tus comentarios</p>
      <p style="margin:0 0 24px;">&iexcl;Saludos!</p>

      ${
        params.hasFooterImage
          ? `<img src="cid:footer-image" alt="Imagen" style="max-width:280px;display:block;margin:20px 0 0;" />`
          : `<p style="margin:20px 0 0;font-weight:bold;color:#333;">Grupo REMA</p>`
      }

      <hr style="border:none;border-top:1px solid #e5e5e5;margin:16px 0;" />
      <p style="font-size:11px;color:#888;margin:0;line-height:1.5;">
        En caso de requerir factura por favor env&iacute;enos su informaci&oacute;n y datos de facturaci&oacute;n a
        <a href="mailto:facturas@remaa.mx" style="color:#888;">facturas@remaa.mx</a>
      </p>
    </div>
  `;
}

function buildQuoteEmailText(params: {
  recipientName: string;
  projectName: string;
  note: string;
}) {
  const projectLabel = params.projectName || "Proyecto";
  const lines = [
    "Buen dia, un gusto saludarte!",
    "",
    `Te comparto la cotizacion: ${projectLabel}`,
  ];
  if (params.note.length > 0) {
    lines.push("", params.note);
  }
  lines.push(
    "",
    "Quedo atento a tus comentarios",
    "",
    "iSaludos!",
    "",
    "---",
    "En caso de requerir factura envienos su informacion y datos de facturacion a facturas@remaa.mx",
  );
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

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
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
