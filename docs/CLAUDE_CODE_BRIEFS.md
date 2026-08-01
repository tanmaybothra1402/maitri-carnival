# Claude Code briefs

Paste these into the Claude Code **Code** tab in order. Each is scoped to stop at
a checkpoint so you can verify before the next one starts.

**Rules that apply to every brief:**

- Turn OFF "Accept edits" before anything that touches the database.
- Never let it batch two briefs together.
- If it proposes SQL with `drop`, `alter` or `delete`, read it before approving.
- Free plan: no point-in-time recovery. The backup is the only safety net.

---

## Decisions already made — do not re-litigate

| Topic | Decision |
|---|---|
| Shared across exhibitions | `designs` only |
| Returning buyer | Registers fresh; old login **fails** |
| Catalogue per exhibition | No — all active designs everywhere |
| Barcode stickers | Reprinted and remapped per exhibition |
| `orders.exhibition_id` | Denormalised column, set from customer at insert |
| Customer images | **None anywhere** — no thumbnails, no PDF images |
| Blur pipeline | Delete `design-image` entirely |
| Image hosting | **ImageKit** for both sheet and in-app uploads |
| Multi-customer ordering | Unlimited customers, popup entry, sticky matrix |

---

## Brief 0 — Backup (BLOCKING)

```
Read CLAUDE.md, docs/MULTI_EXHIBITION_BLUEPRINT.md and docs/SETUP.md.

I have no working backup — Docker isn't installed and pg_dump failed on pooler
auth. Create one inside the database instead: a schema backup_20260801
containing a copy of every table in public. Then show me a table comparing row
counts, backup vs live, for every table.

Stop there. Do not create any new tables, do not alter anything, do not start
the migration. Wait for my confirmation that the counts match.
```

---

## Brief 1 — Build the skill branch structure

Do this before any feature work, so the features are built against it.

```
Read the existing skills in .claude/skills/ and CLAUDE.md.

Restructure into a hub-and-branch system with 8 skills. Create three new ones
and refactor maitri-architecture into a hub that cross-references them:

  CLAUDE.md                 router, always loaded
  ├── maitri-architecture   HUB — read before designing anything
  │   ├── maitri-orders     write path, merge-safety, multi-customer batching
  │   ├── maitri-media      image pipeline, ImageKit, free-tier egress budget
  │   └── maitri-frontend   single-file HTML conventions + verification
  ├── maitri-migration
  ├── maitri-sheet-sync
  ├── maitri-deploy
  └── maitri-guardrails     GATE — review before every deploy

maitri-orders must capture:
- _write_order is the ONLY write path; batches loop over it, never bypass it
- operation-list semantics (_op/_delete), merge-safety, request_id idempotency
- dispatch lock outranks admin_unlocked
- multi-customer saves: per-customer results, partial failure is normal,
  never write a customer whose qty is 0 (it would start their edit window)

maitri-media must capture:
- ImageKit is the ONLY image destination for both sheet and in-app uploads
- Supabase free tier: 10 GB/month egress is ORG-WIDE and shared with the
  database and Edge Functions. Serving images from Supabase Storage would
  compete with the app's own API traffic and take the whole project down when
  exhausted. This is why ImageKit was chosen.
- compress client-side before upload: ~1400px longest edge, JPEG q75
- grids use ?tr=w-300; detail views use full
- uploads are signed by an Edge Function; the ImageKit private key never
  reaches the browser
- customers see NO images anywhere

maitri-frontend must capture:
- single-file HTML, no build step, supabase-js from CDN
- verification: extract script blocks, node --check, confirm every $("id")
  resolves; drive behaviour with jsdom rather than reasoning about it
- paste-in snippets are bare JS, never wrapped in <script>
- grep a class name across the whole file before adding CSS — duplicate
  selectors have silently broken layouts
- errors must say what to do next, not name a code

Each skill's frontmatter description must be specific enough to trigger
reliably and not overlap with its siblings. Add a "See also" section to each
pointing at the related skills.

Stop when the 8 skills exist. Show me the tree and each description line.
```

