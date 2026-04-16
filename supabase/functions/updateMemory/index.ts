import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type UpdateMemoryInput = {
  project_id?: string;
  new_event?: string;
  optional_state_update?: Record<string, unknown>;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

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

  let input: UpdateMemoryInput;
  try {
    input = (await req.json()) as UpdateMemoryInput;
  } catch {
    return jsonError("Invalid request body.", 400);
  }

  const projectId = `${input.project_id ?? ""}`.trim();
  const newEvent = `${input.new_event ?? ""}`.trim();
  const stateUpdate = input.optional_state_update;

  if (!projectId) {
    return jsonError("project_id is required.", 400);
  }

  if (!newEvent) {
    return jsonError("new_event is required.", 400);
  }

  if (stateUpdate !== undefined && !isPlainObject(stateUpdate)) {
    return jsonError("optional_state_update must be a JSON object.", 400);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return jsonError("Unauthorized user.", 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: logError } = await adminClient.from("memory_logs").insert({
    project_id: projectId,
    role: "event",
    content: newEvent,
  });

  if (logError) {
    return jsonError("Failed to insert memory log.", 500, logError.message);
  }

  const [{ data: currentStateRow, error: currentStateError }, { data: currentSummaryRow, error: currentSummaryError }] =
    await Promise.all([
      adminClient.from("memory_state").select("state").eq("project_id", projectId).maybeSingle(),
      adminClient.from("memory_summary").select("summary").eq("project_id", projectId).maybeSingle(),
    ]);

  if (currentStateError || currentSummaryError) {
    return jsonError("Failed to load current memory data.", 500, {
      stateError: currentStateError?.message,
      summaryError: currentSummaryError?.message,
    });
  }

  const baseState = isPlainObject(currentStateRow?.state) ? (currentStateRow?.state as Record<string, unknown>) : {};
  const mergedState = stateUpdate ? deepMerge(baseState, stateUpdate) : baseState;

  if (stateUpdate) {
    const { error: upsertStateError } = await adminClient.from("memory_state").upsert(
      {
        project_id: projectId,
        state: mergedState,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "project_id" },
    );

    if (upsertStateError) {
      return jsonError("Failed to update memory state.", 500, upsertStateError.message);
    }
  }

  const { data: recentLogs, error: logsError } = await adminClient
    .from("memory_logs")
    .select("content, created_at")
    .eq("project_id", projectId)
    .order("created_at", { ascending: false })
    .limit(10);

  if (logsError) {
    return jsonError("Failed to load memory logs.", 500, logsError.message);
  }

  const previousSummary = `${currentSummaryRow?.summary ?? ""}`.trim();
  const summary = buildSummary({
    state: mergedState,
    previousSummary,
    newEvent,
    recentLogs: (recentLogs ?? []) as Array<{ content: string; created_at: string }>,
  });

  const { error: upsertSummaryError } = await adminClient.from("memory_summary").upsert(
    {
      project_id: projectId,
      summary,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "project_id" },
  );

  if (upsertSummaryError) {
    return jsonError("Failed to update memory summary.", 500, upsertSummaryError.message);
  }

  return jsonResponse({ success: true });
});

function buildSummary(args: {
  state: Record<string, unknown>;
  previousSummary: string;
  newEvent: string;
  recentLogs: Array<{ content: string; created_at: string }>;
}) {
  const faseActual = readString(args.state.fase_actual);
  const decisiones = readStringArray(args.state.decisiones);
  const avancesState = readStringArray(args.state.problemas_resueltos);
  const pendientes = readStringArray(args.state.pendientes);

  const recentEvents = args.recentLogs
    .map((log) => `${log.content ?? ""}`.trim())
    .filter((value) => value.length > 0)
    .slice(0, 4);

  const inheritedCritical = extractCriticalFragments(args.previousSummary);

  const lines: string[] = [];

  lines.push(`Estado actual: ${faseActual || "sin fase definida"}.`);

  if (inheritedCritical.length > 0) {
    lines.push(`Contexto critico heredado: ${inheritedCritical.join("; ")}.`);
  }

  if (decisiones.length > 0) {
    lines.push(`Decisiones: ${decisiones.slice(0, 5).join("; ")}.`);
  }

  const avances = [...avancesState.slice(0, 4)];
  if (args.newEvent) {
    avances.unshift(args.newEvent);
  }
  if (recentEvents.length > 0) {
    for (const event of recentEvents) {
      if (!avances.includes(event)) {
        avances.push(event);
      }
    }
  }

  if (avances.length > 0) {
    lines.push(`Avances: ${avances.slice(0, 6).join("; ")}.`);
  }

  if (pendientes.length > 0) {
    lines.push(`Pendientes: ${pendientes.slice(0, 5).join("; ")}.`);
  }

  const draft = lines.join(" ").replace(/\s+/g, " ").trim();
  return trimWords(draft, 300);
}

function extractCriticalFragments(summary: string): string[] {
  const clean = `${summary ?? ""}`.trim();
  if (!clean) {
    return [];
  }

  const criticalKeywords = [
    "riesgo",
    "riesgos",
    "bloque",
    "dependencia",
    "token",
    "auth",
    "seguridad",
    "produccion",
    "staging",
    "decision",
    "decisiones",
    "pendiente",
    "incidencia",
    "falla",
    "error",
    "migracion",
  ];

  const segments = clean
    .split(/[\n\.\!\?]+/)
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

  const selected: string[] = [];
  for (const segment of segments) {
    const normalized = segment.toLowerCase();
    if (criticalKeywords.some((keyword) => normalized.includes(keyword))) {
      selected.push(segment);
    }
  }

  const fallback = selected.length > 0 ? selected : segments;
  const deduped: string[] = [];
  const seen = new Set<string>();
  for (const item of fallback) {
    const key = item.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      deduped.push(item);
    }
  }

  return deduped.slice(0, 3).map((item) => trimWords(item, 20));
}

function deepMerge(base: unknown, patch: unknown): any {
  if (Array.isArray(base) && Array.isArray(patch)) {
    const result: unknown[] = [];
    const seen = new Set<string>();

    for (const item of [...base, ...patch]) {
      const key = stableKey(item);
      if (!seen.has(key)) {
        seen.add(key);
        result.push(item);
      }
    }

    return result;
  }

  if (isPlainObject(base) && isPlainObject(patch)) {
    const result: Record<string, unknown> = { ...base };

    for (const [key, patchValue] of Object.entries(patch)) {
      const baseValue = (result as Record<string, unknown>)[key];
      (result as Record<string, unknown>)[key] = deepMerge(baseValue, patchValue);
    }

    return result;
  }

  if (patch === undefined) {
    return base;
  }

  return patch;
}

function stableKey(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableKey(entry)).join(",")}]`;
  }

  if (isPlainObject(value)) {
    const entries = Object.keys(value)
      .sort()
      .map((key) => `${key}:${stableKey((value as Record<string, unknown>)[key])}`);
    return `{${entries.join(",")}}`;
  }

  return JSON.stringify(value);
}

function readString(value: unknown): string {
  return `${value ?? ""}`.trim();
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => `${item ?? ""}`.trim())
    .filter((item) => item.length > 0);
}

function trimWords(text: string, maxWords: number): string {
  const words = text
    .split(/\s+/)
    .map((word) => word.trim())
    .filter((word) => word.length > 0);

  if (words.length <= maxWords) {
    return words.join(" ");
  }

  return `${words.slice(0, maxWords).join(" ")}...`;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 400, details?: unknown) {
  return jsonResponse({ ok: false, error: message, details }, status);
}
