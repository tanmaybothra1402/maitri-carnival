# Maitri x Niharika Self-Service Exhibition Orders

Production ordering system for Maitri Carnival 2026, 19-21 July 2026.

## Included

- Customer phone/password registration through the `customer-auth` Edge Function.
- Exactly one Maitri order and one Niharika order per customer.
- Admin check-in gate and an account-wide edit window.
- Merge-safe concurrent customer/admin ordering with explicit deletions.
- Product master fields: category, style, fabric, and pieces per set.
- Per-design order notes and computed sets/pieces totals.
- Barcode lookup, mobile camera scanning, and direct ImageKit thumbnails.
- Client-generated sale-order PDFs.
- Role-gated admin console for entry, slots, mapping, products, assisted orders, staff, and analytics.
- Supabase-master Google Sheets mirror with guarded writable columns.

## Active application files

- `web/user.html` - customer app.
- `web/admin-a106dc80eeabd658.html` - admin console.
- `supabase/migrations/` - cumulative schema and function definitions; highest numbered definition wins.
- `supabase/functions/customer-auth/index.ts` - customer registration/login.
- `supabase/functions/admin-api/index.ts` - service-role admin operations.
- `supabase/functions/data-sync/index.ts` - full two-way Google Sheet mirror.
- `supabase/functions/sheet-sync/index.ts` - retained legacy product importer.
- `apps-script/DataSync.gs` - Google Sheet client.

## Start here

1. Read `IMPLEMENTATION_NOTES.md` for the latest coordinated change.
2. Follow `docs/DEPLOY_CARNIVAL.md` in order.
3. Use `docs/SHEETS_MIRROR.md` when updating the workbook.

## Security boundary

The Supabase project URL and publishable key are expected in the static pages. Never place the service-role key or `SHEET_SYNC_SECRET` in browser files or the repository.
