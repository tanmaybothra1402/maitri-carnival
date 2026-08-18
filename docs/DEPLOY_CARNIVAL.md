# Maitri Carnival 2026 - Deploy runbook

Production project: `ezmtiiftolcaslqfvozu`

The current build consists of two static pages, cumulative database migrations, four Edge Functions, and the Google Sheets mirror.

> ## ⛔ BLOCKING PREREQUISITE — before you create a SECOND exhibition
>
> The customer app now resolves its exhibition from the URL (`?e=<slug>`), with
> `is_current` as the bare-URL fallback (migration `202608010003`). While only
> one exhibition exists everything works unchanged. **The moment a second
> `exhibitions` row exists, two things break silently unless already handled:**
>
> 1. **`customer-auth` must pass the slug.** With two or more exhibitions, a
>    registration that does not carry `exhibition_slug` raises
>    `EXHIBITION_SLUG_REQUIRED`. The current `customer-auth` build passes it —
>    do **not** run an older build alongside a second exhibition, or all
>    registration fails.
> 2. **`admin_map_barcode` / `admin_deactivate_barcode` must be scoped to a
>    passed exhibition id.** They still call `current_exhibition_id()`, so until
>    they take an explicit id, admin barcode mapping/deactivation **silently
>    targets whichever exhibition is `is_current`**, regardless of any admin
>    selector — stickers get mapped into the wrong event.
>
> Create the second exhibition only after both are deployed.

## Active files

- Customer app: `web/user.html`
- Admin console: `web/admin-a106dc80eeabd658.html`
- Database: `supabase/migrations/`
- Customer registration/login: `supabase/functions/customer-auth/index.ts`
- Admin service operations: `supabase/functions/admin-api/index.ts`
- Full Sheet mirror: `supabase/functions/data-sync/index.ts`
- Legacy product importer: `supabase/functions/sheet-sync/index.ts`
- Google Apps Script: `apps-script/DataSync.gs`

## 1. Apply cumulative migrations

From the repository root:

```bash
npx supabase db push
```

The latest migration is:

```text
supabase/migrations/202608010013_fix_malformed_barcodes.sql
```

`202608010013` (2026-08-17) repairs four active `barcode_mappings` rows that could
never match a printed sticker — a **data-only** migration (no functions, no grants,
no HTML). It is idempotent (guarded `is distinct from` / `not exists`, re-runnable):
- `MC- 0941` (embedded space) → **deactivated** (a clean `MC-0941` already maps the
  same design NRK-8900; renaming would collide).
- `MC- 0954` (embedded space) → **renamed** to `MC-0954` (no clean row existed).
- `MC-0837` → **deactivated** (its target design MR-8842 is inactive).
- `MC-01` → **left untouched on purpose** (not a 4-digit sticker; intended value
  unknown — do not guess or delete).

Post-apply invariants (all returned 0 rows on 2026-08-17): no active mapping has
whitespace in its barcode; none fails `^[A-Z]{2}-[0-9]{4}$` except the intentional
`MC-01`; none points at an inactive design.

`202608010014` (2026-08-17) normalises malformed **design numbers** toward
`XX - NNNN` / `XX - NNNN (B)`. Data-only, idempotent, no functions/grants/HTML.
It touches only the **9 inert** rows (0 active barcodes / 0 order_items / 0
dispatch_lines): deactivates 4 malformed members whose canonical twin already
exists (`MR - 4281 B`, `MR -  4349`, `MR -  4396`, `NRK -8531`) and renames 5
inert orphans (`MR - 3574 B`→`(B)`, `MR - 4374 ( B )`→`(B)`, `MU  - 0312`,
`NRK -8876`, `NRk - 8890`). **12 non-inert malformed rows are deliberately left
alone** — they carry live barcodes/orders, one carries a dispatch line, and
`design_no` renames cascade to order_items/barcode_mappings but **not**
dispatch_lines — so `noncanonical_active` is 12, not 0, by design. Those 12 need
a human dedup decision. Canonical-collision groups are now **0**.

