import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import JSZip from "https://esm.sh/jszip@3.10.1";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const inboundSecret = Deno.env.get("EMAIL_WEBHOOK_SECRET") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendApiBaseUrl = (Deno.env.get("RESEND_API_BASE_URL") ?? "https://api.resend.com").replace(/\/$/, "");
const invoicesBucket = (Deno.env.get("INVOICES_BUCKET") ?? "invoices").trim();

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

  if (!supabaseUrl || !serviceRoleKey || !inboundSecret || !resendApiKey) {
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

  const { data: inboundEvent, error } = await adminClient.from("inbound_email_events").insert({
    provider: "resend",
    message_id: normalized.messageId,
    from_email: normalized.from,
    to_email: normalized.to,
    subject: normalized.subject,
    text_body: normalized.textBody,
    html_body: normalized.htmlBody,
    raw_payload: payload,
  }).select("id").single();

  if (error) {
    return jsonError(error.message, 500);
  }

  const inboundEventId = `${inboundEvent?.id ?? ""}`.trim();
  const emailId = normalized.emailId;
  if (!emailId) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_skipped_missing_email_id", {
      inbound_event_id: inboundEventId,
      message_id: normalized.messageId,
    });
    return jsonResponse({ ok: true, skipped: "missing_email_id" });
  }

  const receivedEmail = await fetchReceivedEmail(emailId);
  if (!receivedEmail) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_skipped_missing_email_content", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
    });
    return jsonResponse({ ok: true, skipped: "missing_email_content" });
  }

  const attachments = await listReceivedAttachments(emailId);
  if (attachments.length === 0) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_skipped_no_attachments", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
    });
    return jsonResponse({ ok: true, skipped: "no_attachments" });
  }

  const extracted = await extractInvoiceFilesFromAttachments(attachments);
  if (!extracted.xml) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_skipped_no_valid_xml", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
      attachments_count: attachments.length,
    });
    return jsonResponse({ ok: true, skipped: "no_valid_xml" });
  }

  const parsed = parseSatXml(extracted.xml.contentText);
  if (!parsed) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_skipped_invalid_sat_xml", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
      source_attachment: extracted.xml.fileName,
    });
    return jsonResponse({ ok: true, skipped: "invalid_sat_xml" });
  }

  const duplicate = await adminClient
    .from("invoices")
    .select("id")
    .eq("uuid_sat", parsed.uuidSat)
    .maybeSingle();

  if (duplicate.data?.id) {
    await markInboundProcessed(adminClient, inboundEventId);
    await insertAuditLog(adminClient, "email_inbound_duplicate_uuid", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
      uuid_sat: parsed.uuidSat,
    });
    return jsonResponse({ ok: true, duplicate: true, uuid_sat: parsed.uuidSat });
  }

  const providerClientId = await findOrCreateProviderClient(adminClient, {
    providerRfc: parsed.providerRfc,
    providerName: parsed.providerName,
  });

  const xmlPath = buildInvoiceStoragePath(parsed.uuidSat, extracted.xml.fileName);
  const xmlUpload = await adminClient.storage.from(invoicesBucket).upload(xmlPath, extracted.xml.bytes, {
    contentType: "application/xml",
    upsert: false,
  });

  if (xmlUpload.error) {
    await insertAuditLog(adminClient, "email_inbound_xml_upload_failed", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
      error: xmlUpload.error.message,
    });
    return jsonError("Failed to upload XML invoice file.", 500);
  }

  let pdfPath: string | null = null;
  if (extracted.pdf) {
    const computedPdfPath = buildInvoiceStoragePath(parsed.uuidSat, extracted.pdf.fileName);
    const pdfUpload = await adminClient.storage.from(invoicesBucket).upload(computedPdfPath, extracted.pdf.bytes, {
      contentType: "application/pdf",
      upsert: false,
    });
    if (!pdfUpload.error) {
      pdfPath = computedPdfPath;
    }
  }

  const insertInvoice = await adminClient.from("invoices").insert({
    uuid_sat: parsed.uuidSat,
    proveedor: parsed.providerName || parsed.providerRfc || "PROVEEDOR_DESCONOCIDO",
    total: parsed.total,
    fecha: parsed.fecha,
    xml_url: xmlPath,
    pdf_url: pdfPath,
    provider_rfc: parsed.providerRfc,
    provider_client_id: providerClientId,
    inbound_email_event_id: inboundEventId || null,
    source_email_id: emailId,
    status: "unassigned",
    metadata: {
      from_email: normalized.from,
      subject: normalized.subject,
      resend_message_id: normalized.messageId,
      attachments_count: attachments.length,
      source_xml_attachment: extracted.xml.fileName,
      source_pdf_attachment: extracted.pdf?.fileName ?? null,
    },
  }).select("id").single();

  if (insertInvoice.error) {
    await insertAuditLog(adminClient, "email_inbound_invoice_insert_failed", {
      inbound_event_id: inboundEventId,
      email_id: emailId,
      uuid_sat: parsed.uuidSat,
      error: insertInvoice.error.message,
    });
    return jsonError(insertInvoice.error.message, 500);
  }

  await markInboundProcessed(adminClient, inboundEventId);
  await insertAuditLog(adminClient, "email_inbound_invoice_created", {
    inbound_event_id: inboundEventId,
    invoice_id: insertInvoice.data?.id,
    uuid_sat: parsed.uuidSat,
    provider_client_id: providerClientId,
  });

  return jsonResponse({ ok: true, invoice_id: insertInvoice.data?.id, uuid_sat: parsed.uuidSat });
});

