import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Role = "super_admin" | "admin" | "staff";
type Action = "list_users" | "invite_user" | "update_role" | "set_active" | "reset_password" | "resend_invite";

type RequestBody = {
  action?: Action;
  email?: string;
  role?: string;
  user_id?: string;
  is_active?: boolean;
  redirect_to?: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const appPublicUrl = Deno.env.get("APP_PUBLIC_URL") ?? "";
const ownerEmail = (Deno.env.get("OWNER_EMAIL") ?? "mvazquez@gruporemaa.com").trim().toLowerCase();
const INVITE_EXPIRY_HOURS = 24;

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

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonError("Missing Supabase environment variables.", 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return jsonError("Missing Authorization bearer token.", 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: {
      headers: { Authorization: `Bearer ${token}` },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
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
  const callerIsActive = readIsActive(caller.app_metadata, caller.user_metadata);

  if (!callerIsActive) {
    return jsonError("User disabled.", 403);
  }

  if (callerRole !== "super_admin") {
    return jsonError("Only super-admin can manage users.", 403);
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return jsonError("Invalid request body.", 400);
  }

  switch (body.action) {
    case "list_users":
      return await handleListUsers(adminClient, ownerEmail);
    case "invite_user":
      return await handleInviteUser(adminClient, caller.id, callerEmail, body, ownerEmail);
    case "update_role":
      return await handleUpdateRole(adminClient, caller.id, callerEmail, body, ownerEmail);
    case "set_active":
      return await handleSetActive(adminClient, caller.id, callerEmail, body, ownerEmail);
    case "reset_password":
      return await handleResetPassword(adminClient, caller.id, callerEmail, body, ownerEmail);
    case "resend_invite":
      return await handleResendInvite(adminClient, caller.id, callerEmail, body, ownerEmail);
    default:
      return jsonError("Unsupported action.", 400);
  }
});

async function handleListUsers(adminClient: ReturnType<typeof createClient>, ownerEmail: string) {
  const { data, error } = await adminClient.auth.admin.listUsers();
  if (error) {
    return jsonError(error.message, 500);
  }

  const nowMs = Date.now();

  const users = (data.users ?? []).map((user: any) => {
    const email = (user.email ?? "").trim().toLowerCase();
    const createdAtRaw = typeof user.created_at === "string" ? user.created_at : null;
    const createdAtMs = createdAtRaw ? Date.parse(createdAtRaw) : NaN;
    const hasLastSignIn = Boolean(user.last_sign_in_at);
    const invitePending = !hasLastSignIn;
    const inviteExpired =
      invitePending && Number.isFinite(createdAtMs)
        ? nowMs - createdAtMs >= INVITE_EXPIRY_HOURS * 60 * 60 * 1000
        : false;

    return {
      id: user.id,
      email,
      role: readRole(user.app_metadata, user.user_metadata, email, ownerEmail),
      is_active: readIsActive(user.app_metadata, user.user_metadata),
      email_confirmed: Boolean(user.email_confirmed_at),
      created_at: user.created_at,
      last_sign_in_at: user.last_sign_in_at,
      invite_pending: invitePending,
      invite_expired: inviteExpired,
      can_resend_invite: invitePending && inviteExpired,
    };
  });

  return jsonResponse({ users });
}

async function handleInviteUser(
  adminClient: ReturnType<typeof createClient>,
  actorId: string,
  actorEmail: string,
  body: RequestBody,
  ownerEmail: string,
) {
  const email = (body.email ?? "").trim().toLowerCase();
  const role = normalizeRole(body.role, ownerEmail);
  const redirectTo = effectiveRedirectTo(body.redirect_to);

  if (!email || !email.includes("@")) {
    return jsonError("Invalid email.", 400);
  }
  if (role === "super_admin") {
    return jsonError("Cannot invite a super-admin.", 403);
  }

  // Generate invite link via generateLink only (does NOT send a Supabase email).
  // Creates the user if they don't yet exist.
  const inviteLinkPayload: Record<string, unknown> = {
    type: "invite",
    email,
  };
  if (redirectTo != null) {
    inviteLinkPayload.options = { redirectTo };
    inviteLinkPayload.redirectTo = redirectTo;
  }

  const { data: inviteLinkData, error: inviteLinkError } = await adminClient.auth.admin.generateLink(
    inviteLinkPayload as never,
  );

  if (inviteLinkError) {
    return jsonError(inviteLinkError.message, 500);
  }

  const inviteActionLink = readActionLink(inviteLinkData);
  if (!inviteActionLink) {
    return jsonError("No invite action link returned by Supabase.", 500);
  }

  const userId = (inviteLinkData as Record<string, unknown> & { user?: { id?: string } })?.user?.id;
  if (!userId) {
    return jsonError("No user ID returned from generateLink.", 500);
  }

  const { error: updateError } = await adminClient.auth.admin.updateUserById(userId, {
    app_metadata: { role, is_active: true },
  });

  if (updateError) {
    return jsonError(updateError.message, 500);
  }

  const emailDelivery = await sendResendEmail(adminClient, {
    actorUserId: actorId,
    actorEmail,
    toEmail: email,
    subject: "Invitacion a REMA Arquitectura",
    templateKey: "user_invite",
    html: buildInviteEmailHtml({
      inviteLink: inviteActionLink,
      role,
      invitedBy: actorEmail,
    }),
    text: buildInviteEmailText({
      inviteLink: inviteActionLink,
      role,
      invitedBy: actorEmail,
    }),
    payload: {
      role,
      redirect_to: redirectTo,
      delivery: "resend",
      invite_action_link: inviteActionLink,
    },
  });

  if (!emailDelivery.ok) {
    return jsonError(emailDelivery.error ?? "Resend delivery failed.", 502);
  }

  await auditLog(adminClient, {
    actorId,
    actorEmail,
    targetUserId: userId,
    targetEmail: email,
    action: "invite_user",
    payload: { role, redirect_to: redirectTo, delivery: "resend" },
  });

  return jsonResponse({ ok: true, delivery: "resend" });
}

async function handleUpdateRole(
  adminClient: ReturnType<typeof createClient>,
  actorId: string,
  actorEmail: string,
  body: RequestBody,
  ownerEmail: string,
) {
  const userId = (body.user_id ?? "").trim();
  const role = normalizeRole(body.role, ownerEmail);

  if (!userId) {
    return jsonError("Missing user_id.", 400);
  }
  if (role === "super_admin") {
    return jsonError("Use transfer flow for super-admin.", 403);
  }

  const { data: targetData, error: getError } = await adminClient.auth.admin.getUserById(userId);
  if (getError || !targetData.user) {
    return jsonError(getError?.message ?? "User not found.", 404);
  }

  const targetEmail = (targetData.user.email ?? "").trim().toLowerCase();
  if (targetEmail === ownerEmail) {
    return jsonError("Owner role cannot be downgraded from this endpoint.", 403);
  }

  const mergedAppMetadata = {
    ...(targetData.user.app_metadata ?? {}),
    role,
  };

  const { error: updateError } = await adminClient.auth.admin.updateUserById(userId, {
    app_metadata: mergedAppMetadata,
  });

  if (updateError) {
    return jsonError(updateError.message, 500);
  }

  await auditLog(adminClient, {
    actorId,
    actorEmail,
    targetUserId: userId,
    targetEmail,
    action: "update_role",
    payload: { role },
  });

  return jsonResponse({ ok: true });
}

async function handleSetActive(
  adminClient: ReturnType<typeof createClient>,
  actorId: string,
  actorEmail: string,
  body: RequestBody,
  ownerEmail: string,
) {
  const userId = (body.user_id ?? "").trim();
  const isActive = body.is_active;

  if (!userId) {
    return jsonError("Missing user_id.", 400);
  }
  if (typeof isActive !== "boolean") {
    return jsonError("Missing is_active boolean.", 400);
  }

  const { data: targetData, error: getError } = await adminClient.auth.admin.getUserById(userId);
  if (getError || !targetData.user) {
    return jsonError(getError?.message ?? "User not found.", 404);
  }

  const targetEmail = (targetData.user.email ?? "").trim().toLowerCase();
  if (targetEmail === ownerEmail && !isActive) {
    return jsonError("Owner cannot be deactivated.", 403);
  }

  const mergedAppMetadata = {
    ...(targetData.user.app_metadata ?? {}),
    is_active: isActive,
  };

  const { error: updateError } = await adminClient.auth.admin.updateUserById(userId, {
    app_metadata: mergedAppMetadata,
  });

  if (updateError) {
    return jsonError(updateError.message, 500);
  }

  await auditLog(adminClient, {
    actorId,
    actorEmail,
    targetUserId: userId,
    targetEmail,
    action: "set_active",
    payload: { is_active: isActive },
  });

  return jsonResponse({ ok: true });
}

async function handleResetPassword(
  adminClient: ReturnType<typeof createClient>,
  actorId: string,
  actorEmail: string,
  body: RequestBody,
  ownerEmail: string,
) {
  const userId = (body.user_id ?? "").trim();
  const redirectTo = effectiveRedirectTo(body.redirect_to);
  if (!userId) {
    return jsonError("Missing user_id.", 400);
  }

  const { data: targetData, error: getError } = await adminClient.auth.admin.getUserById(userId);
  if (getError || !targetData.user) {
    return jsonError(getError?.message ?? "User not found.", 404);
  }

  const targetEmail = (targetData.user.email ?? "").trim().toLowerCase();
  if (!targetEmail) {
    return jsonError("Target user has no email.", 400);
  }

  if (targetEmail === ownerEmail) {
    return jsonError("Owner password reset must be manual.", 403);
  }

  const recoveryLinkPayload: Record<string, unknown> = {
    type: "recovery",
    email: targetEmail,
  };
  if (redirectTo != null) {
    recoveryLinkPayload.options = { redirectTo };
    recoveryLinkPayload.redirectTo = redirectTo;
  }

  const { data: recoveryData, error: linkError } = await adminClient.auth.admin.generateLink(
    recoveryLinkPayload as never,
  );

  if (linkError) {
    return jsonError(linkError.message, 500);
  }

  const recoveryLink = readActionLink(recoveryData);
  if (!recoveryLink) {
    return jsonError("No recovery action link returned by Supabase.", 500);
  }

  const emailDelivery = await sendResendEmail(adminClient, {
    actorUserId: actorId,
    actorEmail,
    toEmail: targetEmail,
    subject: "Restablece tu acceso a REMA Arquitectura",
    templateKey: "password_reset",
    html: buildPasswordResetEmailHtml({
      recoveryLink,
      requestedBy: actorEmail,
    }),
    text: buildPasswordResetEmailText({
      recoveryLink,
      requestedBy: actorEmail,
    }),
    payload: {
      redirect_to: redirectTo,
      delivery: "resend",
      recovery_action_link: recoveryLink,
    },
  });

  if (!emailDelivery.ok) {
    return jsonError(emailDelivery.error ?? "Resend delivery failed.", 502);
  }

  await auditLog(adminClient, {
    actorId,
    actorEmail,
    targetUserId: userId,
    targetEmail,
    action: "reset_password",
    payload: { redirect_to: redirectTo, delivery: "resend" },
  });

  return jsonResponse({ ok: true, delivery: "resend" });
}

async function handleResendInvite(
  adminClient: ReturnType<typeof createClient>,
  actorId: string,
  actorEmail: string,
  body: RequestBody,
  ownerEmail: string,
) {
  const userId = (body.user_id ?? "").trim();
  const redirectTo = effectiveRedirectTo(body.redirect_to);

  if (!userId) {
    return jsonError("Missing user_id.", 400);
  }

  const { data: targetData, error: getError } = await adminClient.auth.admin.getUserById(userId);
  if (getError || !targetData.user) {
    return jsonError(getError?.message ?? "User not found.", 404);
  }

  const targetEmail = (targetData.user.email ?? "").trim().toLowerCase();
  if (!targetEmail) {
    return jsonError("Target user has no email.", 400);
  }

  if (targetData.user.last_sign_in_at) {
    return jsonError("User has already activated access. Use reset password instead.", 409);
  }

  const createdAtRaw = typeof targetData.user.created_at === "string" ? targetData.user.created_at : null;
  const createdAtMs = createdAtRaw ? Date.parse(createdAtRaw) : NaN;
  if (Number.isFinite(createdAtMs)) {
    const ageMs = Date.now() - createdAtMs;
    const minResendMs = INVITE_EXPIRY_HOURS * 60 * 60 * 1000;
    if (ageMs < minResendMs) {
      const remainingHours = Math.ceil((minResendMs - ageMs) / (60 * 60 * 1000));
      return jsonError(
        `Invite is still valid. You can resend in approximately ${remainingHours}h.`,
        429,
      );
    }
  }

  const targetRole = readRole(targetData.user.app_metadata, targetData.user.user_metadata, targetEmail, ownerEmail);
  if (targetRole === "super_admin") {
    return jsonError("Cannot resend invite to super-admin from this endpoint.", 403);
  }

  const inviteLinkPayload: Record<string, unknown> = {
    type: "invite",
    email: targetEmail,
  };
  if (redirectTo != null) {
    inviteLinkPayload.options = { redirectTo };
    inviteLinkPayload.redirectTo = redirectTo;
  }

  const { data: inviteLinkData, error: inviteLinkError } = await adminClient.auth.admin.generateLink(
    inviteLinkPayload as never,
  );

  if (inviteLinkError) {
    return jsonError(inviteLinkError.message, 500);
  }

  const inviteActionLink = readActionLink(inviteLinkData);
  if (!inviteActionLink) {
    return jsonError("No invite action link returned by Supabase.", 500);
  }

  const emailDelivery = await sendResendEmail(adminClient, {
    actorUserId: actorId,
    actorEmail,
    toEmail: targetEmail,
    subject: "Invitacion a REMA Arquitectura",
    templateKey: "user_invite",
    html: buildInviteEmailHtml({
      inviteLink: inviteActionLink,
      role: targetRole,
      invitedBy: actorEmail,
    }),
    text: buildInviteEmailText({
      inviteLink: inviteActionLink,
      role: targetRole,
      invitedBy: actorEmail,
    }),
    payload: {
      role: targetRole,
      redirect_to: redirectTo,
      delivery: "resend",
      invite_action_link: inviteActionLink,
      resent: true,
    },
  });

  if (!emailDelivery.ok) {
    return jsonError(emailDelivery.error ?? "Resend delivery failed.", 502);
  }

  await auditLog(adminClient, {
    actorId,
    actorEmail,
    targetUserId: userId,
    targetEmail,
    action: "resend_invite",
    payload: { redirect_to: redirectTo, delivery: "resend" },
  });

  return jsonResponse({ ok: true, delivery: "resend" });
}

async function sendResendEmail(
  adminClient: ReturnType<typeof createClient>,
  params: {
    actorUserId: string;
    actorEmail: string;
    toEmail: string;
    subject: string;
    templateKey: string;
    html: string;
    text: string;
    payload: Record<string, unknown>;
  },
) {
  if (!resendApiKey || !resendFromEmail) {
    return { ok: false, error: "Missing RESEND_API_KEY or RESEND_FROM_EMAIL." };
  }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: resendFromEmail,
      to: [params.toEmail],
      subject: params.subject,
      html: params.html,
      text: params.text,
    }),
  });

  const resendData = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    await insertOutboundLog(adminClient, {
      actorUserId: params.actorUserId,
      actorEmail: params.actorEmail,
      toEmail: params.toEmail,
      subject: params.subject,
      templateKey: params.templateKey,
      status: "failed",
      payload: params.payload,
      errorText: JSON.stringify(resendData),
    });
    return { ok: false, error: JSON.stringify(resendData) };
  }

  await insertOutboundLog(adminClient, {
    actorUserId: params.actorUserId,
    actorEmail: params.actorEmail,
    toEmail: params.toEmail,
    subject: params.subject,
    templateKey: params.templateKey,
    providerMessageId: (resendData as Record<string, unknown>)?.id as string | undefined,
    status: "sent",
    payload: params.payload,
  });

  return { ok: true };
}

