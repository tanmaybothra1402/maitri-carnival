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
