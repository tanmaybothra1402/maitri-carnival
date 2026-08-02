# Bulk barcode mapping — runbook

Attach the MC-#### QR stickers to designs and record which sticker went on which
design, so scanning a sticker at the counter pulls up the right design. Today only
~50 of ~593 active designs have a sticker; the rest must be mapped before the event.

**This is a desk task, not an engineering task.** No code, no developer needed.

## The file

`barcodes/barcode-list.csv` — two columns:

| Column | Meaning | State |
|---|---|---|
| `barcode` | The code printed on the sticker, e.g. `MC-0001` | Already filled (MC-0001 … MC-1000) |
| `designNo` | The design the sticker goes on, e.g. `MU - 0322` | **Blank — you fill this** |

(Regenerate the sheet + CSV any time with `node scripts/make-qr-sheets.js`.)

## How mapping works — you do NOT scan first

The pairing is **arbitrary and yours to choose**. At a desk:

1. Decide "sticker **MC-0123** goes on design **MU - 0322**".
2. Write `MC-0123,MU - 0322` in the CSV.
3. Stick MC-0123 on that garment.

That's it. The CSV **is** the record — you never scan to create a mapping. Scanning
happens later, at the counter. Type the design number exactly as it appears in the
catalogue, including the spaces around the dash (`MU - 0322`, not `MU-0322`).

## Importing (admin console → Products → Mapping → Bulk import)

1. Fill the `designNo` column for the stickers you've assigned. Leave unused rows
   blank — they're skipped.
2. Copy the filled rows and **paste** them into the Bulk import box, **or** click
   **Choose CSV…** and pick the file.
3. Click **Check rows**. It reports "**N ready · M to fix**". Fix the M (below),
   then Check again.
4. Click **Import**. It saves in batches of 250 (so 543 rows = 3 batches) and
   reports "**N mapped · M failed**", with any failures listed to fix and re-import.

## What each "to fix" / failure means

| Message | What to do |
|---|---|
| **missing barcode or design** | A column is empty — fill both. |
| **duplicate barcode in file** | The same MC-#### is pasted twice. Keep one. |
| **unknown design "X"** | No such design number. Check spelling and the spaces around the dash. |
| **design "X" is inactive** | The design is switched off. Have Products activate it, or map a different design. |
| **BARCODE_ALREADY_MAPPED** | That sticker is already mapped to a **different** active design. It must be deactivated before it can be re-pointed. (The 50 test stickers MC-0001…MC-0050 are in this state until they are cleared.) |

## Safe to re-run

Re-importing the same file is **safe**. A row already mapped to the **same** design
comes back "Unchanged" and does nothing. So you can import in passes as you fill in
more rows over the day.

## Do NOT map from the Google Sheet

The Sheet shows `barcode_mappings` **read-only on purpose**. A Sheet push writes
straight to the database and **skips the safety check** that stops a sticker being
silently re-pointed to the wrong design — the same class of problem as bypassing
the order writer. Always map through the **Bulk import** screen, never by editing
the Sheet.

## Confirm you're done

After importing, run this query (or ask an engineer to):

```sql
select count(*) from designs d where d.active and not exists (
  select 1 from barcode_mappings m
  where m.design_no = d.design_no and m.active);
```

It counts active designs with **no** active sticker. **Target: 0.** It is 543 today.