`202608010015` + `202608010016` (2026-08-17) add the **CRM module** (buyer
screening before first billing). 015 is the schema/RPCs/permissions; 016 is the
customer column/table privacy lockdown (must ship together). This checkpoint ALSO
redeploys `admin-api` (new nav/permission wiring + 8 CRM actions) and the admin
HTML (CRM screen + reception flag banner). Deploy order: **both migrations, then
`npx supabase functions deploy admin-api --no-verify-jwt`, then the HTML.** The new
`crm` permission module (crm.view/write/assign) was backfilled to administrators
only — grant other staff crm.* through Admin → Team. Rejected buyers show a red
"Flagged — question before allowing entry" banner at reception; the check-in button
stays enabled (flag, not gate).

`202608010017` (2026-08-17) moves the 8 CRM fields **off** `customers` into a 1:1
`public.customer_crm` table (RLS on, no policies, no grants to authenticated/anon).
This kills the column-grant fragility: with no CRM columns on `customers`, table-wide
SELECT is restored to `authenticated` and `select *` is safe again. **UPDATE stays
column-scoped to the 6 profile fields** (`company_name, contact_name, city, state,
agent, gstin`) — never restored table-wide, so a buyer can't write
`active`/`checked_in_at`/`edit_deadline`/`exhibition_id`. One atomic migration:
create table → backfill (asserted 1075 = 1075 before the drop) → rewrite the 6 CRM
RPCs + `admin_directory` to LEFT JOIN `customer_crm` with `coalesce(crm_status,
'pending')` and upsert-on-write → drop the 8 columns → restore SELECT. **Migration
only — no Edge or HTML change** (RPC signatures + JSON shapes unchanged). The
`user.html` explicit-column select from the hotfix is kept as defense in depth.

`202608010018` (2026-08-17) — CRM refinements. Token/reference become standalone
customer attributes (`crm_set_reference_flag`, `crm_set_token`) — removed from
`crm_log_call` (**signature change**, drop-then-recreate). `crm_set_status` gains a
required-when-rejected reason (**signature change**); `customer_crm.status_reason`
added and surfaced in the reception flag banner (reason + who + when).
`customer_calls.followup_at` added; `crm_log_call` requires it when
outcome='callback'. New `crm_bulk_assign` / `crm_bulk_set_buyer_type` (one txn, one
log row per customer). `crm_list_customers` returns call_count / last_call_at /
order_line_count and supports withOrders + callbacksDue filters and a queue sort;
the CRM list defaults to **customers with orders**. This checkpoint redeploys
`admin-api` (4 new actions + changed crmLogCall/crmSetStatus) and the admin HTML
(list bulk-select + inline buyer-type, restructured detail card, fixed checkbox
labels). No customer-facing change.

`202608010023` (2026-08-18) — `crm.bulk` key gates the three mass-edit actions
(`crm_bulk_assign` / `crm_bulk_set_buyer_type` / `crm_bulk_set_tier`). admin-api:
`crm.bulk` in ALL_PERMISSIONS but **excluded from GROUPS.crm and from the
manager/administrator presets** (so ticking CRM never grants it); the 3 bulk
actions re-gated onto `crm.bulk`; coherence guard also drops `crm.bulk` without
`crm.view`; createStaff/updateStaff carry a `crmBulk` sub-toggle. HTML: a nested
**Bulk edits** sub-toggle under the CRM module (plus the CRM module's missing
`<input>` / ORDER / SECTION editor entries — 021 added the data but not the form
control, so editing staff still wiped CRM); CRM list hides checkboxes / select-all
/ bulk bar / inline New-Regular + A/B/C for non-bulk staff; per-customer tier
control added to the detail card so `crm.write` keeps single-customer editing.
Migration backfills `crm.bulk` to exactly two accounts (`tanmaybothra1402-2fb5`,
`ganesh`) and aborts if that count isn't 2. Redeploys admin-api + HTML.
NOTE: applied via MCP `apply_migration` (which stamps a 14-digit CLI-timestamp
version); the ledger version was reconciled back to this 12-digit house number by
an UPDATE to `supabase_migrations.schema_migrations` preserving `statements`.

