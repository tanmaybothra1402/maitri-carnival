BUNDLE 6 of 6 — CONFIG & DOCS.


################################################################################
# FILE: supabase/config.toml
################################################################################

project_id = "maitri-office-exhibition"

[api]
enabled = true
port = 54321
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
max_rows = 1000

[db]
port = 54322
major_version = 17

[studio]
enabled = true
port = 54323

[inbucket]
enabled = true
port = 54324

[auth]
enabled = true
site_url = "http://localhost:8000/app.html"
additional_redirect_urls = ["http://localhost:8000/**"]
jwt_expiry = 3600
enable_signup = true

[auth.email]
enable_signup = true
double_confirm_changes = false
enable_confirmations = false

[functions.sheet-sync]
verify_jwt = false

[functions.admin-api]
verify_jwt = false



################################################################################
# FILE: README.md
################################################################################

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


################################################################################
# FILE: docs/DEPLOY_CARNIVAL.md
################################################################################

# Maitri Carnival 2026 — Deploy runbook

The new build adds an admin entry gate, slot booking, a 24-hour edit window, assisted
admin ordering, and EKUM branding, on top of the existing `ezmtiiftolcaslqfvozu` project.
Everything below runs from the repo root. The sandbox that generated these files cannot
reach Supabase, so you run the push/deploy steps.

## What changed (files)

- `supabase/migrations/202607170001_carnival_entry_slots_window.sql` — event settings, customer check-in + account edit-window columns, `orders.admin_unlocked`, `slots` + `bookings` tables, RLS/grants.
- `supabase/migrations/202607170002_carnival_functions.sql` — guarded `save_my_order`, shared `_write_order`, `admin_save_order`, `get_my_status`, `list_slots`, `book_slot`, `cancel_my_booking`, `check_in_customer`, `revoke_entry`.
- `supabase/functions/admin-api/index.ts` — new actions: `directory`, `checkIn`, `revokeEntry`, `listSlots`, `upsertSlot`, `deleteSlot`, `listBookings`, `assistedRegister`, `assistedSaveOrder`, `getCustomerOrders`; `setOrderLocked` now toggles `admin_unlocked`.
- `web/user.html` — customer app (register + credentials card, slot booking, entry-pending gate, order form, 24h countdown, thumbnail PDF).
- `web/admin.html` — one tabbed console (Dashboard, Entry, Slots, Mapping, Products, Assisted order).
- `web/index.html` — redirects to `user.html`.

The old `web/app.html`, `web/mapping.html`, `web/dashboard.html` are superseded by
`user.html` + `admin.html`. Leave or delete them; nothing links to them.

## 1. Apply migrations

```bash
npx supabase db push
```

Confirm the new tables exist (Dashboard → Table editor): `slots`, `bookings`, and the new
`customers` columns `checked_in_at`, `ordering_started_at`, `edit_deadline`.

## 2. Redeploy the admin function; confirm customer-auth JWT posture

```bash
npx supabase functions deploy admin-api --no-verify-jwt
# customer-auth must remain callable without a bearer token:
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions list
```

Quick check (should return a clean 401 "Incorrect mobile number or password", i.e. the
function ran, not a platform "missing JWT" error):

```bash
curl -s -X POST "https://ezmtiiftolcaslqfvozu.supabase.co/functions/v1/customer-auth" \
  -H "apikey: sb_publishable_QTijSp1pHxiCGga3l722zg_Vjqxj2qG" \
  -H "Content-Type: application/json" \
  -d '{"action":"login","phone":"9111100001","password":"wrongpass"}'
```

## 3. Retire the dead image-proxy (optional cleanup)

It references the dropped `design_assets` table and is unused.

```bash
npx supabase functions delete image-proxy
```

## 4. Publish the pages

The three HTML files already carry the live URL + publishable key — no placeholders to
replace. Commit and push; GitHub Actions publishes `web/`.

- **Customer link:** `https://tanmaybothra1402.github.io/maitri-carnival/user.html`
- **Admin link:** `https://tanmaybothra1402.github.io/maitri-carnival/admin.html`