async function insertOutboundLog(
  adminClient: ReturnType<typeof createClient>,
  params: {
    actorUserId: string;
    actorEmail: string;
    toEmail: string;
    subject: string;
    templateKey: string;
    providerMessageId?: string;
    status: "sent" | "failed" | "queued";
    payload: Record<string, unknown>;
    errorText?: string;
  },
) {
  await adminClient.from("outbound_email_log").insert({
    actor_user_id: params.actorUserId,
    actor_email: params.actorEmail,
    to_email: params.toEmail,
    subject: params.subject,
    template_key: params.templateKey,
    provider: "resend",
    provider_message_id: params.providerMessageId,
    status: params.status,
    payload: params.payload,
    error_text: params.errorText,
  });
}

function normalizeRedirectTo(raw: string | undefined): string | null {
  const value = (raw ?? "").trim();
  return value.length > 0 ? value : null;
}

function effectiveRedirectTo(raw: string | undefined): string | null {
  const explicit = normalizeRedirectTo(raw);
  if (explicit != null) {
    return explicit;
  }

  const configured = normalizeRedirectTo(appPublicUrl);
  if (configured == null) {
    return null;
  }

  try {
    return new URL("/register?mode=invite", configured).toString();
  } catch {
    return configured;
  }
}

function readActionLink(data: unknown): string | null {
  if (!data || typeof data !== "object") {
    return null;
  }

  const record = data as Record<string, unknown>;
  const direct = record.action_link;
  if (typeof direct === "string" && direct.trim().length > 0) {
    return direct.trim();
  }

  const properties = record.properties;
  if (properties && typeof properties === "object") {
    const actionLink = (properties as Record<string, unknown>).action_link;
    if (typeof actionLink === "string" && actionLink.trim().length > 0) {
      return actionLink.trim();
    }
  }

  return null;
}