`202608010022` (2026-08-18) — tier-first ordering on every customer list, in SQL
before the LIMIT (sorting after a cap silently drops A-tier off the page).
`crm_list_customers`: tier rank is the default primary, explicit Call queue /
Callback sorts still win with tier as tiebreak. `admin_directory` (Reception +
Sale search): tier-first, created_at desc tiebreak. **New `admin_dispatch_orders`
RPC** backs listDispatch — the old PostgREST path had a 300-row cap against 486
dispatchable orders and couldn't sort by the nested `customer_crm.tier`; ordering
+ search moved into SQL. Dashboard RPCs left as metric/recency order by design
(no plain customer roster; tier badge already renders). Redeploys admin-api + HTML.
Same 14→12-digit ledger reconciliation as 023 (see note there). No customer-facing change.

`202608010021` (2026-08-17) — permission-coherence fix. `crm.assign` moved from
the Admin group to the CRM module (admin-api GROUPS.crm + PRESET_PERMISSIONS.crm +
staff_permission_defaults 'crm' preset + a **new CRM checkbox in the staff editor**
— the CRM module was missing from Admin → Team entirely, so editing any staff
wiped crm.view/write). All three CRM keys now move together. admin-api
createStaff/updateStaff gained a server-side coherence guard that drops crm.assign
when crm.view is false. Seed-only migration — no live staff change. (Flagged:
`products.create` has the same admin-tier cross-grant shape; left as-is pending a
decision.) Redeploys admin-api + HTML.

`202608010020` (2026-08-17) — customer tier (A/B/C, NULL=unranked) on
`customer_crm` (NOT customers — kept behind the buyer-invisible wall). New
`crm_set_tier` / `crm_bulk_set_tier`; six readers extended to return tier
(crm_list_customers, crm_customer_detail, admin_directory, admin_dispatch_detail,
admin_dashboard_v2, admin_dashboard_drill_v1); admin-api gains crmSetTier /
crmBulkSetTier + tier in the listDispatch orders join. HTML shows ONE shared
`tierBadge()` beside the company name on CRM/Reception/Dispatch/Dashboard/Sale,
inline A/B/C + bulk + tier filter/sort in CRM. Also **fixes a 019 bug**:
crm_list_customers filtered buyer_type on ('new','old') so the "Regular buyer"
filter returned zero rows — now ('new','regular'). Redeploys admin-api + HTML.
Tier is unreachable from a customer session (customer_crm 42501; dashboard readers
guard staff-only on their first statement). No customer-facing change.

