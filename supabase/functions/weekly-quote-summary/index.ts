import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Action = "send_weekly" | "resend_now";
type Role = "super_admin" | "admin" | "staff";

type RequestBody = {
  action?: Action;
};

type QuoteSummaryRow = {
  quoteNumber: string;
  status: "approved" | "acta_finalizada";
  total: number;
  createdAt: string;
  projectCode: string;
  projectName: string;
  clientName: string;
  approvedAt?: string;
  actaAt?: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const ownerEmail = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();
const schedulerSecret = (Deno.env.get("WEEKLY_SUMMARY_SCHEDULER_SECRET") ?? "").trim();

const summaryRecipients = [
  "mvazquez@gruporemaa.com",
  "mvazquez@remaa.mx",
  "facturas@remaa.mx",
];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-scheduler-secret",
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

  const schedulerHeader = (req.headers.get("x-scheduler-secret") ?? "").trim();
  const schedulerAuthorized =
    schedulerSecret.length > 0 && schedulerHeader.length > 0 && schedulerHeader === schedulerSecret;

  let body: RequestBody = {};
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    body = {};
  }

  const action: Action = body.action ?? (schedulerAuthorized ? "send_weekly" : "resend_now");

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let actorUserId = "system-scheduler";
  let actorEmail = "system-scheduler@gruporemaa.com";
  let trigger: "scheduled" | "manual" = "scheduled";

  if (schedulerAuthorized) {
    if (action !== "send_weekly") {
      return jsonError("Scheduled trigger only supports send_weekly action.", 400);
    }

    const enabled = await isWeeklySummaryEnabled(adminClient, ownerEmail);
    if (!enabled) {
      return jsonResponse({ ok: true, skipped: true, reason: "weekly_summary_disabled" });
    }
  } else {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) {
      return jsonError("Missing Authorization bearer token.", 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const {
      data: { user: caller },
      error: callerError,
    } = await userClient.auth.getUser();

    if (callerError || !caller) {
      return jsonError("Unauthorized user.", 401);
    }

    actorUserId = caller.id;
    actorEmail = (caller.email ?? "").trim().toLowerCase();
    trigger = "manual";

    const callerRole = readRole(caller.app_metadata, caller.user_metadata, actorEmail, ownerEmail);
    if (callerRole !== "admin" && callerRole !== "super_admin") {
      return jsonError("Only admin/super-admin can trigger this summary.", 403);
    }

    const enabledForCaller = caller.user_metadata?.pref_email_alerts === true;
    if (!enabledForCaller) {
      return jsonError("Activa el resumen semanal en Ajustes para poder reenviarlo.", 409);
    }
  }

  const rows = await fetchQuotesSummary(adminClient);
  const approvedRows = rows.filter((row) => row.status === "approved");
  const pendingPaymentRows = rows.filter((row) => row.status === "acta_finalizada");

  const html = buildSummaryHtml({
    approvedRows,
    pendingPaymentRows,
    generatedAt: new Date().toISOString(),
    trigger,
  });
  const text = buildSummaryText({
    approvedRows,
    pendingPaymentRows,
    generatedAt: new Date().toISOString(),
    trigger,
  });

  const subjectPrefix = trigger === "scheduled" ? "Resumen semanal" : "Reenvio manual";
  const subject = `${subjectPrefix} de cotizaciones | Aprobadas y Por cobrar`;

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: resendFromEmail,
      to: summaryRecipients,
      subject,
      html,
      text,
    }),
  });

  const resendData = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    await insertOutboundLog(adminClient, {
      actor_user_id: actorUserId,
      actor_email: actorEmail,
      to_email: summaryRecipients.join(","),
      subject,
      template_key: "weekly_quote_summary",
      status: "failed",
      payload: {
        action,
        trigger,
        approved_count: approvedRows.length,
        pending_payment_count: pendingPaymentRows.length,
      },
      error_text: JSON.stringify(resendData),
    });
    return jsonError("Resend delivery failed.", 502, resendData);
  }

  await insertOutboundLog(adminClient, {
    actor_user_id: actorUserId,
    actor_email: actorEmail,
    to_email: summaryRecipients.join(","),
    subject,
    template_key: "weekly_quote_summary",
    provider_message_id: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: "sent",
    payload: {
      action,
      trigger,
      approved_count: approvedRows.length,
      pending_payment_count: pendingPaymentRows.length,
    },
  });

  return jsonResponse({
    ok: true,
    trigger,
    recipients: summaryRecipients,
    approved_count: approvedRows.length,
    pending_payment_count: pendingPaymentRows.length,
  });
});