function buildInviteEmailHtml(params: { inviteLink: string; role: Role; invitedBy: string }) {
  return `
    <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#1f1f1f;">
      <h1 style="margin:0 0 16px;font-size:28px;">Invitacion a REMA Arquitectura</h1>
      <p style="margin:0 0 12px;">Has sido invitado a acceder al sistema de REMA como <strong>${params.role}</strong>.</p>
      <p style="margin:0 0 20px;">Invitado por: ${params.invitedBy}</p>
      <p style="margin:0 0 24px;">
        <a href="${params.inviteLink}" style="display:inline-block;padding:12px 18px;background:#f5b400;color:#3d2e00;text-decoration:none;border-radius:8px;font-weight:700;">
          Aceptar invitacion
        </a>
      </p>
      <p style="margin:0 0 12px;">Si el boton no abre correctamente, copia y pega este enlace en tu navegador:</p>
      <p style="word-break:break-all;font-size:13px;color:#555;">${params.inviteLink}</p>
    </div>
  `.trim();
}

function buildInviteEmailText(params: { inviteLink: string; role: Role; invitedBy: string }) {
  return [
    "Invitacion a REMA Arquitectura",
    "",
    `Has sido invitado a acceder al sistema como ${params.role}.`,
    `Invitado por: ${params.invitedBy}`,
    "",
    "Abre este enlace para aceptar la invitacion:",
    params.inviteLink,
  ].join("\n");
}