`202608010019` (2026-08-17) — buyer_type value `old` → `regular` (constraint +
crm_set_buyer_type / crm_bulk_set_buyer_type restated; 0 live rows to migrate;
customer_crm_log audit history deliberately left intact). This checkpoint also
redeploys `admin-api` (assign picker now lists ALL active staff with a "no CRM
access" marker, not only crm.view holders) and the admin HTML: `old`→`regular`
labels, and a **screen-density pass** — CRM description/4 filter rows collapsed
into a search + Filters bottom-sheet (chrome 491→165px at 390×844, 2→4 cards);
Reception header trimmed (508→374px); an app-wide `main.page` bottom padding so
the last row always clears the 7-item nav + Sale FAB. No customer-facing change.

Migrations `202608010001`–`202608010009` are the multi-exhibition build. In order:

| Migration | What it does |
|---|---|
| `…0001` | `exhibitions` table; `exhibition_id` (NOT NULL) on customers/orders/slots/barcode_mappings; scoped `lookup_barcode`, `admin_dashboard_v2`, registration trigger. |
| `…0002` | Removes the image field from `order_state_json` and `lookup_barcode` (customers see no product images). |
| `…0003` | URL-scoped exhibitions: `handle_new_auth_user` resolves the exhibition from the login-email slug, with the 1-exhibition silent fallback and the ≥2 `EXHIBITION_SLUG_REQUIRED` rule. |
| `…0004` | Scopes `admin_map_barcode` / `admin_deactivate_barcode` to a passed `exhibition_id` (composite PK `(barcode, exhibition_id)`). |
| `…0005` | Exhibition management RPCs (`admin_list_exhibitions`, atomic `admin_set_current_exhibition`, `barcode_functions_exhibition_scoped`). |
| `…0006` | Backfills `admin.exhibitions` onto existing admin-settings staff. |
| `…0007` | Adds `products.create`; backfills it onto product-editors. |
| `…0008` | Narrows `products.create` to admin-settings holders only. |
| `…0009` | Revokes `authenticated`/`anon` grants on `exhibitions` (service-role only). |

**Behaviour changes worth knowing before you run them:**

1. **Dispatch outranks `admin_unlocked`.** Reopening an order does not make a dispatched line editable — reduce its dispatched sets to 0 first. "Reopen the order" is not the universal fix.
2. **`select on public.designs` is revoked from `authenticated`** (verified still revoked — live grants are SELECT-only on customers/orders/order_items, all RLS-gated). Any client reading `designs` directly fails; route through an RPC or the service role.
3. **A second exhibition is gated** — see the BLOCKING PREREQUISITE box above. All the prerequisites it names are now deployed (`customer-auth` AUTH_CONTRACT 2, barcode functions scoped), so the console's Admin → Exhibitions → Create is safe to use.
4. **Permission keys are stored per-staff and do not auto-appear.** `admin.exhibitions` and `products.create` were backfilled by `…0006`/`…0007`/`…0008`; if you ever add another permission key in `admin-api`, existing staff will not see the feature until a backfill migration grants it (bootstrap returns the stored map, it does not re-expand the preset).

## 2. Deploy Edge Functions

```bash
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions deploy admin-api --no-verify-jwt
npx supabase functions deploy data-sync --no-verify-jwt
npx supabase functions deploy sheet-sync --no-verify-jwt
npx supabase functions list
```

`customer-auth`, `admin-api`, `data-sync`, and `sheet-sync` intentionally perform their own authentication/secret checks, so their `verify_jwt` setting is false in `supabase/config.toml`. **`design-image` is deleted** — do not redeploy it (customers get no product images).

Confirm the deployed secrets include:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SHEET_SYNC_SECRET`
- `ALLOWED_ORIGINS` containing the GitHub Pages origin
- `IMAGEKIT_PRIVATE_KEY`, `IMAGEKIT_PUBLIC_KEY`, `IMAGEKIT_URL_ENDPOINT` — required for in-app product photo upload (`admin-api signImageUpload`). **Set the public/private keys with matching values from the ImageKit dashboard; an expired or mismatched public key makes every upload 403 while the rest of the flow looks fine.** Set them quoted.

## 3. Retire the dead image proxy

The final app reads `designs.image_url` directly. The old image proxy references the dropped `design_assets` table and is unused.

```bash
npx supabase functions delete image-proxy
```

## 4. Update the Google Sheet mirror

1. Open the workbook's Apps Script project.
2. Replace its code with `apps-script/DataSync.gs`.
3. Save and reload the Sheet.
4. Run **Supabase Sync -> Test connection**.
5. Run **Supabase Sync -> Pull ALL tables**.

The Designs tab must now show `category`, `style`, `fabric`, and `pcs_per_set`. Fill valid `pcs_per_set` values before live ordering and push the Designs tab.

Legacy `color` columns are deliberately hidden. Customer colour instructions belong in `order_items.line_note`.

## 5. Publish the static pages

Commit and publish the contents of `web/` through GitHub Pages.

- Customer page: `web/user.html`
- Admin page: `web/admin-a106dc80eeabd658.html`

Keep the unguessable admin filename unchanged unless you also update the private admin link used by staff. Authentication remains the real security boundary.

## 6. Create visit slots

Log into the admin console, open **Slots**, and create the active windows for 19-21 July 2026. Capacity is optional.

## 7. Required production checks

1. Customer registration and login work without a platform missing-JWT error.
2. Team login is accepted only when `app_metadata.role` equals `admin` or `staff`.
3. Entry check-in unlocks customer ordering.
4. Two stale devices adding different designs preserve both additions.
5. Customer and Assisted admin adding different designs preserve both additions.
6. Explicit deletion removes only the selected design.
7. Same-design simultaneous changes resolve to the last completed save.
8. Notes persist after refresh and appear in admin detail and PDF.
9. Total pieces equals the sum of `sets x pcs_per_set`.
10. Sale-order PDF completes even when one product image cannot be fetched.
11. An expired order reopened by staff can be saved from the customer page.
12. Sheet deletes are unavailable on every mirrored tab.
13. A customer thumbnail is identifiable but its detail does not survive zooming.
14. `GET /rest/v1/designs?select=image_url` with a customer token returns a permission error, not data.
15. No `ik.imagekit.io` URL appears anywhere in the customer page's DOM or network tab.
16. Ticking a design in Dispatch prevents the customer from editing or deleting it.
17. Reopening a dispatched order still does not unlock the dispatched line.
18. Setting a dispatched line back to 0 sets restores normal editing.
19. Partial dispatch shows `Partial`; every line full shows `Completed`.
20. Mapping typeahead finds `MR-1234` from `1`, `12`, `123` and `1234`.
21. A batch of mappings saves in one call; failures stay queued, successes clear.
22. A dispatch-only staff member sees only the Dispatch tab, with no gap in the bottom bar.

### Multi-exhibition, multi-customer, bulk import, product create (this build)

These need real data and cannot be verified headlessly — run them against the live project.

23. **Selector visibility.** Only the three `admin.settings` holders see the app-bar exhibition selector and the Admin → Exhibitions sub-tab. Other staff see neither, and their scans/registrations still work (server resolves the current exhibition).
24. **Default to live.** The selector opens on the LIVE exhibition — green `LIVE` badge, no banner.
25. **Viewing a non-current exhibition** shows the amber "not the live event" banner, and Reception, Dashboard, Sale Order, Dispatch and Products → Mapping all re-scope to it. **Product Master stays global** ("· all events").
26. **Set-current** (Admin → Exhibitions) requires typing the exact exhibition name to confirm, flips the `LIVE` badge atomically, and new registrations/scans then land in the newly-live exhibition.
27. **Multi-customer existing quantities.** Select ≥2 customers, scan a design one already holds — the popup shows that customer's *current* sets ("Currently N"); a customer left unchanged is not re-written, and only edited totals are saved.
28. **Multi-customer partial failure.** Make one customer's save fail (e.g. a dispatched line). The others still save, failures are reported per customer, nothing rolls back. Re-saving the fixed ones does not double-apply (idempotent `request_id`).
29. **Multi-customer qty-0.** A selected customer left with no changes is never written — no empty order row, no 24-hour window started for them.
30. **Bulk barcode import** (Products → Mapping). Paste `templates/BarcodeMappings_Import.csv`: unknown/inactive designs and in-file duplicates are flagged per row, valid rows map, and an already-mapped barcode fails on its own line without aborting the file.
31. **New product with a photo.** Create a design with a photo → it lands in the ImageKit folder matching its prefix (`BS-DESIGN`, `NRK-DESIGN`, … or `App-Uploads`) and shows full-res on admin screens. Creating a `design_no` that already exists is rejected.
32. **New product without a photo** saves, and a photo can be attached afterwards. If the ImageKit key is misconfigured the create offers "save without photo" rather than losing the form.

## Event-day flow

1. Customer registers and saves their phone/password.
2. Customer optionally books a visit slot.
3. Staff searches the Entry directory and checks the customer in.
4. Customer scans Maitri and Niharika designs, enters sets and line notes, and saves.
5. The first successful save starts the account-wide edit window.
6. Every save merges its changed designs into the latest order, protecting unrelated concurrent changes.
7. Customer downloads a separate sale-order PDF for each firm.
8. Staff handles exceptions through Assisted ordering, password reset, customer control, and order reopening.

## Post-event

Registration is now controlled **per exhibition** (`exhibitions.registration_enabled`,
editable from Admin → Exhibitions). Close the one that ended, and lock only its
orders — not every exhibition's:

```sql
-- close registration for the exhibition that ended
update public.exhibitions
set registration_enabled = false
where slug = 'carnival-2026';

-- lock only that exhibition's still-open orders
update public.orders o
set status = 'Locked', admin_unlocked = false
where status <> 'Locked'
  and o.exhibition_id = (select id from public.exhibitions where slug = 'carnival-2026');
```

(The legacy `system_settings.registration_enabled` still exists for the
single-exhibition path; with multiple exhibitions the per-exhibition flag wins.)
