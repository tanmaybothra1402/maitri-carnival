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
