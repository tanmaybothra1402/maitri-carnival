# Maitri Carnival 2026 - Final coordinated update

Date: 16 July 2026

## What changed

### Merge-safe concurrent ordering

Affected paths:

- `supabase/migrations/202607170006_merge_notes_style_pcs.sql`
- `web/user.html`
- `web/admin-a106dc80eeabd658.html`

Customer and assisted-admin saves now send only changed designs plus explicit deletion tombstones. The database locks the order row and applies those operations to the latest server order. Unrelated additions made by another device are preserved. If both users change the same design, the last committed save wins for that design. Omitting a design is no longer interpreted as deletion; deletion must be explicit.

The migration keeps compatibility with an older full-cart client during rollout. A stale old-client save is merged rather than allowed to erase newer rows.

### Product master and order quantities

Active product fields are now:

- `design_no`
- `firm`
- `image_url`
- `category`
- `style`
- `fabric`
- `pcs_per_set`
- `description` (optional legacy-compatible detail)
- `active`

`color` is retained physically in PostgreSQL only for safe backward compatibility. It is hidden from the current product UI and Google Sheet mirror.

Order lines now include:

- sets (`qty`)
- pieces per set snapshot
- computed line pieces (`sets * pcs_per_set`)
- a customer/staff note per design, max 500 characters

Orders now store:

- `total_designs`
- `total_sets`
- `total_pieces` (actual pieces)

### Sale-order PDF

Affected path:

- `web/user.html`

The browser PDF now includes product photo, design, category/style/fabric, per-design note, sets, pcs/set, line pieces, and order totals. It includes the order reference/version, uses dynamic row heights, repeats the table header on later pages, limits image downloads to six at a time, tolerates failed product images, and blocks download while there are unsaved changes so the document matches the saved order.

A rendered visual sample is included separately as `Maitri-Sale-Order-Sample.pdf` and `.png`.

### Admin and Sheet compatibility

Affected paths:

- `supabase/functions/admin-api/index.ts`
- `supabase/functions/data-sync/index.ts`
- `supabase/functions/sheet-sync/index.ts`
- `apps-script/DataSync.gs`
- `supabase/config.toml`
- `docs/DEPLOY_CARNIVAL.md`
- `docs/SHEETS_MIRROR.md`
- `README.md`

The current dashboard was not redesigned. It was only made schema-compatible with style, sets and pieces so it continues to operate until the planned dashboard pass.

`pcs_per_set` is validated as a whole number from 1 to 9999. For safety, direct Sheet deletion is now blocked for designs, barcode mappings, customers, orders, order items, slots, bookings and settings. Use `active`, `status`, or the admin console. Only lookup rows may be deleted through `_delete`.

## Deployment requirements

### 1. Database migration required: YES

From the repository root:

```bash
npx supabase db push
```

This applies `supabase/migrations/202607170006_merge_notes_style_pcs.sql`.

### 2. Edge Function redeploy required: YES

```bash
npx supabase functions deploy admin-api --no-verify-jwt
npx supabase functions deploy data-sync --no-verify-jwt
npx supabase functions deploy sheet-sync --no-verify-jwt
```

`customer-auth` code did not change for this feature. Its no-JWT posture is now also declared in `supabase/config.toml`.

### 3. Static frontend publish required: YES

Publish these exact paths:

- `web/user.html`
- `web/admin-a106dc80eeabd658.html`

### 4. Google Apps Script update required: YES

Replace the Apps Script project code with:

- `apps-script/DataSync.gs`

Save, reload the Sheet, then run **Supabase Sync -> Pull ALL tables**. The Designs tab will expose `style` and `pcs_per_set`; the OrderItems tab will expose `line_note`.

## Important rollout order

1. Apply the migration.
2. Redeploy the three Edge Functions.
3. Update Apps Script and pull the workbook.
4. Fill and push valid `pcs_per_set` values before live customer ordering.
5. Publish both HTML files.
6. Run the verification checklist below.

Existing order lines are initially backfilled at 1 pc/set because that is the only safe assumption for historical rows. Product-master changes are snapshotted when an order line is next saved. Any pre-launch test orders that need correct piece totals should be cleared/re-saved after the product master is populated.

## Verification checklist

1. Set two devices on the same customer and firm.
2. Device A adds design A and saves.
3. Without refreshing, Device B adds design B and saves.
4. Refresh both devices: designs A and B must both exist.
5. Admin Assisted adds design C while customer adds design D: all four must remain.
6. Change the same design quantity from two devices: the last completed save should own that design's final quantity.
7. Delete one existing design from one device while another device adds a different design: only the explicitly deleted design should disappear.
8. Confirm each product displays category, style, fabric and pcs/set.
9. Add line notes and verify they persist after refresh and appear in admin order detail and PDF.
10. Verify totals: line pieces = sets x pcs/set; order pieces = sum of line pieces.
11. Download a multi-row PDF with one missing/broken image; generation must still complete.
12. Expire the customer window, reopen one firm from admin, and verify the customer Save button is enabled only for that reopened firm.
13. Pull the Google Sheet and confirm legacy color columns are not shown in Designs/OrderItems.
14. Attempt `_delete=TRUE` on a customer row; push must be rejected. Use active/status instead.

## Local verification completed

- Customer browser script: JavaScript syntax passed.
- Admin browser script: JavaScript syntax passed.
- All Edge Function TypeScript files: transpilation/syntax passed.
- Both HTML files: no duplicate IDs; static DOM references checked.
- Merge behavior: deterministic operation-model checks passed.
- Sale-order sample: created, preflighted, rendered at 180 DPI, and visually inspected with no clipping or overlap.

The database migration and deployed Edge Function behavior still require execution against the actual Supabase project; this environment has no project credentials or live database connection.
