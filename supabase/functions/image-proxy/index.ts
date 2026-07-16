import { corsHeaders, optionsResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

function bytesToHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha1Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  return bytesToHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message))).toLowerCase();
}

async function buildImageUrl(baseUrl: string, transformation: string): Promise<string> {
  const url = new URL(baseUrl);
  url.searchParams.delete("ik-s");
  url.searchParams.delete("ik-t");
  url.searchParams.set("tr", transformation);

  const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY") ?? "";
  if (!privateKey) return url.toString();

  const endpoint = (Deno.env.get("IMAGEKIT_URL_ENDPOINT") ?? "").replace(/\/$/, "");
  if (!endpoint) throw new Error("IMAGEKIT_URL_ENDPOINT_REQUIRED_FOR_SIGNING");

  const transformedUrl = url.toString();
  const endpointWithSlash = `${endpoint}/`;
  if (!transformedUrl.startsWith(endpointWithSlash)) {
    throw new Error("IMAGE_URL_DOES_NOT_MATCH_CONFIGURED_IMAGEKIT_ENDPOINT");
  }

  const expiry = Math.floor(Date.now() / 1000) + 300;
  const stringToSign = transformedUrl.slice(endpointWithSlash.length) + expiry;
  const signature = await hmacSha1Hex(privateKey, stringToSign);
  url.searchParams.set("ik-t", String(expiry));
  url.searchParams.set("ik-s", signature);
  return url.toString();
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    const user = await requireUser(request);
    const db = serviceClient();
    const body = await request.json().catch(() => ({}));
    const designNo = clean(body.designNo);
    const variant = clean(body.variant || "thumb").toLowerCase();
    if (!designNo) throw new Error("DESIGN_NO_REQUIRED");
    if (!['thumb', 'pdf'].includes(variant)) throw new Error("INVALID_IMAGE_VARIANT");

    const isAdmin = String(user.app_metadata?.role ?? "") === "admin";
    if (!isAdmin) {
      const { data: customer, error: customerError } = await db
        .from("customers")
        .select("active")
        .eq("id", user.id)
        .maybeSingle();
      if (customerError) throw customerError;
      if (!customer?.active) throw new Error("CUSTOMER_ACCESS_DISABLED");
    }

    const { data, error } = await db
      .from("designs")
      .select("design_no,active,design_assets(base_image_url)")
      .eq("design_no", designNo)
      .maybeSingle();
    if (error) throw error;
    if (!data || !data.active) throw new Error("ACTIVE_DESIGN_NOT_FOUND");

    const asset = Array.isArray((data as any).design_assets)
      ? (data as any).design_assets[0]
      : (data as any).design_assets;
    const baseUrl = clean(asset?.base_image_url);
    if (!baseUrl) throw new Error("IMAGE_NOT_AVAILABLE");

    const transformation = variant === "pdf"
      ? Deno.env.get("IMAGEKIT_PDF_TRANSFORMATION") ?? "w-320,h-430,c-at_max,q-30,f-jpg"
      : Deno.env.get("IMAGEKIT_THUMB_TRANSFORMATION") ?? "w-240,h-320,c-at_max,q-50,f-auto";

    const upstreamUrl = await buildImageUrl(baseUrl, transformation);
    const upstream = await fetch(upstreamUrl, {
      headers: { "User-Agent": "MaitriOfficeExhibitionImageProxy/1.0" },
      redirect: "follow",
    });
    if (!upstream.ok || !upstream.body) {
      throw new Error(`IMAGEKIT_FETCH_FAILED_${upstream.status}`);
    }

    return new Response(upstream.body, {
      status: 200,
      headers: {
        ...corsHeaders(request),
        "Content-Type": upstream.headers.get("content-type") ?? "image/jpeg",
        "Cache-Control": "private, max-age=300",
        "Content-Disposition": "inline",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : message.includes("NOT_FOUND") ? 404 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