async function isWeeklySummaryEnabled(adminClient: ReturnType<typeof createClient>, owner: string) {
  const { data, error } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 200 });
  if (error || !data?.users) {
    return false;
  }

  for (const user of data.users) {
    const email = (user.email ?? "").trim().toLowerCase();
    const role = readRole(user.app_metadata, user.user_metadata, email, owner);
    const isActive = readIsActive(user.app_metadata, user.user_metadata);
    const enabled = user.user_metadata?.pref_email_alerts === true;
    if (isActive && enabled && (role === "admin" || role === "super_admin")) {
      return true;
    }
  }

  return false;
}

async function fetchQuotesSummary(adminClient: ReturnType<typeof createClient>): Promise<QuoteSummaryRow[]> {
  const projectJoin = "projects:projects(code,name,clients:clients(contact_name,business_name))";
  const baseSelect = `quote_number,status,total,created_at,${projectJoin}`;
  const orderOpts = { ascending: false };

  // Try with timestamp columns; fall back if migration hasn't been applied yet
  const { data: withDates, error: datesError } = await adminClient
    .from("quotes")
    .select(`${baseSelect},approved_at,acta_at`)
    .in("status", ["approved", "acta_finalizada"])
    .order("created_at", orderOpts)
    .limit(400);

  let rawRows: Record<string, unknown>[];
  if (datesError) {
    const { data: fallback, error: fallbackError } = await adminClient
      .from("quotes")
      .select(baseSelect)
      .in("status", ["approved", "acta_finalizada"])
      .order("created_at", orderOpts)
      .limit(400);
    if (fallbackError) {
      throw new Error(`Failed to fetch quote summary: ${fallbackError.message}`);
    }
    rawRows = (fallback ?? []) as Record<string, unknown>[];
  } else {
    rawRows = (withDates ?? []) as Record<string, unknown>[];
  }

  return rawRows.map((row) => {
    const project = (row.projects as Record<string, unknown> | null) ?? {};
    const client = (project.clients as Record<string, unknown> | null) ?? {};
    const contactName = `${client.contact_name ?? ""}`.trim();
    const businessName = `${client.business_name ?? ""}`.trim();
    return {
      quoteNumber: `${row.quote_number ?? ""}`.trim(),
      status: row.status === "approved" ? "approved" : "acta_finalizada",
      total: Number(row.total ?? 0),
      createdAt: `${row.created_at ?? ""}`.trim(),
      projectCode: `${project.code ?? ""}`.trim(),
      projectName: `${project.name ?? ""}`.trim(),
      clientName: contactName || businessName || "Sin cliente",
      approvedAt: row.approved_at ? `${row.approved_at}`.trim() : undefined,
      actaAt: row.acta_at ? `${row.acta_at}`.trim() : undefined,
    };
  });
}

