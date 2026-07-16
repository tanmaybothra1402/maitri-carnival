# Maitri × Niharika Self-Service Exhibition Orders

Disposable, reliability-first order system for the 19–21 July 2026 in-office exhibition.

## Included

- Customer phone + password registration/login through Supabase Auth.
- Exactly one editable Maitri order and one editable Niharika order per customer.
- PostgreSQL RLS and an atomic, versioned save RPC.
- Barcode-to-design lookup and mobile camera scanning.
- Protected low-resolution thumbnails through an authenticated Edge Function proxy.
- Client-side order PDFs with low-resolution thumbnails.
- Separate admin barcode mapping tool and admin dashboard.
- Google Sheets → Supabase product-master synchronization.
- Excel product-master template.
- GitHub Pages workflow.

## Start here

1. Read `docs/SETUP.md`.
2. Work through its numbered checkpoints in order.
3. Use `docs/TEST_PLAN.md` before the exhibition.

## Important security boundary

The public Supabase URL and publishable/anon key belong in the HTML pages. The service-role key, ImageKit private key and Sheet sync secret must never be committed or inserted into a browser file.

## Main files

- `web/app.html` — customer registration, login, scanning, order editing and PDF.
- `web/mapping.html` — admin barcode mapping.
- `web/dashboard.html` — admin analytics, export and password reset.
- `supabase/migrations/` — schema, Auth trigger, RLS and database functions.
- `supabase/functions/` — Sheet sync, admin API and image proxy.
- `apps-script/Sync.gs` — Google Sheets sync.
- `templates/Maitri_Niharika_Product_Master.xlsx` — product-master starter workbook.
