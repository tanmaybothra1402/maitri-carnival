// Customer-facing design image proxy.
//
// Customers never receive designs.image_url. They receive a design number and
// fetch bytes from here. This function resolves the master URL server-side,
// forces a medium-blur low-resolution transformation, and streams back JPEG
// bytes only. The master path is never returned, never echoed in a header, and
// never accepted as input, so there is nothing in the browser to sharpen.
//
// Threat model, stated plainly: the bytes served here are the same degraded
// bytes already visible on screen, so this endpoint is not a secret. It exists
// to remove the master URL from the client, not to gate access to thumbnails.
//
// Deployed with verify_jwt = false because <img src> cannot send an
// Authorization header.

import { optionsResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

// Soft blur. The design must stay clearly identifiable at thumbnail size —
// the customer has to confirm they ordered the right thing — while embroidery,
// print detail and stitching do not survive being zoomed.
// Higher width + lower blur = recognisable; low quality still kills fine detail.
const CUSTOMER_TRANSFORM = "w-260,q-45,bl-3,f-jpg";
const PDF_TRANSFORM = "w-220,q-40,bl-2,f-jpg";

const DESIGN_NO = /^[A-Za-z0-9][A-Za-z0-9._\-\/ ]{0,63}$/;
const CACHE = "public, max-age=86400, immutable";

function applyTransform(raw: string, tr: string): string {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return "";
  }
  // Replace any existing transform rather than appending, so a master URL that
  // already carries a high-quality tr= cannot win.
  url.searchParams.set("tr", tr);
  return url.toString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse(req);
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const url = new URL(req.url);
    const designNo = (url.searchParams.get("d") ?? "").trim();
    const variant = url.searchParams.get("v") === "pdf" ? PDF_TRANSFORM : CUSTOMER_TRANSFORM;

    if (!designNo || !DESIGN_NO.test(designNo)) {
      return new Response("Bad request", { status: 400 });
    }

    const db = serviceClient();
    const { data, error } = await db.rpc("design_image_source", {
      p_design_no: designNo,
    });
    if (error) throw error;

    const master = typeof data === "string" ? data.trim() : "";
    if (!master) return new Response("Not found", { status: 404 });

    const src = applyTransform(master, variant);
    if (!src) return new Response("Not found", { status: 404 });

    const upstream = await fetch(src, {
      headers: { accept: "image/jpeg,image/*" },
    });
    if (!upstream.ok || !upstream.body) {
      return new Response("Upstream unavailable", { status: 502 });
    }

    // Deliberately do not forward upstream headers; some CDNs echo the origin
    // path in x-ik-* or link headers.
    return new Response(upstream.body, {
      status: 200,
      headers: {
        "content-type": "image/jpeg",
        "cache-control": CACHE,
        "x-content-type-options": "nosniff",
        "referrer-policy": "no-referrer",
        "access-control-allow-origin": "*",
      },
    });
  } catch (_err) {
    return new Response("Image unavailable", { status: 500 });
  }
});
