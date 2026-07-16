# Stress Test Report — V2 (staff permissions, merge saves, dashboard v2, pcs/set)

**Date:** 16 July 2026 · **Type:** static / code-derived (live DB unreachable from the analysis environment)
**Scope:** the changes in migrations `202607170006`–`202607170008`, the updated Edge Functions (`admin-api`, `customer-auth`, `data-sync`, `_shared/auth.ts`), and both HTML pages.

## Summary

The revision is large but **coherent and well-constructed** — frontend, Edge Functions, and SQL move together. No confirmed Critical issue (no auth bypass, cross-customer leak, or privilege escalation) was found by inspection. The main risks are **deploy-ordering** (all pieces must go live together) and a few **Medium/Low** hardening items.

Counts: 0 confirmed Critical · 2 High (deploy-ordering) · 4 Medium · 3 Low.

## What changed (verified by reading)

- **Merge-safe saves.** `_write_order` now takes an operation list (`_op:"upsert"` / `_op:"delete"` with `_delete:true`). Under a `SELECT … FOR UPDATE` lock it applies deletes, upserts changed designs (`on conflict (order_id, design_no)`), and **preserves omitted designs**. Version conflicts no longer error — a stale save **merges** (union) and returns `MERGED`.
- **Per-design pieces.** `designs.pcs_per_set` + `order_items.pcs_per_set_snapshot`; true pieces = `sets × pcs_per_set` computed consistently in `_write_order`, `order_state_json`, and both dashboards.
- **Style + line notes.** `designs.style`, `order_items.style_snapshot`, `order_items.line_note` (≤500). Legacy `color`/`description` retained for compatibility.
- **Staff RBAC.** `staff_profiles` with presets + a `permissions` JSON; role can be `admin` or `staff`. `admin-api` enforces per-action permissions at a single choke point.
- **Dashboard v2** (`admin_dashboard_v2`), single-query **reception directory** (`admin_directory`), one-call **bootstrap** (`get_my_carnival_bootstrap`), and **action attribution** (customer vs staff) on order items.

## Verified sound

- **Concurrency/merge.** Per-order `FOR UPDATE` serializes writes; the frontend sends `_op`-marked deltas (dirty upserts + tracked deletes), so the merge path always triggers and the legacy full-replace can't fire for the current client. Concurrent adds are preserved, deletes are explicit, same-design edits are last-write-wins, and operations are idempotent (retry-safe) plus `request_id`-deduped.
- **RBAC enforcement.** `requireAdmin` accepts `admin`/`staff`; `loadStaffContext` builds effective permissions; `requireActionPermission` is called for **every** action at one place (admin-api line 429). Every sensitive action is present in `ACTION_PERMISSIONS`; the only unmapped actions are `whoami` and `bootstrap` (benign self/UI-init). Disabled staff (`active=false`) are blocked (`TEAM_ACCOUNT_DISABLED`), and `is_admin_user`/`staff_has_permission` both require `active`.
- **Sheet delete gating.** `data-sync` throws `DELETE_NOT_ALLOWED_…` unless the table is `deletable` — only `lookup_values` is. Matches the documented rule.
- **Identity separation.** Staff use `@staff.maitricarnival.app`, customers `@accounts.maitricarnival.app`; the registration trigger only provisions the customer domain, so staff/admin accounts are never mis-created as customers.
- **Totals integrity.** A backfill in `170006` recomputes `total_sets`/`total_pieces`; new writes keep them in sync.
- **Syntax.** All three migrations have balanced dollar-quotes; `admin-api`, `customer-auth`, `data-sync` and both HTML scripts parse clean.

## Findings

### High — deploy-ordering (not code defects, but will break things if mis-sequenced)

- **H1. Everything must deploy together.** The new `admin.html` calls `admin_dashboard_v2` and `staff_has_permission`, and `170007` **revokes the old `admin_dashboard` from `authenticated`**. The customer save now sends `_op` deltas that only `170006`'s `_write_order` understands. So: push migrations `170006–170008`, redeploy **all four** functions, and publish **both** HTML files in the same release. If HTML ships before migrations (or vice-versa), the dashboard, staff, or save flows break.
- **H2. Apply all three new migrations.** `DEPLOY_CARNIVAL.md` calls `170006` "the latest," but `170007` and `170008` also exist. `npx supabase db push` applies all by filename order — just don't hand-apply only `170006`.

### Medium

- **M1. `staff_has_permission(p_user_id, p_permission)` is granted to `authenticated` and takes an arbitrary user id.** Any logged-in user (including a customer) could probe whether *any* user id holds a given permission — boolean only, but it leaks who is staff/admin and their capabilities. Fix: ignore `p_user_id` and use `auth.uid()`, or restrict execute to `service_role`.
- **M2. Legacy-client save fallback.** If a customer has an **old cached page** (pre-update, sends a full cart without `_op`) and saves while stale, `_write_order` merges (union) and that client's local deletions are silently dropped. A hard refresh eliminates the stale page. Worth a note to staff during rollout.
- **M3. Dashboard v2 date filter is brittle.** `admin_dashboard_v2` casts `p_filters->'dateFrom'->>0` to `date`; a malformed value throws and fails the whole dashboard load (500). Ensure the client only sends valid dates or omits the key; consider a safe-cast.
- **M4. Two dashboard code paths coexist.** The old TS `dashboard()` action in `admin-api` and the old `admin_dashboard` RPC are now effectively dead (frontend uses `admin_dashboard_v2`). Harmless, but remove one path post-event to avoid drift.

### Low

- **L1. `is_admin_user` now returns true for any active staff.** Harmless today (its only callers — the old dashboard variants — are revoked from `authenticated`, and it's not used in any RLS policy). But if you later gate new broad access with `is_admin_user`, remember it no longer means "admin only."
- **L2. `capture_customer_order_actor`** runs an `exists(customers…)` per row on every item insert/update — negligible overhead, but per-row.
- **L3. `color`/`description` remain in responses** though the UI uses `style`/`line_note`. Fine for compatibility; tidy later.

## PENDING LIVE (run these against the deployed project to close out)

1. **RBAC:** log in as a `sales`-preset staff → confirm `PERMISSION_DENIED` on `createStaff`/`updateSettings`, allowed on `assistedSaveOrder`/`recentOrders`.
2. **Merge:** one customer on two devices — each adds different designs, one deletes a design → final order is the union with the deletion applied; totals correct.
3. **Pieces:** confirm `pieces == sets × pcs_per_set` across order screen, admin detail, dashboard, and PDF.
4. **Sheet:** `_delete=TRUE` on Designs → `DELETE_NOT_ALLOWED`; on Lookups → deletes. New DB column auto-appears on pull.
5. **Dashboard v2:** latency at ~300 customers / thousands of items; filters + drilldowns; date range.
6. **Auth:** `customer-auth` still returns a clean 401 on bad login (verify_jwt off), and registration stores `agent`.
7. **Attribution:** a staff-built assisted order shows `source=staff`; a customer edit shows `source=customer` in the dashboard.

No auth-bypass, cross-customer-leak, or privilege-escalation path was found in the new code. Address H1/H2 in the deploy, and M1 is the one worth a quick fix before launch.
