# Maitri × Niharika Exhibition System — Stress Test Report

**Author:** Claude (Cowork)
**Date:** 16 July 2026
**Target:** `maitri-carnival` (Supabase project ref `ezmtiiftolcaslqfvozu`), GitHub Pages `https://tanmaybothra1402.github.io/maitri-carnival/`
**Event window:** 19–21 July 2026
**Report type:** Static / code-derived audit. Live runtime execution deferred (see Scope limitation).

---

## Executive summary

The system is well-architected for its purpose. The security spine — least-privilege grants, RLS on every table, customer writes funnelled exclusively through audited `SECURITY DEFINER` RPCs, and admin actions gated behind a service-role Edge Function — is sound on inspection. The `save_my_order` concurrency and idempotency design correctly handles the multi-device and repeated-save cases.

The findings that matter for launch are **not** data-breach class. They are (a) an operational reliability regression in the PDF path introduced when `image-proxy` was removed, (b) an open-registration / abuse surface that is wider than it looks because customer creation runs through a service-role call, (c) a small number of things that can only be *confirmed* live and would be launch-blocking if misconfigured, and (d) leftover/dead code from the two rounds of updates. No confirmed Critical (auth bypass or cross-customer data leak) was found by static analysis; several items are marked **Critical-to-verify** because code alone cannot close them.

**Headline counts:** 0 confirmed Critical · 2 Critical-to-verify · 4 High · 5 Medium · 6 Post-event.

---

## Scope limitation (read this first)

This report is based on complete static analysis of every migration, Edge Function, shared module, the three web clients, the Apps Script sync, and configuration. **Live execution against the Supabase project was not possible from the analysis environment** — its outbound network is restricted to a package-registry allow-list, so the project host (`ezmtiiftolcaslqfvozu.supabase.co`) is unreachable. Accordingly:

- Sections 1, 2 (audits) and the logic analyses in 3–7 are **complete and code-verified**.
- Every claim that depends on runtime behaviour (actual RLS enforcement, real concurrency outcomes, live CORS, image byte sizes, latency percentiles, error rates) is marked **PENDING LIVE** with the exact procedure and pass criteria to confirm it.
- Section 8 (load) is a **plan with thresholds**, not measured metrics.

The `.env.production` file was inspected for configuration correctness only; no secret value is reproduced anywhere in this report.

---

## 1. Static architecture & security audit

**Data model.** Ten tables: `system_settings` (singleton config), `customers` (PK = `auth.users.id`), `designs` (+ new `image_url` column), `barcode_mappings`, `orders` (unique per `customer_id`+`firm`, versioned), `order_items`, and the audit/idempotency tables `order_save_requests`, `barcode_mapping_log`, `product_sync_runs`. The formerly-separate `design_assets` table was dropped by the direct-image patch.

**Trust boundaries — verified correct:**

- The publishable/anon key and project URL are the only credentials in the browser. This is intentional; RLS is the protection layer. Confirmed no service-role key, sheet secret, or private key appears in `web/*.html`.
- Customers have **no direct write grant** on `orders` or `order_items`. All mutations go through `save_my_order` (`SECURITY DEFINER`), which re-derives `auth.uid()` server-side and ignores any client-supplied identity. Correct.
- `customers` has a **column-scoped** update grant (`company_name, contact_name, city, state, gstin` only). A customer cannot self-modify `active` or `phone_e164`. This means an admin-disabled customer cannot re-enable themselves. Correct and important.
- Admin actions run only inside `admin-api`, which calls `requireAdmin` → verifies the JWT server-side via service role and checks `app_metadata.role === 'admin'`. `app_metadata` is server-controlled and cannot be set through `signUp`/`user_metadata`, so a customer cannot escalate. Correct.
- Tables with RLS enabled but no policy and grants revoked (`system_settings`, `order_save_requests`, `barcode_mapping_log`, `product_sync_runs`) are inaccessible to `anon`/`authenticated`. This correctly hides `registration_access_code_hash`. Correct.

**Input handling — verified:**

- `save_my_order` validates firm membership per item, rejects duplicate designs, bounds `qty` to 1–9999, caps items at 500, and validates JSON shape. Good.
- The dashboard Excel export prefixes `= + - @` cells with `'` (CSV/formula-injection mitigation). Good.
- All three clients escape interpolated text via `escapeHtml`/`esc`, including image `src` attributes (quotes are entity-encoded, preventing attribute breakout). XSS surface is low; catalog text originates from the admin-controlled sheet regardless.
- `sheet-sync` authenticates with a 64-char shared secret compared in **constant time** (`secureEqual`). Good.