function buildPasswordResetEmailHtml(params: { recoveryLink: string; requestedBy: string }) {
  return `
    <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#1f1f1f;">
      <h1 style="margin:0 0 16px;font-size:28px;">Restablece tu acceso a REMA</h1>
      <p style="margin:0 0 12px;">Se solicito un restablecimiento de contraseña para tu cuenta.</p>
      <p style="margin:0 0 20px;">Solicitado por: ${params.requestedBy}</p>
      <p style="margin:0 0 24px;">
        <a href="${params.recoveryLink}" style="display:inline-block;padding:12px 18px;background:#f5b400;color:#3d2e00;text-decoration:none;border-radius:8px;font-weight:700;">
          Restablecer acceso
        </a>
      </p>
      <p style="margin:0 0 12px;">Si el boton no abre correctamente, copia y pega este enlace en tu navegador:</p>
      <p style="word-break:break-all;font-size:13px;color:#555;">${params.recoveryLink}</p>
    </div>
  `.trim();
}

function buildPasswordResetEmailText(params: { recoveryLink: string; requestedBy: string }) {
  return [
    "Restablece tu acceso a REMA Arquitectura",
    "",
    "Se solicito un restablecimiento de contraseña para tu cuenta.",
    `Solicitado por: ${params.requestedBy}`,
    "",
    "Abre este enlace para restablecer tu acceso:",
    params.recoveryLink,
  ].join("\n");
}

