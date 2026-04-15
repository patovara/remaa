import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  base?: string;
  target?: string;
};

type CacheRow = {
  rate: number;
  provider: string;
  fetched_at: string;
  expires_at: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const exchangeApiBaseUrl = (Deno.env.get("EXCHANGE_RATE_API_BASE_URL") ?? "https://v6.exchangerate-api.com/v6").replace(/\/$/, "");
const exchangeApiKey = (Deno.env.get("EXCHANGE_RATE_API_KEY") ?? "").trim();
const cacheTtlMinutes = Number(Deno.env.get("EXCHANGE_RATE_CACHE_TTL_MINUTES") ?? "60");

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

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonError("Missing Supabase environment variables.", 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: RequestBody = {};
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    body = {};
  }

  const base = normalizeCurrencyCode(body.base, "MXN");
  const target = normalizeCurrencyCode(body.target, "USD");

  if (base === target) {
    return jsonError("base and target currencies must be different.", 400);
  }

  const cachedFresh = await findLatestRate(adminClient, base, target, true);
  if (cachedFresh) {
    return jsonResponse({
      ok: true,
      base,
      target,
      rate: cachedFresh.rate,
      provider: cachedFresh.provider,
      fetched_at: cachedFresh.fetched_at,
      fallback: false,
      source: "cache",
    });
  }

  const shouldAttemptExternal = exchangeApiKey.length > 0;
  if (shouldAttemptExternal) {
    const external = await fetchExternalRate(base, target);
    if (external.ok) {
      const now = new Date();
      const ttl = Number.isFinite(cacheTtlMinutes) && cacheTtlMinutes > 0 ? cacheTtlMinutes : 60;
      const expiresAt = new Date(now.getTime() + ttl * 60 * 1000);

      await adminClient.from("currency_rates_cache").insert({
        base_currency: base,
        target_currency: target,
        rate: external.rate,
        provider: external.provider,
        fetched_at: now.toISOString(),
        expires_at: expiresAt.toISOString(),
      });

      return jsonResponse({
        ok: true,
        base,
        target,
        rate: external.rate,
        provider: external.provider,
        fetched_at: now.toISOString(),
        fallback: false,
        source: "api",
      });
    }
  }

  const latestCached = await findLatestRate(adminClient, base, target, false);
  if (latestCached) {
    return jsonResponse({
      ok: true,
      base,
      target,
      rate: latestCached.rate,
      provider: latestCached.provider,
      fetched_at: latestCached.fetched_at,
      fallback: true,
      source: "cache_fallback",
    });
  }

  return jsonError(
    shouldAttemptExternal
      ? "No fue posible consultar tipo de cambio ni hay cache disponible."
      : "Missing EXCHANGE_RATE_API_KEY and no cache available.",
    502,
  );
});

async function findLatestRate(
  adminClient: ReturnType<typeof createClient>,
  base: string,
  target: string,
  onlyFresh: boolean,
): Promise<CacheRow | null> {
  let query = adminClient
    .from("currency_rates_cache")
    .select("rate, provider, fetched_at, expires_at")
    .eq("base_currency", base)
    .eq("target_currency", target)
    .order("fetched_at", { ascending: false })
    .limit(1);

  if (onlyFresh) {
    query = query.gt("expires_at", new Date().toISOString());
  }

  const { data, error } = await query.maybeSingle();
  if (error || !data) {
    return null;
  }

  return {
    rate: Number(data.rate ?? 0),
    provider: `${data.provider ?? "exchangerate-api"}`.trim(),
    fetched_at: `${data.fetched_at ?? ""}`.trim(),
    expires_at: `${data.expires_at ?? ""}`.trim(),
  };
}

async function fetchExternalRate(
  base: string,
  target: string,
): Promise<{ ok: true; rate: number; provider: string } | { ok: false }> {
  const url = `${exchangeApiBaseUrl}/${exchangeApiKey}/pair/${base}/${target}`;
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });

    if (!response.ok) {
      return { ok: false };
    }

    const payload = await response.json().catch(() => ({} as Record<string, unknown>));
    const result = `${(payload as Record<string, unknown>).result ?? ""}`.trim().toLowerCase();
    const rate = Number((payload as Record<string, unknown>).conversion_rate ?? 0);

    if (result !== "success" || !Number.isFinite(rate) || rate <= 0) {
      return { ok: false };
    }

    return { ok: true, rate, provider: "exchangerate-api" };
  } catch {
    return { ok: false };
  }
}

function normalizeCurrencyCode(value: string | undefined, fallback: string) {
  const normalized = `${value ?? ""}`.trim().toUpperCase();
  if (normalized.length < 3 || normalized.length > 5) {
    return fallback;
  }
  return normalized;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 400, details?: unknown) {
  return jsonResponse({ error: message, details }, status);
}