**CORS.** `ALLOWED_ORIGINS` in `.env.production` correctly lists `https://tanmaybothra1402.github.io,http://localhost:8000`. The handler reflects an allowed origin and otherwise falls back to `allowed[0]` — not a security weakness (CORS is not authorization), and the configured value matches the live Pages origin. *PENDING LIVE: confirm the deployed function secrets carry the same value.*

See Sections 9–10 for the issues that fall out of this audit.

---

## 2. Migration-order & leftover-code audit

The build was updated in two rounds (`202607150001–06`, then `202607160001–04`). Net final state is **consistent**, but the layered rewrites left dead and potentially confusing artifacts:

| Item | Status | Effect |
|---|---|---|
| `handle_new_auth_user` redefined 3× (150002 email→160003 native-phone→160004 email) | Final = 160004 (email-domain `accounts.maitricarnival.app`, local part `c<phone>`) | **160003 is dead code** — its native-phone logic never runs. Matches `customer-auth` `CUSTOMER_DOMAIN`. No functional bug, but misleading for anyone reading the history. |
| `customer_email_domain` set 3× (`customers.maitri.local`→`customers.maitricarnival.com` (160002)→`accounts.maitricarnival.app` (160004)) | Final = `accounts.maitricarnival.app` | 160002 is fully superseded. Net-correct. |
| `design_assets` table + `image-proxy` proxy | Table dropped (160001); **proxy still deployed** | `image-proxy` now references a non-existent table and will error on every call. Dead, reachable endpoint. |
| `IMAGEKIT_THUMB/PDF_TRANSFORMATION` secrets | Still present in `.env.production` | Harmless leftovers; no longer read by any active function. |
| `is_admin_user(uuid)` helper (150002) | Defined, **never referenced** by any policy or function | Dead helper. Harmless. |
| `upsert_product_rows` logs a `ROWS` run even when called inside `apply_product_snapshot` | By design | Every full snapshot writes **two** `product_sync_runs` rows (one `ROWS`, one `FULL_SNAPSHOT`); on failure, two `Failed` rows. Cosmetic — can confuse "Show sync status". |

None of these block launch; all are cleanup items (see Post-event, plus the `image-proxy` removal which is worth doing pre-event as attack-surface hygiene).

---

## 3. RLS test matrix (code-derived)

Derived from the grants in `202607150002_auth_and_rls.sql` and the direct-image patch. "Expected" is the code-guaranteed outcome; each row has a one-line live check.

| # | Actor | Operation | Expected | Basis |
|---|---|---|---|---|
| R1 | anon (no session) | `GET /rest/v1/customers` | **Deny** (grant revoked) | revoke all from anon |
| R2 | anon | `GET /rest/v1/orders`, `order_items` | **Deny** | revoke all |
| R3 | anon | `POST /rpc/lookup_barcode` | **Deny** (execute granted to `authenticated` only) | revoke from anon |
| R4 | anon | `GET /rest/v1/designs` | **Deny** (select granted to `authenticated` only) | grant to authenticated |
| R5 | customer A | read own `customers` row | **Allow** | `customers_select_own` |
| R6 | customer A | read customer B's row (`?id=eq.B`) | **Return 0 rows** | RLS `id = auth.uid()` |
| R7 | customer A | read B's `orders` / `order_items` | **Return 0 rows** | `orders_select_own`, `order_items_select_own` |
| R8 | customer A | `UPDATE customers SET active=true` | **Deny** (column not granted) | column-scoped grant |
| R9 | customer A | `UPDATE customers SET phone_e164=…` | **Deny** (column not granted) | column-scoped grant |
| R10 | customer A | direct `INSERT/UPDATE/DELETE orders` | **Deny** (no write grant) | no grant |
| R11 | customer A | `save_my_order` for own firm | **Allow** | execute granted |
| R12 | customer A | read all active `designs` incl `image_url` | **Allow (all rows)** | grant + `designs_read_active` — see M1 |
| R13 | customer A | read `system_settings` / `product_sync_runs` / `barcode_mapping_log` | **Deny** | RLS on, no policy, revoked |
| R14 | customer (non-admin) JWT | `POST /functions/v1/admin-api` any action | **403 ADMIN_REQUIRED** | `requireAdmin` |
| R15 | admin JWT | direct `GET /rest/v1/customers` (PostgREST) | **Return 0 rows** (admin uid is not a customer; admin data comes via `admin-api` service role) | RLS |

