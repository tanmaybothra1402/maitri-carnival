# Maitri exhibition ordering app

Wholesale garment-exhibition ordering for **EKUM** (parent) and its firms
**Maitri** and **Niharika**. Customers register, are checked in at a gate, scan
barcodes to build per-firm orders, and edit within a time window. Staff run
reception, sales, products, dispatch and admin from a separate console.

**This runs live at a physical exhibition.** Data loss is not recoverable and
downtime happens with a hall full of buyers. Prefer refusing an action over
performing a destructive one.

## Stack

Supabase (Postgres + RLS + Auth + Deno Edge Functions) and single-file static
HTML on GitHub Pages. **No build step**, `supabase-js` from CDN. Deliberate — one
person must be able to edit and deploy under event pressure.

## Skills

Read the relevant skill before starting. They encode decisions and real bugs, not
generic advice. `maitri-architecture` is the **hub** — read it first; it routes you
to the branch that owns your change.

| Skill | When |
|---|---|
| `maitri-architecture` | **Hub.** Before designing any feature. Auth, permissions checklist, barcodes, and the branch map. |
| `maitri-orders` | The order write path — `_write_order`, merge-safe ops, dispatch lock, multi-customer batching. |
| `maitri-media` | Product images — ImageKit, the shared egress budget, signed uploads, no customer images. |
| `maitri-frontend` | Editing `web/*.html` — single-file conventions and the mandatory verification suite. |
| `maitri-migration` | Any schema or RPC change. |
| `maitri-sheet-sync` | The Google Sheets mirror and bulk imports. |
| `maitri-deploy` | Shipping, or "my fix isn't showing up". |
| `maitri-guardrails` | **Gate.** Before deploying, or reviewing a diff. Every failure mode that has shipped. |

## The five things most likely to break

1. **`grant … to authenticated` leaks to customers.** They are authenticated
   users. This exposed every master product image URL once.
2. **Shared functions have more callers than you think.** `lookup_barcode` served
   customer *and* admin. `downloadAdminOrderPdf` was called directly *and* as an
   event handler. Both broke when changed for one caller. Trace all callers first.
3. **Blank spreadsheet cells become `false`.** A bulk import deactivated 450
   designs and would have failed every barcode scan at the event.
4. **Module lists are hardcoded in five places.** Adding one and missing any of
   them fails silently or rejects every staff save.
5. **GitHub Pages caches HTML for ten minutes.** Verify with `curl`, distribute
   `?v=N` links, and never assume a refresh worked.

## Verification is not optional

The HTML files are large single files where one syntax error kills the app
silently. After editing, extract the script blocks and `node --check` them, and
confirm every `$("id")` resolves. For behaviour, drive the real page with `jsdom`
rather than reasoning about it. Commands are in `maitri-guardrails` §F.

**Runtime verification against the live database is the operator's to run.** Say
so plainly. Never imply something was tested against real data when it was not.

## Secrets

`supabase/.env.production` and `apps-script/SHEET_SYNC_SECRET.txt` are gitignored.
Never display, log, commit, or paste a service-role key or sync secret into chat.
Read them only to construct a command, and pipe rather than print.

## Communication

The people using this are on a noisy floor, on phones and tablets, often mid-sale.
Error messages must say what to do next, not name an error code. Snippets meant
for pasting must be bare — a stray `<script>` tag has broken the whole console
before.
