---
name: maitri-sheet-sync
description: Conventions for the Google Sheets two-way mirror in the Maitri exhibition app (data-sync Edge Function + DataSync.gs). Use when adding a table or column to the mirror, changing what is editable from the Sheet, debugging a push or pull error, or working on bulk catalogue imports.
---

# Google Sheets two-way mirror

**Supabase is the master.** The workbook pulls every table into tabs, lets you
edit, and pushes back. Two parts:

- `supabase/functions/data-sync/index.ts` — secret-gated Edge Function
- `apps-script/DataSync.gs` — the Sheet menu

Auth is a shared secret in the `x-sheet-sync-secret` header, compared with
`secureEqual` (constant time). The repo copy of `DataSync.gs` keeps
`const DS_SECRET = ''` so the key is never committed; the real key lives in
`apps-script/SHEET_SYNC_SECRET.txt`, which is gitignored.

To hand the operator a ready-to-paste copy without printing the secret:

```bash
sed "s|^const DS_SECRET = '';.*|const DS_SECRET = '$(tr -d '\n' < apps-script/SHEET_SYNC_SECRET.txt)';|" \
  apps-script/DataSync.gs | pbcopy
```

## Table configuration

Each table has a `TableCfg` in `data-sync`:

```ts
designs: {
  pk: "design_no",
  cols: [...],    // shown on pull (plus any new DB columns, auto-discovered)
  write: [...],   // ONLY these are written on push
  hide: ["color"],// legacy columns kept out of the Sheet
  insert: true,   // may new rows be created?
}
```

`pull` uses `select("*")` so a newly added database column appears in the Sheet
automatically. `push` writes only whitelisted columns, so ids, versions and
timestamps cannot be corrupted from a spreadsheet.

Mirror the same `write` lists in `DS_EDITABLE` in `DataSync.gs` — they must agree
or the UI tints columns the server will ignore.

### What must stay read-only

**`order_items` is read-only** (`write: []`). Sheet pushes run with the service
role and bypass `_write_order` entirely — that means the 24-hour edit window, the
order lock and the dispatch lock are all defeated. Someone could edit the quantity
of a line that had already shipped.

The rule generalises: **any table whose writes have business rules must be
read-only in the Sheet**, or its push must route through the guarded function.

`staff_profiles` is mirrored read-only for visibility only.

## Coercion traps

`coerce()` converts spreadsheet cells to database values by column name.

**A blank cell in a boolean column used to become `false`.** A 450-design import
left `active` blank and imported the entire catalogue deactivated —
`lookup_barcode` requires `active = true`, so every barcode scan at the event
would have failed.

`BLANK_MEANS_TRUE` now protects `active`. Any new column where blank plausibly
means "unchanged" or "yes" must be added there, or excluded from coercion. Never
let an empty cell disable something.

Other traps:
- Dates must be full timestamps (`2026-07-19T10:00:00+05:30`). Apps Script sends
  `Date` objects, converted with `toISOString()`.
- Integer columns reject decimals and text — validate and name the offending row.
- Duplicate primary keys within one push cause
  `ON CONFLICT DO UPDATE command cannot affect row a second time` (SQLSTATE 21000)
  and write **nothing**. De-duplicate first and name the duplicate keys, because
  the raw error identifies no row.

## A NOT NULL column breaks upsert — for existing rows, not just inserts

`push` upserts with `onConflict` (INSERT … ON CONFLICT DO UPDATE). When a migration
adds a `NOT NULL` column to a mirrored table, the instinct is "stamp it on new
rows." That is not enough: PostgREST sends the **whole** record on every upsert, so
an update of an *existing* row also omits the new column and fails the NOT NULL
check — the mirror stops writing that table entirely, not just refusing inserts.

The wrong fix is to add the column to the upsert record. On `ON CONFLICT DO UPDATE`
that **overwrites** the existing value, silently re-homing a row to whatever the
Sheet-side default said — exactly the untrusted-source assignment the column was
added to prevent. Instead **split the two paths**:

- existing row (pk already present) → `UPDATE`, writing only the whitelisted `write`
  columns, never the scope column;
- new row (no pk) → `INSERT`, with the scope column stamped **server-side** from the
  database (e.g. `select id from exhibitions where is_current`), never from a cell.

**The `slots` case:** Phase 1's `NOT NULL exhibition_id` did exactly this. The first
fix compiled clean and looked right — and was still wrong, because it added
`exhibition_id` to the upsert and would have re-homed every edited slot to the
current exhibition. Only running the full pull → append → push cycle surfaced it.
Compile-clean is not correct here; exercise the round trip.

## Deletion — the four rails

Deleting a row from the Sheet and pushing **permanently deletes it in Supabase**,
for tables listed in `DIFF_DELETABLE`. This is genuinely destructive; all four
rails must remain in place.

1. **Freshness token.** `pull` returns a token (row count + newest `updated_at`),
   stored per tab in Document Properties. A push that would delete anything
   recomputes the token and refuses if the table has moved.
   *This is the rail that matters.* Without it, pulling at 10am and pushing at 2pm
   deletes every customer who registered in between — cascading to their orders
   and dispatch records, with no undo.
2. **Delete ceiling.** At most 25 rows, or 10% of the table, whichever is smaller.
   Exceeding it means the sheet is filtered or incomplete.
3. **Named confirmation.** A dry run (`dryRun: true`) returns `willDelete`; the
   Sheet lists the exact keys and requires a Yes.
4. **Protected rows.** Never deletable regardless of the token:

| Table | Protected when |
|---|---|
| customers | checked in, started ordering, or has an order with designs |
| orders | has designs |
| order_items | already dispatched |
| designs | appears on any order |
| barcode_mappings | already scanned onto an order |
| slots | has a live booking |

**A push that deletes nothing must not require a token.** Otherwise a bulk import
into a hand-typed sheet is rejected, and the obvious "fix" — pulling — overwrites
the operator's unsaved work. The freshness check is evaluated only once deletion
is actually implicated.

After any push that deleted, the token is cleared so a fresh pull is required
before the next deletion.

## Bulk imports

Pulling **clears the tab and rewrites it from Supabase**. Never pull a tab
containing hand-entered rows that have not been pushed — it destroys them. Say
this explicitly when advising an operator mid-import.

Pre-flight for a large catalogue import:
- `firm` must be exactly `Maitri`, `Niharika` or `Both` — case-sensitive, and the
  most common cause of a rejected push.
- `design_no` unique within the sheet **and** checked against existing rows; a
  collision silently overwrites rather than erroring.
- `pcs_per_set` a whole number 1–9999, or blank (defaults to 4 for new designs).
- The push aborts on the first bad row and writes nothing, so one typo in row 300
  means zero of 450 land. Re-pushing is safe — the primary key upserts.

## Error messages

Translate server codes into operator instructions in `dsExplain_()`. Codes like
`SHEET_IS_STALE_FOR_CUSTOMERS_PULL_AGAIN_BEFORE_PUSHING` should reach the user as
"This tab is out of date. Someone changed the data in the app since you last
pulled… Pull again, redo your edits, then push."

## After changing the mirror

- `cp apps-script/DataSync.gs /tmp/ds.js && node --check /tmp/ds.js`
- `npx esbuild supabase/functions/data-sync/index.ts --bundle --format=esm --outfile=/dev/null`
- Redeploy: `npx supabase functions deploy data-sync --no-verify-jwt`
- Re-paste `DataSync.gs` into the Apps Script editor — it does not deploy with the repo
- Update `docs/SHEETS_MIRROR.md`

## See also

- `maitri-architecture` — the hub; where the mirror sits and why writes bypass `_write_order`.
- `maitri-orders` — why order/`order_items` columns must stay read-only in the Sheet.
- `maitri-media` — product image URLs arriving via the Sheet import.
- `maitri-migration` — adding a table or column to the mirror is a schema change.
- `maitri-guardrails` — §B silent data destruction (blank-cell coercion, stale-sheet deletes).
