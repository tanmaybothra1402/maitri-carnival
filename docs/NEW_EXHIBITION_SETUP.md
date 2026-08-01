# Spinning up the next exhibition

This codebase is the template. A new exhibition is a **fork plus a reset**, not a
rewrite. Budget half a day, not a week.

Decide first: **new Supabase project, or reuse this one?**

- **New project (recommended).** The old event's data stays intact for reference
  and reporting. No risk of a reset command touching live history. Costs one more
  project on your plan.
- **Reuse.** Cheaper, but you must wipe customers/orders and you lose last event's
  records unless you export first.

The rest assumes a new project.

---

## 1. Fork the repo

```bash
cd ~/Documents
git clone https://github.com/<user>/maitri-carnival.git maitri-<newevent>
cd maitri-<newevent>
rm -rf .git && git init && git add -A && git commit -m "Fork from Carnival 2026"
```

Create the new GitHub repo and push. Then **Settings → Pages → Source → GitHub
Actions** (not "Deploy from a branch" — that combination serves a stale site
forever while Actions shows green).

Rename the admin page to a fresh unguessable name:

```bash
git mv web/admin-<old>.html web/admin-$(openssl rand -hex 8).html
```

Auth is the real security boundary; the filename only keeps it out of casual
reach and out of search engines.

## 2. New Supabase project

```bash
npx supabase link --project-ref <new-ref>
npx supabase db push
```

Set secrets, then deploy all functions:

```bash
npx supabase secrets set SHEET_SYNC_SECRET=$(openssl rand -hex 32)
npx supabase secrets set ALLOWED_ORIGINS=https://<user>.github.io
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions deploy admin-api     --no-verify-jwt
npx supabase functions deploy data-sync     --no-verify-jwt
npx supabase functions deploy design-image  --no-verify-jwt
npx supabase functions list
```

Save the new sync secret to `apps-script/SHEET_SYNC_SECRET.txt` (gitignored).

## 3. Rebrand and reconfigure

Find and replace across `web/*.html`:

| Token | Where |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | `CONFIG` at the top of both pages |
| Event name, dates | `CONFIG` + `system_settings` |
| `@accounts.maitricarnival.app` | `customer-auth` + both pages (use a new domain per event so accounts never collide) |
| Theme tokens | CSS `:root` — `--teal-deep`, `--teal`, `--foam`, `--warm`, `--orange` |
| Firm colours | Maitri `#2E2A6B`, Niharika `#E6007E` |
| Logos | `web/assets/` |

Then seed settings:

```sql
update public.system_settings
set event_name = '<Event> 2026',
    event_start_date = '2026-..-..',
    event_end_date   = '2026-..-..',
    edit_window_hours = 24,
    registration_enabled = true
where singleton = true;
```

## 4. Create the first admin

Register through the app, then promote:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{"role":"admin"}'::jsonb
where email = '<your-email>';
```

`app_metadata`, never `user_metadata` — users can edit the latter.

## 5. Slots

Two-hour windows, named systematically so staff can navigate them (`19.1 (10AM)`,
`19.2 (12PM)`, …). Generate with SQL rather than clicking through the UI.

## 6. Products and barcodes

1. Fill the Designs tab in the workbook (see `maitri-sheet-sync` for the
   pre-flight checklist — `firm` spelling and duplicate `design_no` are the two
   things that reject a whole import).
2. Push. **Never pull that tab first** — pulling clears hand-entered rows.
3. Verify: `select count(*) from designs where active;` — must not be 0.
4. Generate barcode sheets: `node scripts/make-qr-sheets.js` (700 per brand, A3,
   120 per page). Adjust `PER_BRAND` and `BRANDS` at the top.
5. Map stickers in the admin console. The typeahead matches any substring; the
   batch queue saves once. A sticker already mapped is refused at scan time.

## 7. Staff

Create logins in Admin → Team. Module toggles, not granular permissions. A packer
gets **Dispatch only** — not Sales.

Brief them on the two non-obvious rules:
- "Reopen the order" does **not** unlock a dispatched line. Undispatch first.
- Granting someone a new module requires them to reload the page.

## 8. Before doors open

Walk the full list in `maitri-deploy`, but at minimum:

- Map one real printed sticker, then scan it from a test customer account and
  confirm the design appears with a readable thumbnail and reaches the PDF.
- Confirm `select count(*) from designs where active` is the number you expect.
- Log in as a non-admin staff member and check they land on a section they can
  actually access.
- Open the customer page in a private window and confirm no `ik.imagekit.io`
  request appears in the network tab.

## 9. Reset instead of forking (if reusing a project)

Export first. Then, keeping designs, slots, staff and settings:

```sql
begin;
delete from auth.users where email like '%@accounts.<old-domain>';
delete from public.dispatch_events;
delete from public.dispatch_lines;
delete from public.order_save_requests;
delete from public.order_items;
delete from public.orders;
delete from public.bookings;
delete from public.customers;
delete from public.barcode_mapping_log;
commit;
```

The cascade from `auth.users` does most of this; the explicit deletes catch rows
created without an auth user. **Keep `barcode_mappings`** unless the physical
stickers are being reprinted — recreating hundreds of mappings is expensive,
deleting them later is one line.
