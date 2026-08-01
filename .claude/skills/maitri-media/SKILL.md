---
name: maitri-media
description: Product images for the Maitri exhibition app — the rule that customers never see product images, ImageKit as the only host, the shared free-tier egress budget, client-side compression, and signed in-app uploads. Read before touching product photos or image display, adding image upload, changing where images are served, or when something is slow or hitting a quota.
---

# Maitri media — the image pipeline

Design photographs are the intellectual property at risk: this is a wholesale
garment exhibition and copying is the live threat. Two forces shape every decision
here — keeping those images away from buyers, and not blowing the shared free-tier
egress budget. Read this before writing anything that uploads or displays a
product image.

## 1. Customers never see product images

Not on screen, not in the sale-order PDF, not in any customer API response.
Customers get the design number, the category/style/fabric line, description and
quantity; because the exhibition is physical, the buyer is holding the garment, so
the image was never doing real work for them.

- No product `<img>` anywhere in `web/user.html`; none in the customer PDF.
- `order_state_json` and `lookup_barcode` return **no image field at all** — not a
  URL, not a key.
- The `design-image` Edge Function and its blur pipeline are **deleted**; any
  reference to them is dead code.
- A `grant select` on a table with image URLs to `authenticated` leaks them to
  every customer (they are authenticated users). See `maitri-guardrails` §A1 —
  this exact leak shipped once.

Make `design_no` and the detail line visually dominant in the customer app — that
is how a buyer confirms they scanned the right thing.

## 2. ImageKit is the only image host (implementation detail)

Staff/admin images come from **ImageKit** — never Supabase Storage — whether the
image arrived via the Google Sheet or an in-app upload. `designs.image_url` holds
the ImageKit URL; no branching on origin.

**Why it must not be Supabase Storage:** the free tier gives **~10 GB/month egress
that is ORG-WIDE**, shared across the database, the Edge Functions, and Storage. A
few staff browsing a full-size product grid would exhaust it, and when it runs out
it is not images that break — it is the **whole project**: ordering stops
mid-event. ImageKit moves image bytes off that shared meter. Do not "simplify" by
moving images back to Storage.

## 3. Staff / admin paths keep full resolution

Staff and dispatch must identify goods, so admin screens show full-resolution
images — sourced from the **service-role admin API** (`listDesigns`), never from a
customer-reachable RPC. Grids and detail views differ:

- **grids** use a width transform: `?tr=w-300`
- **detail views** use the full image

## 4. Uploads are signed; the private key never reaches the browser

In-app capture (Brief 5) uploads **directly** from the browser to ImageKit using a
short-lived token **issued by an Edge Function**. The ImageKit private key lives
only in Edge Function secrets and must never appear in `web/*.html` or any client
bundle. The returned URL is stored on the `designs` row.

## 5. Compress client-side before upload

A 3 MB phone photo must leave the browser at roughly **250 KB**:

- resize to **~1400px on the longest edge**
- **JPEG quality ~75** via a `<canvas>`

Exhibition wifi is unreliable: show upload progress, retry on failure, and allow
saving a product **without** a photo to attach later.

## See also

- `maitri-architecture` — the hub; image privacy among the other load-bearing rules.
- `maitri-orders` — order/sale screens where admin images appear and customer ones must not.
- `maitri-frontend` — the capture/upload UI, canvas compression, and verifying it.
- `maitri-sheet-sync` — image URLs arriving via the Google Sheet import.
- `maitri-guardrails` — §A1 the `authenticated` image-URL leak; review before deploying.