function normalizeRole(raw: string | undefined, ownerEmail: string): Role {
  const value = `${raw ?? "staff"}`.trim().toLowerCase();
  if (value === "super_admin" || value === "superadmin" || value === "owner") {
    return "super_admin";
  }
  if (value === "admin" || value === "administrator") {
    return "admin";
  }
  if (value === "staff" || value === "user") {
    return "staff";
  }

  if (value === ownerEmail) {
    return "super_admin";
  }

  return "staff";
}

function readRole(
  appMetadata: Record<string, unknown> | null,
  userMetadata: Record<string, unknown> | null,
  email: string,
  ownerEmail: string,
): Role {
  if (email === ownerEmail) {
    return "super_admin";
  }

  const directRole =
    normalizeRoleFromMetadata(appMetadata?.role) ?? normalizeRoleFromMetadata(userMetadata?.role);
  if (directRole != null) {
    return directRole;
  }

  const appRoles = appMetadata?.roles;
  if (Array.isArray(appRoles)) {
    for (const role of appRoles) {
      const parsed = normalizeRoleFromMetadata(role);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  const userRoles = userMetadata?.roles;
  if (Array.isArray(userRoles)) {
    for (const role of userRoles) {
      const parsed = normalizeRoleFromMetadata(role);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return "staff";
}

function normalizeRoleFromMetadata(raw: unknown): Role | null {
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
  appMetadata: Record<string, unknown> | null,
  userMetadata: Record<string, unknown> | null,
): boolean {
  if (typeof appMetadata?.is_active === "boolean") {
    return appMetadata.is_active;
  }
  if (typeof userMetadata?.is_active === "boolean") {
    return userMetadata.is_active;
  }
  return true;
}

async function auditLog(
  adminClient: ReturnType<typeof createClient>,
  params: {
    actorId: string;
    actorEmail: string;
    targetUserId: string;
    targetEmail: string;
    action: string;
    payload: Record<string, unknown>;
  },
) {
  await adminClient.from("user_admin_audit").insert({
    actor_user_id: params.actorId,
    actor_email: params.actorEmail,
    target_user_id: params.targetUserId,
    target_email: params.targetEmail,
    action: params.action,
    payload: params.payload,
  });
}

function jsonError(message: string, status = 400) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
