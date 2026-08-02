---
name: maitri-architecture
description: The hub for the Maitri/EKUM exhibition ordering app (Supabase + single-file static HTML) — the load-bearing rules and the map to every branch skill. Read this BEFORE designing any feature, so you know which choke point owns your change and which branch skill to open next. Covers auth, the permissions module checklist, barcodes, and where logic belongs.
---

# Maitri exhibition app — architecture hub

Wholesale garment-exhibition ordering. Parent brand **EKUM**, firms **Maitri** and
**Niharika**. Customers register, get checked in at a gate, scan barcodes to build
per-firm orders, and edit within a time window. Staff run reception, sales,
products, dispatch and admin from a separate console.

Stack: Supabase (Postgres + RLS + Auth + Edge Functions in Deno/TypeScript) and
**single-file static HTML pages on GitHub Pages**. No build step. `supabase-js`
from CDN. Deliberate — the apps must be editable and deployable by one person under
event pressure.

**This is the hub.** It holds the rules that cross every module and points you at
the branch that owns the detail. Read it first, then open the branch for what you
are building.

## The branch map

```
CLAUDE.md                 router, always loaded
└── maitri-architecture   ← you are here — read before designing anything
    ├── maitri-orders     write path, merge-safety, dispatch lock, multi-customer batching
    ├── maitri-media      ImageKit, the shared egress budget, signed uploads, no customer images
    └── maitri-frontend   single-file HTML conventions + the verification suite
    plus: maitri-migration · maitri-sheet-sync · maitri-deploy · maitri-guardrails (GATE)
```

| If your change touches… | Own it in… |
|---|---|
| creating/editing/saving/batching/locking orders, `_write_order` | `maitri-orders` |
| product images, uploads, ImageKit, what customers can see | `maitri-media` |
| `web/*.html`, paste-in JS, CSS, client verification | `maitri-frontend` |
| schema, RPCs, grants, CHECK constraints | `maitri-migration` |
| the Google Sheet mirror, bulk imports | `maitri-sheet-sync` |
| shipping, "my fix isn't showing up" | `maitri-deploy` |
| reviewing a diff before deploy | `maitri-guardrails` |

## The choke points (summary — detail in the branches)

1. **One order write path.** Every order write goes through `public._write_order`.
   One function, not one per actor — so the dispatch lock, edit window and order
   lock are each written once. Detail, operation-list semantics, and multi-customer
   batching: **`maitri-orders`**.
2. **Customer writes are `SECURITY DEFINER` RPCs, never direct table access.**
   Customers are authenticated Supabase users, so a `grant … to authenticated`
   hands the table to every buyer — this leaked the master image catalogue once.
   Route reads through definer functions. See §permissions below and
   `maitri-guardrails` §A.
3. **Image privacy and the egress budget** own a whole branch: **`maitri-media`**.
   Customers see no images; ImageKit is the only host; admin keeps full resolution.
4. **Server-side aggregation for dashboards.** ~300 customers × thousands of line
   items — aggregate in Postgres (`admin_dashboard_v2`, `admin_dispatch_detail`),
   never in the browser.

## Permissions: granular in the DB, grouped in the UI

`staff_profiles.permissions` is JSONB with granular keys (`sale.write`,
`dispatch.view`, `products.mapping`, …). The Team UI shows **module toggles**
(Reception / Sales / Products / Dispatch / Dashboard / Admin) expanded via `GROUPS`
in `admin-api`.

Every admin action is gated at **one** choke point,
`requireActionPermission(context, action)` against `ACTION_PERMISSIONS`. An action
missing from that map is **unprotected**. Always add both.

**Adding a module changes FIVE things or staff creation breaks:**

1. `ACTION_PERMISSIONS` entries for the new actions
2. `GROUPS` + `collapseGroups` + `ALL_PERMISSIONS` + `PRESET_PERMISSIONS` in `admin-api`
3. `allowedSections` **and** `modulePermission` in `createStaff` *and* `updateStaff`
4. The `staff_profiles.preset` and `default_section` CHECK constraints (migration)
5. `TEAM_GROUPS`, the nav item, `moduleAllowed()`, and the default-section
   `<select>` options in the HTML