For privacy, rename the admin page to an unguessable filename before committing and keep it
private (auth is still required regardless):

```bash
git mv web/admin.html web/admin-$(openssl rand -hex 8).html
```

Record the resulting filename. Confirm `ALLOWED_ORIGINS` in the deployed function secrets
includes the Pages origin (it already does in `.env.production`).

## 5. Create the visit slots

Log into admin → **Slots** tab → add windows across 19–21 July 2026 (e.g. hourly, optional
capacity). Booked counts and a traffic bar appear as customers book.

## 6. Event-day operating flow

1. Customer registers (open link), saves the credentials card, optionally books a slot.
2. On arrival, staff open admin → **Entry**, search the customer's mobile, tap **Check in**.
3. Customer's page auto-unlocks; they build Maitri/Niharika orders by scanning barcodes.
4. First save starts the account-wide 24-hour edit window (shown as a live countdown).
5. For anyone who can't use the site, admin → **Assisted order**: register (if needed) and
   build the order for them — this bypasses the gate and the lock.
6. Locked/expired orders can be reopened per order from the Dashboard order detail (Unlock).

## 7. Google Sheets full mirror — deferred phase

The current `sheet-sync` remains one-way (ProductMaster → Supabase) for designs. The
full two-way overview/edit workbook (all tables, pull + guarded push) is the agreed final
phase, to be built after this app is verified live.

## Post-event

```sql
update public.system_settings set registration_enabled = false where singleton = true;
-- optional hard lock:
update public.orders set status = 'Locked', admin_unlocked = false where status <> 'Locked';
```


################################################################################
# FILE: docs/SHEETS_MIRROR.md
################################################################################

# Google Sheets two-way mirror

Supabase is the master. This workbook lets you pull every table, edit it, and push
changes back. Built from `apps-script/DataSync.gs` + the `data-sync` Edge Function.

## One-time setup

1. Deploy the function (uses the existing `SHEET_SYNC_SECRET`):
   ```bash
   npx supabase functions deploy data-sync --no-verify-jwt
   ```
2. Create a new Google Sheet → Extensions → Apps Script → paste `DataSync.gs` → Save → reload the sheet.
3. **Supabase Sync → 1. Configure connection** → paste the project URL (`https://ezmtiiftolcaslqfvozu.supabase.co`) and the same `SHEET_SYNC_SECRET`.
4. **Supabase Sync → Pull ALL tables** → builds one tab per table.

## Tabs and what you can edit

Each tab shows all columns for reference; **only the tinted columns are written back** (everything else — ids, versions, timestamps — is ignored on push).

| Tab | Editable columns | New rows? |
|---|---|---|
| Designs | firm, image_url, category, fabric, color, description, active | Yes (give a new DesignNo) |
| BarcodeMappings | design_no, active | Yes (give a new barcode) |
| Customers | company_name, contact_name, city, state, gstin, agent, active | No (created by registration) |
| Orders | status, admin_unlocked | No |
| OrderItems | qty | No |
| Slots | starts_at, ends_at, label, capacity, active | Yes (leave id blank) |
| Bookings | party_size, note, status, slot_id | No |
| Lookups | kind, value | Yes |
| Settings | event_name, event dates, registration_enabled, edit_window_hours | No |

## Editing rules

- **Pull first**, edit, then **Push this tab** (push only affects the active tab).
- **Delete a row:** put `TRUE` in its `_delete` column, then push.
- **Add a design:** new row with a unique `design_no` + firm + details (+ image_url). Push.
- **Product images:** put the ImageKit link in `image_url` on the Designs tab and push — that's how images get attached.
- Editing `OrderItems.qty` automatically recomputes that order's totals.
- Dates/times must be full timestamps (e.g. `2026-07-19T10:00:00+05:30`) for slots/settings.

## Safety notes

- The push only touches editable columns, so you can't accidentally corrupt ids or versions.
- Customers/Orders/OrderItems are update-only (no new rows) — orders are created by the app.
- Keep the `SHEET_SYNC_SECRET` private; anyone with it and the URL can read/write data.
