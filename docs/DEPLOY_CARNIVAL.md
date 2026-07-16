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
