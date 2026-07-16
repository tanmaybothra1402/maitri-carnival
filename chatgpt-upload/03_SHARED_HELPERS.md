BUNDLE 3 of 6 — SHARED EDGE-FUNCTION HELPERS. Contains 5 files.


################################################################################
# FILE: supabase/functions/_shared/auth.ts
################################################################################

import type { User } from "npm:@supabase/supabase-js@2";
import { serviceClient } from "./supabase.ts";

export function bearerToken(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Error("AUTH_REQUIRED");
  return match[1].trim();
}

export async function requireUser(request: Request): Promise<User> {
  const token = bearerToken(request);
  const client = serviceClient();
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("INVALID_OR_EXPIRED_SESSION");
  return data.user;
}

export async function requireAdmin(request: Request): Promise<User> {
  const user = await requireUser(request);
  if (String(user.app_metadata?.role ?? "") !== "admin") {
    throw new Error("ADMIN_REQUIRED");
  }
  return user;
}


################################################################################
# FILE: supabase/functions/_shared/cors.ts
################################################################################

function configuredOrigins(): string[] {
  return (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim().replace(/\/$/, ""))
    .filter(Boolean);
}

export function corsHeaders(request: Request): HeadersInit {
  const requestOrigin = (request.headers.get("origin") ?? "").replace(/\/$/, "");
  const allowed = configuredOrigins();
  const allowOrigin = allowed.length === 0
    ? "*"
    : allowed.includes(requestOrigin)
    ? requestOrigin
    : allowed[0];

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-sheet-sync-secret",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Expose-Headers": "content-type, content-length",
    "Vary": "Origin",
  };
}

export function optionsResponse(request: Request): Response {
  return new Response("ok", { headers: corsHeaders(request) });
}


################################################################################
# FILE: supabase/functions/_shared/http.ts
################################################################################

import { corsHeaders } from "./cors.ts";

export function jsonResponse(request: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object") {
    const value = error as Record<string, unknown>;
    const parts = [value.message, value.details, value.hint, value.code]
      .filter((part) => part !== undefined && part !== null && String(part).trim() !== "")
      .map((part) => String(part).trim());
    if (parts.length) return Array.from(new Set(parts)).join(" | ");
    try {
      return JSON.stringify(value);
    } catch (_) {
      return "Unknown structured error";
    }
  }
  return String(error ?? "Unknown error");
}

export function clean(value: unknown): string {
  return String(value ?? "").trim();
}


################################################################################
# FILE: supabase/functions/_shared/secure.ts
################################################################################

export function secureEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i += 1) diff |= aa[i] ^ bb[i];
  return diff === 0;
}


################################################################################
# FILE: supabase/functions/_shared/supabase.ts
################################################################################

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new Error("Supabase service environment variables are missing");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { "x-application-name": "maitri-office-exhibition" } },
  });
}

export function authClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!url || !key) throw new Error("Supabase auth environment variables are missing");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
