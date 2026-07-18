
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
| Designs | firm, image_url, category, style, fabric, pcs_per_set, description, active | Yes (give a new DesignNo) |
| BarcodeMappings | design_no, active | Yes (give a new barcode) |
| Customers | company_name, contact_name, city, state, gstin, agent, active | No (created by registration) |
| Orders | status, admin_unlocked | No |
| OrderItems | Read-only | No |
| Slots | starts_at, ends_at, label, capacity, active | Yes (leave id blank) |
| Bookings | party_size, note, status, slot_id | No |
| Staff | Read-only | No |
| Settings | event_name, event dates, registration_enabled, edit_window_hours | No |

## Deleting rows

Deleting a row from the sheet and pushing **permanently deletes it in Supabase**. This works on Designs, BarcodeMappings, Slots, Customers, Orders and OrderItems.

This is genuinely destructive, so four rails sit in front of it:

1. **Fresh pull required.** Pulling stamps the tab with a token describing the table's state. If anything changed in the app since, the push is rejected with *"This tab is out of date"* before a single row is touched. This is the rail that matters: without it, pulling at 10am and pushing at 2pm would delete every customer who registered in between.
2. **Delete ceiling.** A single push may delete at most 25 rows, or 10% of the table, whichever is smaller. Exceeding it almost always means the sheet is filtered or incomplete.
3. **Named confirmation.** You are shown the exact rows that will be deleted, by key, and must confirm.
4. **Protected rows.** Some rows can never be deleted from the Sheet, whatever the token says:

| Table | Protected |
|---|---|
| Customers | Checked in, started ordering, or has any order with designs |
| Orders | Has any designs on it |
| OrderItems | Already dispatched |
| Designs | Appears on any order |
| BarcodeMappings | Already scanned onto an order |
| Slots | Has a live booking |

For these, use `active` or `status` instead. Deactivating is almost always what you actually want during the event.

**The token is spent after any push that deletes.** Pull again before the next one.

## Editing rules

- **Pull first**, edit, then **Push this tab** (push only affects the active tab).
- **Add a design:** new row with a unique `design_no` + firm + category + style + fabric + pcs_per_set (+ image_url). Push.
- **Product images:** put the ImageKit link in `image_url` on the Designs tab and push — that's how images get attached.
- **OrderItems is read-only.** A Sheet push runs with the service role and would bypass `_write_order`, defeating the 24-hour edit window, the order lock and the dispatch lock — you could have edited a line that had already shipped. Change order lines in the admin console instead.
- Dates/times must be full timestamps (e.g. `2026-07-19T10:00:00+05:30`) for slots/settings.

## Safety notes

- The push only touches editable columns, so you can't accidentally corrupt ids or versions.
- Customers/Orders/OrderItems are update-only (no new rows) — orders are created by the app.
- **During the event, prefer `active`/`status` over deletion.** The rails make deletion survivable, not safe. A deleted customer takes their orders and dispatch records with them and there is no undo.
- Never push a tab you have filtered or sorted without pulling first.
- Keep the `SHEET_SYNC_SECRET` private; anyone with it and the URL can read/write data.