type NormalizedInboundPayload = {
  from: string | null;
  to: string | null;
  subject: string | null;
  textBody: string | null;
  htmlBody: string | null;
  messageId: string | null;
  emailId: string | null;
};

type ResendAttachment = {
  id: string;
  filename: string;
  contentType: string | null;
  downloadUrl: string;
};

type ExtractedFile = {
  fileName: string;
  bytes: Uint8Array;
  contentText: string;
};

type ParsedSatInvoice = {
  uuidSat: string;
  providerRfc: string | null;
  providerName: string | null;
  total: number;
  fecha: string;
};

async function markInboundProcessed(
  adminClient: ReturnType<typeof createClient>,
  inboundEventId: string,
) {
  if (!inboundEventId) return;
  await adminClient.from("inbound_email_events").update({
    processed: true,
    processed_at: new Date().toISOString(),
  }).eq("id", inboundEventId);
}

async function insertAuditLog(
  adminClient: ReturnType<typeof createClient>,
  eventName: string,
  payload: Record<string, unknown>,
) {
  await adminClient.from("audit_logs").insert({
    event_name: eventName,
    entity_type: "email_inbound",
    entity_id: `${payload.inbound_event_id ?? ""}`.trim() || null,
    payload,
  });
}

async function fetchReceivedEmail(emailId: string): Promise<Record<string, unknown> | null> {
  const response = await fetch(`${resendApiBaseUrl}/emails/receiving/${encodeURIComponent(emailId)}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json().catch(() => null);
  if (!data || typeof data !== "object") {
    return null;
  }
  return data as Record<string, unknown>;
}

async function listReceivedAttachments(emailId: string): Promise<ResendAttachment[]> {
  const response = await fetch(`${resendApiBaseUrl}/emails/receiving/${encodeURIComponent(emailId)}/attachments`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    return [];
  }

  const payload = await response.json().catch(() => ({} as Record<string, unknown>));
  const rows = Array.isArray((payload as Record<string, unknown>).data)
    ? ((payload as Record<string, unknown>).data as unknown[])
    : [];

  const attachments: ResendAttachment[] = [];
  for (const row of rows) {
    const item = asRecord(row);
    if (!item) continue;
    const id = coalesceString(item.id) ?? "";
    const filename = coalesceString(item.filename) ?? "";
    const downloadUrl = coalesceString(item.download_url) ?? "";
    if (!id || !filename || !downloadUrl) continue;

    attachments.push({
      id,
      filename,
      downloadUrl,
      contentType: coalesceString(item.content_type),
    });
  }

  return attachments;
}

async function extractInvoiceFilesFromAttachments(attachments: ResendAttachment[]): Promise<{
  xml: ExtractedFile | null;
  pdf: ExtractedFile | null;
}> {
  let xmlFile: ExtractedFile | null = null;
  let pdfFile: ExtractedFile | null = null;

  for (const attachment of attachments) {
    const ext = extensionOf(attachment.filename);
    const bytes = await downloadAttachmentBytes(attachment.downloadUrl);
    if (!bytes) continue;

    if (ext === "xml") {
      const text = decodeUtf8(bytes);
      if (looksLikeSatXml(text)) {
        xmlFile = {
          fileName: sanitizeFileName(attachment.filename, "invoice.xml"),
          bytes,
          contentText: text,
        };
      }
      continue;
    }

    if (ext === "pdf" && !pdfFile) {
      pdfFile = {
        fileName: sanitizeFileName(attachment.filename, "invoice.pdf"),
        bytes,
        contentText: "",
      };
      continue;
    }

    if (ext === "zip") {
      const extracted = await extractFilesFromZip(bytes);
      if (!xmlFile && extracted.xml && looksLikeSatXml(extracted.xml.contentText)) {
        xmlFile = extracted.xml;
      }
      if (!pdfFile && extracted.pdf) {
        pdfFile = extracted.pdf;
      }
    }
  }

  return { xml: xmlFile, pdf: pdfFile };
}

async function extractFilesFromZip(bytes: Uint8Array): Promise<{
  xml: ExtractedFile | null;
  pdf: ExtractedFile | null;
}> {
  try {
    const zip = await JSZip.loadAsync(bytes);
    let xml: ExtractedFile | null = null;
    let pdf: ExtractedFile | null = null;

    const entries = Object.values(zip.files);
    for (const entry of entries) {
      if (entry.dir) continue;
      const ext = extensionOf(entry.name);
      if (ext !== "xml" && ext !== "pdf") continue;

      const fileBytes = await entry.async("uint8array");
      if (ext === "xml" && !xml) {
        const text = decodeUtf8(fileBytes);
        xml = {
          fileName: sanitizeFileName(entry.name, "invoice.xml"),
          bytes: fileBytes,
          contentText: text,
        };
      }
      if (ext === "pdf" && !pdf) {
        pdf = {
          fileName: sanitizeFileName(entry.name, "invoice.pdf"),
          bytes: fileBytes,
          contentText: "",
        };
      }
    }

    return { xml, pdf };
  } catch {
    return { xml: null, pdf: null };
  }
}

async function downloadAttachmentBytes(downloadUrl: string): Promise<Uint8Array | null> {
  try {
    const response = await fetch(downloadUrl);
    if (!response.ok) return null;
    return new Uint8Array(await response.arrayBuffer());
  } catch {
    return null;
  }
}

function parseSatXml(xml: string): ParsedSatInvoice | null {
  const safeXml = `${xml ?? ""}`.trim();
  if (!safeXml) return null;

  const uuid = extractXmlAttribute(safeXml, "TimbreFiscalDigital", "UUID");
  const totalRaw = extractXmlAttribute(safeXml, "Comprobante", "Total");
  const fecha = extractXmlAttribute(safeXml, "Comprobante", "Fecha");
  const rfc = extractXmlAttribute(safeXml, "Emisor", "Rfc") ?? extractXmlAttribute(safeXml, "Emisor", "RFC");
  const nombre = extractXmlAttribute(safeXml, "Emisor", "Nombre");

  const uuidSat = `${uuid ?? ""}`.trim().toUpperCase();
  if (!isUuidLike(uuidSat)) return null;

  const total = Number(`${totalRaw ?? ""}`.replace(/,/g, "").trim());
  if (!Number.isFinite(total) || total < 0) return null;

  const parsedDate = new Date(`${fecha ?? ""}`);
  if (Number.isNaN(parsedDate.getTime())) return null;

  return {
    uuidSat,
    providerRfc: normalizeRfc(rfc),
    providerName: nombre?.trim() || null,
    total,
    fecha: parsedDate.toISOString(),
  };
}

function extractXmlAttribute(xml: string, tagName: string, attrName: string): string | null {
  const pattern = new RegExp(`<[^>]*${tagName}[^>]*\\b${attrName}=["']([^"']+)["'][^>]*>`, "i");
  const match = xml.match(pattern);
  if (!match || !match[1]) return null;
  return match[1].trim();
}

function isUuidLike(value: string): boolean {
  return /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(value);
}

function normalizeRfc(value: string | null): string | null {
  if (!value) return null;
  const rfc = value.trim().toUpperCase();
  return rfc.length > 0 ? rfc : null;
}

function looksLikeSatXml(text: string): boolean {
  if (!text) return false;
  const compact = text.toLowerCase();
  return compact.includes("comprobante") && compact.includes("timbrefiscaldigital");
}

function extensionOf(filename: string): string {
  const normalized = filename.toLowerCase().trim();
  const dot = normalized.lastIndexOf(".");
  if (dot < 0 || dot === normalized.length - 1) return "";
  return normalized.slice(dot + 1);
}

function decodeUtf8(bytes: Uint8Array): string {
  return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
}

function sanitizeFileName(input: string, fallback: string): string {
  const base = (input || "").replace(/\\/g, "/").split("/").pop() ?? "";
  const clean = base.replace(/[^A-Za-z0-9._-]/g, "_").replace(/_+/g, "_").replace(/^_+|_+$/g, "");
  return clean || fallback;
}

function buildInvoiceStoragePath(uuidSat: string, fileName: string): string {
  const now = new Date();
  const yyyy = now.getUTCFullYear();
  const mm = String(now.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(now.getUTCDate()).padStart(2, "0");
  const safeName = sanitizeFileName(fileName, "file.bin");
  const stamp = now.getTime();
  return `inbound/${yyyy}/${mm}/${dd}/${uuidSat}/${stamp}_${safeName}`;
}

async function findOrCreateProviderClient(
  adminClient: ReturnType<typeof createClient>,
  args: { providerRfc: string | null; providerName: string | null },
): Promise<string | null> {
  if (args.providerRfc) {
    const existingByRfc = await adminClient
      .from("clients")
      .select("id")
      .eq("rfc", args.providerRfc)
      .limit(1)
      .maybeSingle();

    if (existingByRfc.data?.id) {
      return existingByRfc.data.id as string;
    }
  }

  const businessName = `${args.providerName ?? ""}`.trim() || `${args.providerRfc ?? ""}`.trim() || "Proveedor sin nombre";
  const notes = "Creado automaticamente por email-inbound como proveedor de facturas";

  const created = await adminClient.from("clients").insert({
    business_name: businessName,
    rfc: args.providerRfc,
    sector_label: "PROVEEDOR",
    notes,
  }).select("id").single();

  if (created.error || !created.data?.id) {
    return null;
  }

  return created.data.id as string;
}

function normalizeInboundPayload(payload: Record<string, unknown>): NormalizedInboundPayload {
  const data = asRecord(payload.data);
  const from = coalesceString(data?.from, data?.from_email, payload.from, payload.from_email);
  const to = coalesceString(data?.to, data?.to_email, payload.to, payload.to_email);
  const subject = coalesceString(data?.subject, payload.subject);
  const textBody = coalesceString(data?.text, data?.text_body, payload.text, payload.text_body);
  const htmlBody = coalesceString(data?.html, data?.html_body, payload.html, payload.html_body);
  const messageId = coalesceString(data?.message_id, payload.message_id, data?.id, payload.id);
  const emailId = coalesceString(data?.email_id, data?.id, payload.email_id, payload.id);

  return { from, to, subject, textBody, htmlBody, messageId, emailId };
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