---

## Brief 2 — Multi-exhibition Phase 1 + 2

Only after Brief 0's counts are confirmed.

```
Follow docs/MULTI_EXHIBITION_BLUEPRINT.md. Read maitri-migration and
maitri-architecture first.

Phase 1 and Phase 2 ship together — the migration changes function signatures
that admin-api calls, so deploying one alone breaks the console.

Write the migration but DO NOT APPLY IT YET. Show me:
1. The full SQL
2. Which functions change signature, and every caller of each
3. The verification queries that prove the backfill was complete

I'll review, then tell you to apply.

After applying, re-run the row counts from Brief 0 and show me before/after.
Any difference means stop and restore from backup_20260801.
```

---

## Brief 3 — Remove customer images

Small, do it right after the migration settles.

```
Read maitri-media and maitri-frontend first.

Customers must see NO product images anywhere — not in the order list, not in
the sale-order PDF. Images are internal only.

1. Strip all <img> and image fetching from web/user.html, including the PDF
2. Delete supabase/functions/design-image/ and its config.toml entry
3. Remove the imageKey plumbing from order_state_json and lookup_barcode
   (migration — keep admin paths at full resolution)
4. Make design_no and the category/style/fabric line visually dominant in both
   the order list and the PDF, since they're now the only identifiers

Then run the maitri-frontend verification suite and show me the results.
```

---

## Brief 4 — Multi-customer ordering

The big admin feature.

```
Read maitri-orders and maitri-frontend first.

A salesperson selects multiple customers and builds their orders together.

Flow:
- Select N customers (unlimited) in Sale Order
- Scan a barcode once
- Popup appears listing every selected customer VERTICALLY, each with a qty
  box defaulting to 0, arrows and typed entry
- Save adds the design to each customer with qty > 0
- The cart below is a matrix: rows = designs, columns = customers

Non-negotiable:
- Batch = a loop over admin_save_order_with_actor, one call per customer.
  Never write a new bulk order writer.
- Partial failure is normal. Report per-customer results, don't roll back
  the successes.
- Never write a customer whose qty is 0 — it would start their 24h edit window
  for nothing.
- Matrix: sticky design column, sticky customer header, a consistent colour per
  customer across popup and matrix.
- Editing a matrix cell REOPENS the popup rather than editing in place, so all
  quantity entry happens in the vertical view where nothing is scrolled off.
- Confirmation summary before save: "Sharma: 12 designs / 48 sets · Gupta: 5/20"

Show me the UI plan before building it.
```

---

## Brief 5 — In-app product capture

```
Read maitri-media first — especially the egress reasoning.

Staff must be able to add a product from the app: take a photo with the camera
or pick from the gallery, fill in the details, save.

Requirements:
- Images go to ImageKit, NOT Supabase Storage. An Edge Function issues a signed
  upload token; the browser uploads directly; the returned URL is stored on the
  design. The ImageKit private key never reaches the browser.
- Compress client-side before upload: ~1400px longest edge, JPEG q75 via canvas.
  A 3 MB phone photo must become ~250 KB.
- Exhibition wifi is unreliable: show upload progress, retry on failure, and
  allow saving a product WITHOUT a photo to attach later.
- Validate design_no against existing designs before saving — staff creating
  products on the floor will otherwise silently overwrite a sheet-imported one.
- New permission products.create. Adding it means the five-point module
  checklist in maitri-architecture applies.

Show me the plan and the ImageKit auth flow before building.
```

---

## Brief 6 — Final review

```
Run maitri-guardrails against everything changed since the multi-exhibition
migration. Report BLOCKER / HIGH / MEDIUM / LOW / VERIFIED CORRECT.

Pay particular attention to:
- shared functions whose callers changed
- anything granted to `authenticated`
- module lists that must be updated in five places
- the verification suite in maitri-frontend

Then update docs/DEPLOY_CARNIVAL.md with the new production checks.
```
