# Maitri Carnival 2026 - Deploy runbook

Production project: `ezmtiiftolcaslqfvozu`

The current build consists of two static pages, cumulative database migrations, four Edge Functions, and the Google Sheets mirror.

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
supabase/migrations/202607170006_merge_notes_style_pcs.sql
```

It adds merge-safe order operations, style, pieces per set, per-design notes, total sets and actual total pieces.

## 2. Deploy Edge Functions

```bash
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions deploy admin-api --no-verify-jwt
npx supabase functions deploy data-sync --no-verify-jwt
npx supabase functions deploy sheet-sync --no-verify-jwt
npx supabase functions list
```

`customer-auth`, `admin-api`, `data-sync`, and `sheet-sync` intentionally perform their own authentication/secret checks, so their `verify_jwt` setting is false in `supabase/config.toml`.

Confirm the deployed secrets include:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SHEET_SYNC_SECRET`
- `ALLOWED_ORIGINS` containing the GitHub Pages origin

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
2. Staff login is rejected unless `app_metadata.role` equals `admin`.
3. Entry check-in unlocks customer ordering.
4. Two stale devices adding different designs preserve both additions.
5. Customer and Assisted admin adding different designs preserve both additions.
6. Explicit deletion removes only the selected design.
7. Same-design simultaneous changes resolve to the last completed save.
8. Notes persist after refresh and appear in admin detail and PDF.
9. Total pieces equals the sum of `sets x pcs_per_set`.
10. Sale-order PDF completes even when one product image cannot be fetched.
11. An expired order reopened by staff can be saved from the customer page.
12. Sheet `_delete` is rejected for operational tables and accepted only for Lookups.

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

```sql
update public.system_settings
set registration_enabled = false
where singleton = true;

update public.orders
set status = 'Locked', admin_unlocked = false
where status <> 'Locked';
```