function buildSummaryHtml(params: {
  approvedRows: QuoteSummaryRow[];
  pendingPaymentRows: QuoteSummaryRow[];
  generatedAt: string;
  trigger: "scheduled" | "manual";
}) {
  const approvedTotal = params.approvedRows.reduce((sum, row) => sum + row.total, 0);
  const pendingPaymentTotal = params.pendingPaymentRows.reduce((sum, row) => sum + row.total, 0);

  const renderRows = (rows: QuoteSummaryRow[], showActaAt: boolean) => {
    const colspan = showActaAt ? 6 : 5;
    if (rows.length === 0) {
      return `<tr><td colspan="${colspan}" style="padding:8px;border:1px solid #ddd;">Sin registros</td></tr>`;
    }

    return rows
      .map(
        (row) =>
          `<tr>
            <td style="padding:8px;border:1px solid #ddd;">${escapeHtml(row.quoteNumber)}</td>
            <td style="padding:8px;border:1px solid #ddd;">${escapeHtml(row.clientName)}</td>
            <td style="padding:8px;border:1px solid #ddd;">${escapeHtml([row.projectCode, row.projectName].filter((it) => it).join(" - "))}</td>
            <td style="padding:8px;border:1px solid #ddd;">${formatDate(row.approvedAt)}</td>
            ${showActaAt ? `<td style="padding:8px;border:1px solid #ddd;">${formatDate(row.actaAt)}</td>` : ""}
            <td style="padding:8px;border:1px solid #ddd;text-align:right;">$${row.total.toFixed(2)}</td>
          </tr>`,
      )
      .join("");
  };

  return `
    <div style="font-family:Arial,sans-serif;max-width:980px;margin:0 auto;color:#1f1f1f;">
      <h2 style="margin:0 0 8px;">Resumen de cotizaciones</h2>
      <p style="margin:0 0 16px;color:#555;">
        Tipo de envio: ${params.trigger === "scheduled" ? "Programado (lunes 8:00)" : "Reenvio manual"}<br/>
        Generado: ${escapeHtml(params.generatedAt)}
      </p>

      <div style="display:flex;gap:14px;flex-wrap:wrap;margin:0 0 20px;">
        <div style="padding:12px 14px;background:#f7f7f7;border-radius:8px;min-width:210px;">
          <strong>Aprobadas</strong><br/>
          ${params.approvedRows.length} cotizaciones<br/>
          Total: $${approvedTotal.toFixed(2)}
        </div>
        <div style="padding:12px 14px;background:#fff1cc;border-radius:8px;min-width:210px;">
          <strong>Por cobrar</strong><br/>
          ${params.pendingPaymentRows.length} cotizaciones<br/>
          Total: $${pendingPaymentTotal.toFixed(2)}
        </div>
      </div>

      <h3 style="margin:0 0 8px;">Aprobadas</h3>
      <table style="border-collapse:collapse;width:100%;margin-bottom:18px;">
        <thead>
          <tr style="background:#f5f5f5;">
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Folio</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Cliente</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Proyecto</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Fecha Aprobaci&oacute;n</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:right;">Total</th>
          </tr>
        </thead>
        <tbody>
          ${renderRows(params.approvedRows, false)}
        </tbody>
      </table>

      <h3 style="margin:0 0 8px;">Por cobrar</h3>
      <table style="border-collapse:collapse;width:100%;">
        <thead>
          <tr style="background:#f5f5f5;">
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Folio</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Cliente</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Proyecto</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Fecha Aprobaci&oacute;n</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left;">Fecha Conclusi&oacute;n</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:right;">Total</th>
          </tr>
        </thead>
        <tbody>
          ${renderRows(params.pendingPaymentRows, true)}
        </tbody>
      </table>
    </div>
  `;
}

function buildSummaryText(params: {
  approvedRows: QuoteSummaryRow[];
  pendingPaymentRows: QuoteSummaryRow[];
  generatedAt: string;
  trigger: "scheduled" | "manual";
}) {
  const approvedTotal = params.approvedRows.reduce((sum, row) => sum + row.total, 0);
  const pendingPaymentTotal = params.pendingPaymentRows.reduce((sum, row) => sum + row.total, 0);

  return [
    "Resumen de cotizaciones",
    `Tipo de envio: ${params.trigger === "scheduled" ? "Programado (lunes 8:00)" : "Reenvio manual"}`,
    `Generado: ${params.generatedAt}`,
    "",
    `Aprobadas: ${params.approvedRows.length} | Total: $${approvedTotal.toFixed(2)}`,
    `Por cobrar: ${params.pendingPaymentRows.length} | Total: $${pendingPaymentTotal.toFixed(2)}`,
  ].join("\n");
}

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

function readRole(
  appMetadata: Record<string, unknown> | undefined,
  userMetadata: Record<string, unknown> | undefined,
  email: string,
  owner: string,
): Role {
  if (email === owner) return "super_admin";

  const directRole = parseRole(appMetadata?.role) ?? parseRole(userMetadata?.role);
  if (directRole != null) {
    return directRole;
  }

  const appRoles = appMetadata?.roles;
  if (Array.isArray(appRoles)) {
    for (const roleValue of appRoles) {
      const parsed = parseRole(roleValue);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  const userRoles = userMetadata?.roles;
  if (Array.isArray(userRoles)) {
    for (const roleValue of userRoles) {
      const parsed = parseRole(roleValue);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return "staff";
}

function parseRole(raw: unknown): Role | null {
  const value = `${raw ?? ""}`.trim().toLowerCase();
  if (value === "super_admin" || value === "superadmin" || value === "owner") {
    return "super_admin";
  }
  if (value === "admin" || value === "administrator") {
    return "admin";
  }
  if (value === "staff" || value === "user") {
    return "staff";
  }
  return null;
}

function readIsActive(
  appMetadata: Record<string, unknown> | undefined,
  userMetadata: Record<string, unknown> | undefined,
) {
  if (typeof appMetadata?.is_active === "boolean") {
    return appMetadata.is_active;
  }
  if (typeof userMetadata?.is_active === "boolean") {
    return userMetadata.is_active;
  }
  return true;
}

function formatDate(iso?: string): string {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    return d.toLocaleDateString("es-MX", { day: "2-digit", month: "2-digit", year: "numeric" });
  } catch {
    return "—";
  }
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
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
