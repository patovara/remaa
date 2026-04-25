import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type BuildMemoryContextInput = {
  project_id?: string;
  user_input?: string;
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

  let input: BuildMemoryContextInput;
  try {
    input = (await req.json()) as BuildMemoryContextInput;
  } catch {
    return jsonError("Invalid request body.", 400);
  }

  const projectId = `${input.project_id ?? ""}`.trim();
  const userInput = `${input.user_input ?? ""}`.trim();

  if (!projectId) {
    return jsonError("project_id is required.", 400);
  }

  if (!userInput) {
    return jsonError("user_input is required.", 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const [{ data: stateRow, error: stateError }, { data: summaryRow, error: summaryError }] = await Promise.all([
    adminClient.from("memory_state").select("state").eq("project_id", projectId).maybeSingle(),
    adminClient.from("memory_summary").select("summary").eq("project_id", projectId).maybeSingle(),
  ]);

  if (stateError || summaryError) {
    return jsonError("Failed to load memory context.", 500, {
      stateError: stateError?.message,
      summaryError: summaryError?.message,
    });
  }

  if (!stateRow || !summaryRow) {
    return jsonError("Memory context not found for project_id.", 404);
  }

  const state = (stateRow.state ?? {}) as Record<string, unknown>;
  const summary = `${summaryRow.summary ?? ""}`.trim();

  const systemPrompt = [
    "SYSTEM:",
    "Eres un asistente técnico.",
    "Solo puedes usar STATE y SUMMARY.",
    "Si falta información, pregunta.",
    "",
    "STATE:",
    JSON.stringify(state, null, 2),
    "",
    "SUMMARY:",
    summary,
  ].join("\n");

  const userPrompt = ["USER:", userInput].join("\n");

  return jsonResponse({
    system_prompt: systemPrompt,
    user_prompt: userPrompt,
  });
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 400, details?: unknown) {
  return jsonResponse({ ok: false, error: message, details }, status);
}