Missing #3 drops the person on a section they cannot access. Missing #4 rejects
every staff save with a constraint violation. The bottom nav uses fixed
`grid-column` positions and re-flows at login to the modules the person can see.
This checklist applies to new permissions too (e.g. `products.create`,
`admin.exhibitions`).

## Auth: hidden emails

- Customers: `c<phone>@accounts.<event-domain>`
- Staff: `<staffid>@staff.<event-domain>`
- Admins: real email addresses

Role lives in `app_metadata.role` (`admin` | `staff`) — never in user metadata,
which users can edit. Sessions persist with **separate storage keys** for the
customer and team apps, so a shared counter tablet can hold both. Never call a
destructive `signOut()` on a transient error — refresh the token and retry once.
Deactivating staff takes effect immediately (permissions re-read per request); but
**granting** a module needs a page reload — the nav was rendered at login.

## Barcodes are physical objects

A printed sticker maps to exactly one design, one way. `admin_map_barcode` refuses
to re-point an **active** mapping (`BARCODE_ALREADY_MAPPED|<barcode>|<design>`); to
reuse a sticker, deactivate the mapping first. Client-side checks mirror this for
instant feedback, but the database is the real boundary — the batch path and stale
pages hit the same function.

**Barcode mappings are GLOBAL, not per-exhibition.** `barcode_mappings` has PK
`(barcode)` and no `exhibition_id`; `lookup_barcode` / `admin_map_barcode` /
`admin_deactivate_barcode` take no exhibition. Designs are global, so a barcode
that names a design is global too, and there is ONE physical sticker run shared
across every exhibition. They were briefly scoped per-exhibition (Brief 3.6, to
allow reprinting a per-event set) and reverted once the stickers became a single
shared run (migration `202608010011`). **Do not re-scope them** — the one-way guard
is now genuinely global, and re-adding `exhibition_id` would fragment a barcode
across events for no reason.

## Units

`pieces = sets × pcs_per_set`. Customers order in **sets**; `pcs_per_set` is
snapshotted onto the order line so later catalogue edits never change a placed
order. Default 4. (Detail in `maitri-orders`.)

## File map

| Concern | File |
|---|---|
| Customer app | `web/user.html` |
| Admin console | `web/admin-<random>.html` (unguessable name; auth is the real boundary) |
| Customer auth | `supabase/functions/customer-auth/index.ts` |
| All admin actions | `supabase/functions/admin-api/index.ts` |
| Sheet mirror | `supabase/functions/data-sync/index.ts` |
| Schema | `supabase/migrations/` (cumulative, numbered) |
| Sheet menu | `apps-script/DataSync.gs` |
| Barcode sheets | `scripts/make-qr-sheets.js` |

## Working style (summary)

- **Trace every caller before changing a shared function.** `lookup_barcode` served
  customer and admin; `downloadAdminOrderPdf` was called directly and as an event
  handler. Both broke when changed for one caller. This is the most common way this
  codebase breaks — `maitri-guardrails` §C.
- Prefer `create or replace` migrations that restate the whole function —
  `maitri-migration`.
- HTML verification is mandatory and mechanical — `maitri-frontend` and
  `maitri-guardrails` §F.
- Errors say what to do next, not name a code.

## See also

- `maitri-orders` — the order write path and multi-customer batching.
- `maitri-media` — images, ImageKit, the egress budget, customer-image privacy.
- `maitri-frontend` — single-file HTML conventions and the verification suite.
- `maitri-migration` — schema/RPC/grant house style and the CHECK constraints.
- `maitri-sheet-sync` — the Google Sheet mirror and bulk imports.
- `maitri-deploy` — shipping, cache-busting, the production check list.
- `maitri-guardrails` — the GATE; review every diff against real shipped bugs before deploying.