**PENDING LIVE:** run R1–R15 with (i) a bare anon key, (ii) a freshly registered `STRESS-` customer session, (iii) a second `STRESS-` customer, (iv) the admin JWT. Pass = every "Deny" returns 401/403 or an empty set, every "Allow" returns the actor's own data only. R6/R7 (cross-customer isolation) and R14 (privilege boundary) are the must-pass rows.

---

## 4. Auth & session analysis

**Registration/login path (code-verified):** the browser posts `{action, phone, password, …}` to `customer-auth` with only the `apikey` header (no bearer). The function normalizes the phone to `91[6-9]\d{9}`, derives the hidden email `c<phone>@accounts.maitricarnival.app`, and on register uses the **service role** `admin.createUser({email_confirm:true})`, then signs in and returns the session; the browser adopts it via `setSession`. The DB trigger provisions the `customers` row + two `orders`. Client and server phone/password rules are aligned (10-digit → `91…`; password 8–72). Error mapping is clean and non-leaky.

**Findings:**

- **H1 (Critical-to-verify) — `customer-auth` JWT verification.** `config.toml` declares `verify_jwt = false` only for `sheet-sync` and `admin-api`, **not** `customer-auth`. The browser calls it without a bearer token. If it was deployed without `--no-verify-jwt`, the platform rejects every register/login with 401 and the app is dead on arrival. You report it's live, so it was almost certainly deployed with the flag — but this must be positively confirmed (see §10-H1).
- **H2 (High) — registration abuse surface.** Registration is open (`REQUIRE_ACCESS_CODE:false`, no `registration_access_code_hash` set) and the Pages URL is public. Worse, account creation runs via service-role `admin.createUser`, which **bypasses GoTrue's normal signup rate-limiting/captcha**. A script can therefore create accounts quickly, each inserting 1 `auth.users` + 1 `customers` + 2 `orders` rows. Separately, GoTrue's own `enable_signup=true` means the `/auth/v1/signup` endpoint is also open as a second path. Impact: junk-data flooding and possible auth-table bloat during the event. The access-code check *is* correctly enforced server-side in the DB trigger for any path, so setting a code closes both paths at once.
- **Session handling — OK.** JWT expiry 3600s with auto-refresh; sessions persist in `localStorage`. Two devices hold independent valid sessions for the same user — intended and handled by the save-order version logic (§5).

**PENDING LIVE:** confirm a bad login returns a clean 401 (not a platform "missing JWT" 401), a good register returns a session, duplicate phone returns 409, and that a session token actually authorizes `get_my_order_state`.

---

## 5. Save-order concurrency & idempotency analysis

**Design (code-verified) — sound.** `save_my_order`:

1. Dedups on `request_id` (PK of `order_save_requests`): a repeat returns the stored response verbatim.
2. Takes `SELECT … FOR UPDATE` on the caller's single `(customer_id, firm)` order row, serializing concurrent saves for the same order.
3. Optimistic version gate: if `p_base_version <> orders.version`, records and returns a `ORDER_VERSION_CONFLICT` (with the fresh server state) instead of writing.
4. Validates items, replaces the cart atomically, bumps `version`, updates totals/status — all in one transaction.

**Scenario walkthrough:**

- *Same account, two devices, both at version 5.* Device A locks, matches, writes v6, commits. Device B was blocked on `FOR UPDATE`; it then reads v6, sees base 5 ≠ 6, returns conflict with server state. **No lost update.** ✔ (expected)
- *Repeated/replayed identical request.* Same `request_id` → stored response returned; no double-apply. ✔
- *Network drop after commit, user taps Save again.* The client generates a **fresh** `request_id` per click, so this is a new save with a stale `base_version` → conflict → forces reload. No double-apply, but note the idempotency key is effectively **never reused by the client** — resilience here rests on the version gate, not idempotency. Acceptable; worth knowing.
- *Different customers saving in parallel.* Locks are per-order-row, so distinct customers never contend. Scales cleanly. ✔
- *Duplicate barcode add.* Client blocks re-adding a design already in the cart; server also rejects `DUPLICATE_DESIGN_*`. Double-guarded. ✔
- *Maitri/Niharika isolation.* Two separate order rows per customer; `save_my_order` validates each item's firm ∈ `{p_firm, 'Both'}`. Cross-firm contamination rejected. ✔

