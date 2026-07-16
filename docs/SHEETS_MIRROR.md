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