**M-class note (Medium, M5):** the client mints a new `request_id` every click, so automatic retry idempotency is unused. Not a bug, but if you ever add auto-retry, reuse the same `request_id`.

**PENDING LIVE:** the concurrency claims are logically guaranteed but should be demonstrated: fire N parallel `save_my_order` calls with the same `base_version` from two sessions of one `STRESS-` account and assert exactly one success + rest conflict, order `version` increments by exactly the number of successes, and no duplicate/lost items.

---

## 6. Sheet-sync resilience analysis (code-derived)

`sheet-sync` (secret-gated) dispatches to `upsert_product_rows` (per-row upsert, `sync_version` bumped only on actual change) or `apply_product_snapshot` (validate dup/blank keys → upsert → **deactivate designs absent from the snapshot**). Apps Script drives it: immediate `onEdit` row sync + a **5-minute timed full snapshot**, both guarded by `LockService`.

**Findings:**

- **H3 (High) — snapshot mass-deactivation risk during live edits.** The 5-minute `scheduledExhibitionFullSync` deactivates every design not present in the sheet at read time. If, mid-event, someone clears/reorders rows, deletes a row to re-add it, or the read catches a transient partial state, those designs flip to `active=false` and **customers can no longer scan them** until the next good sync. Reversible, but disruptive during the exhibition. Mitigations in §10.
- **M2 (Medium) — one malformed row aborts the whole batch.** `normalize_product_firm` raises on an invalid `Firm`, and the upsert runs in a single transaction, so a single bad value (e.g., a pasted typo bypassing the sheet's data-validation dropdown) fails the **entire** sync/snapshot and writes a `Failed` run — no rows update. The sheet's Firm/Active data-validation reduces but does not eliminate this (paste can bypass validation).
- **Duplicate design number** — rejected pre-write in both paths (`DUPLICATE_DESIGN_NO_*`). ✔
- **Duplicate barcode mapping** — not a sheet concern; handled by `admin_map_barcode`, which *remaps* with an audit-log entry (intended). `mapBatch` continues past per-row failures and reports counts. ✔
- **Repeated delivery of the same sync** — upserts are idempotent (no-op when unchanged); snapshots recompute deactivations deterministically. No request-level dedup, but safe. ✔
- **Concurrent sheet edits** — serialized by `LockService` (15s edit lock, 5s snapshot lock; snapshot skips if it can't acquire). ✔
- **Double logging** — every snapshot writes both a `ROWS` and a `FULL_SNAPSHOT` run (see §2). Cosmetic.

**PENDING LIVE:** using only `STRESS-`-prefixed design numbers, exercise insert / update / deactivate / duplicate-design / malformed-Firm / repeated-delivery, and confirm existing production designs are never touched. Do **not** trigger a full snapshot against the live sheet during this test (it would evaluate deactivation across the real catalog).

---

## 7. Image & PDF analysis (code-derived)

Post-patch flow: `ProductMaster.ImageURL → designs.image_url → <img src>` in-page, and for the PDF `imageUrlToDataUrl()` does a CORS `fetch(url, {credentials:'omit'})` → data URL → `jsPDF.addImage`.

**Findings:**

- **H4 (High) — PDF fetches full-resolution originals.** The removed proxy used to serve `w-320,h-430,q-30,f-jpg`. The new PDF path fetches the **untransformed original** for every line item (the sample URL carries no `tr=` params). A heavy order (40–50 designs) downloads 40–50 full-size JPEGs and holds them as base64 data URLs simultaneously on a phone — slow, bandwidth-heavy, and a real out-of-memory / tab-crash risk on mid-range Android. This is the single most likely in-event failure. Fix in §10-H4 (append an ImageKit `tr=` transformation when building the PDF URL).
- **Resilience — good.** Both display and PDF wrap each image in try/catch; one broken or slow URL draws a placeholder rect and the order/PDF flow continues. A single failed image will **not** block the rest. ✔
- **CORS dependency (PENDING LIVE).** The PDF `fetch` reads cross-origin bytes, so ImageKit must return `Access-Control-Allow-Origin`. If it doesn't, in-page `<img>` still renders but **PDF images silently fall back to blank rects**. Must be confirmed against the real image host.
- **Format edge.** `addImage(dataUrl, undefined, …)` lets jsPDF infer format. Originals that are WebP/PNG may not embed cleanly in jsPDF 2.5.2 (WebP especially). Forcing `f-jpg` via the transformation (same fix as H4) also removes this risk.

**PENDING LIVE:** measure the sample image's byte size and a 40–50-item PDF build on a real mid-range phone (time + memory); test a deliberately broken URL and a slow/large URL; verify ImageKit CORS headers.

---

## 8. Load-test plan & expected behaviour (not executed)

No latency/error metrics were captured (environment cannot reach the project). The plan below is calibrated to your stated caps (peak 30, sustained 50 for 5 min, burst 75 for 30 s, ≤100 `STRESS-` accounts) and working-scale assumptions (~400 designs/barcodes, 10–20 typical / 40–50 heavy items).

**Scenarios & thresholds (proposed pass criteria):**

| Scenario | Mix | Threshold |
|---|---|---|
| Steady peak (30 users) | login → load orders → 5× add-barcode → save, loop | error rate < 1%, p95 `save_my_order` < 800 ms |
| Sustained (50 users, 5 min) | same | error rate < 2%, p95 < 1200 ms, no monotonic latency climb |
| Burst (75 users, 30 s) | login + one save each | error rate < 5%, no 5xx from PostgREST/Edge, recovery to baseline < 60 s |
| Heavy-order save | 50-item cart save | p95 < 1500 ms, correct totals |
| Read fan-out | `lookup_barcode` + catalog reads at 75 rps | p95 < 500 ms |

**Expected bottlenecks (analytical):** per-order `FOR UPDATE` locks mean **distinct** customers don't contend, so 30–75 *different* users should scale well; the shared write points are `order_save_requests`/`product_sync_runs` inserts and `auth.users` creation. Watch Edge Function cold starts (first-hit latency), the PostgREST/pooler connection ceiling on your plan, and GoTrue limits during the registration burst. Capture p50/p95/p99 and error rate per scenario; **abort** immediately on rising error rate, any sign of real-data impact, or Supabase throttling legitimate traffic.

This section is ready to convert into a runnable `k6`/Node suite on request; it needs an environment (or your machine) with network access to the project.

---

## 9. Prioritized findings

### Critical (confirmed) — none from static analysis

No auth bypass or cross-customer data-leak was found by code inspection. The isolation and privilege boundaries are correctly constructed.

### Critical-to-verify (launch-blocking if wrong; needs one live check each)

- **H1 — `customer-auth` may reject all calls if not deployed with `--no-verify-jwt`.** Not declared in `config.toml`. If misdeployed, registration and login are 100% broken. (§4, §10)
- **CV2 — RLS cross-customer isolation (R6/R7) and admin boundary (R14) must be demonstrated live** before trusting them under event conditions. Code says they hold; confirm with two `STRESS-` accounts + admin JWT.

### High

- **H2 — Open registration + rate-limit-bypassing account creation.** Abuse/junk-data surface during a public event. (§4)
- **H3 — 5-minute full-snapshot can mass-deactivate designs during live sheet edits.** (§6)
- **H4 — PDF downloads full-resolution images; heavy orders risk OOM/crash on phones.** (§7)

### Medium

- **M1 — Full catalog + image-URL enumerable by any authenticated user** (`designs`, `barcode_mappings`, `lookup_barcode` all readable; registration is open → effectively public scraping). (§1, §3-R12)
- **M2 — One malformed sheet row aborts the entire sync/snapshot.** (§6)
- **M3 — Dead but reachable `image-proxy` endpoint** referencing the dropped `design_assets` table. (§2)
- **M4 — CORS/image-host dependency for PDF is unverified**; silent blank-image fallback if ImageKit lacks CORS. (§7)
- **M5 — Idempotency key is never reused by the client**, so save resilience rests solely on the version gate. (§5)

### Post-event improvements

- Remove dead code: `image-proxy` function, `IMAGEKIT_*` leftover secrets, dead `handle_new_auth_user` (160003) and `is_admin_user`, superseded 160002.
- Collapse the double `product_sync_runs` logging per snapshot.
- Add a health/self-check endpoint that verifies each function's `verify_jwt` posture.
- Consider signed/short-lived image delivery if catalog confidentiality matters beyond the event.
- Add lightweight app-side rate limiting or a captcha to `customer-auth`.
- Unlock-sets-`Saved` even for empty orders (cosmetic status inaccuracy in `admin-api setOrderLocked`).

---

## 10. Remediation steps (Critical-to-verify & High)

**H1 — Confirm/settle `customer-auth` JWT posture.**
1. Verify live: `POST https://ezmtiiftolcaslqfvozu.supabase.co/functions/v1/customer-auth` with header `apikey: <publishable>` and body `{"action":"login","phone":"9111100001","password":"x"}`. Expected **401 with `{"ok":false,"error":"Incorrect mobile number or password."}`** (the function ran). A platform error like `{"message":"Missing authorization header"}` or `401 Invalid JWT` means JWT verification is ON and the app is broken.
2. If broken (or to be safe), redeploy without JWT enforcement and pin it in config:
   ```bash
   npx supabase functions deploy customer-auth --no-verify-jwt
   ```
   Add to `supabase/config.toml`:
   ```toml
   [functions.customer-auth]
   verify_jwt = false
   ```
   Re-run step 1 to confirm.

**CV2 — Demonstrate RLS isolation live (run the §3 matrix).** Register two `STRESS-` customers and use the admin JWT; assert R6/R7 return empty for the other customer and R14 returns 403. If any "Deny" row returns data, treat as Critical and stop launch.

**H2 — Close open registration (server-side, covers all paths).**
```sql
update public.system_settings
set registration_access_code_hash =
    encode(extensions.digest('YOUR_EXHIBITION_CODE','sha256'),'hex')
where singleton = true;
```
Then set `REQUIRE_ACCESS_CODE:true` in `web/app.html` (shows the field) and share the code only with genuine buyers. The DB trigger enforces it regardless of whether registration comes via `customer-auth` or direct GoTrue signup. Optionally also set GoTrue `enable_signup=false` if the only intended path is `customer-auth`. If you *want* fully open registration, accept the abuse risk and instead add basic rate limiting to `customer-auth`.

**H3 — Make the full snapshot safe during the event.** Choose one:
- Simplest for event days: **disable the 5-minute timed trigger** and rely on immediate `onEdit` row sync only; run a manual "Sync complete product snapshot" only when you intentionally want deactivation of removed rows.
- Or guard the snapshot: refuse to deactivate if the incoming row count is implausibly low (e.g. `< 90%` of current active designs) — abort and log instead of mass-deactivating. (Add a threshold check in `apply_product_snapshot` before the `update … set active=false`.)

**H4 — Shrink PDF images.** When building the PDF URL, append an ImageKit transformation instead of fetching the original, e.g. in `imageUrlToDataUrl`/the PDF loop:
```js
const pdfUrl = item.imageUrl + (item.imageUrl.includes('?') ? '&' : '?') + 'tr=w-320,h-430,c-at_max,q-35,f-jpg';
const dataUrl = await imageUrlToDataUrl(pdfUrl);
```
This restores the pre-patch payload size, forces JPEG (fixing the WebP/PNG embed edge, M4-adjacent), and removes the OOM risk. Verify a 50-item PDF on a real phone afterwards. (For in-page thumbnails you can similarly append `tr=w-160,q-40` to the `<img src>` to cut data usage, though memory pressure there is far lower.)

---

## Appendix — What remains to be executed live

When run from a network-enabled environment (or on your machine), the following close every PENDING LIVE item and produce Sections 3–8 with real results/metrics. All test data must use `STRESS-`/`TEST-` prefixes (company/contact names; synthetic phone block recorded for cleanup), touch no unprefixed records, and stop on rising errors or throttling.

1. Unauth probes (R1–R4) + CORS from Pages vs. a foreign origin.
2. Register 2 `STRESS-` customers via `customer-auth`; run the full R1–R15 matrix incl. admin JWT.
3. Concurrency: parallel `save_my_order` (same base_version, two sessions) → assert one success/rest conflict; repeated `request_id` → identical response; heavy 50-item save.
4. Sheet-sync: `STRESS-` designs only — insert/update/deactivate/duplicate/malformed/replay; **no** live full snapshot.
5. Image/PDF: sample byte size, 40–50-item PDF on a phone, broken + slow URL, ImageKit CORS headers.
6. Load: 30 steady / 50×5 min / 75×30 s within caps; capture p50/p95/p99 + error rate; abort on the stop conditions.
7. Cleanup: delete only the `STRESS-` accounts/records created, by recorded IDs.
