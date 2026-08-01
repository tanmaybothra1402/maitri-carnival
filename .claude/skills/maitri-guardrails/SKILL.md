---
name: maitri-guardrails
description: Review a change to the Maitri exhibition app against the failure modes that have actually broken it in production. Use before deploying, after writing a migration or Edge Function change, when reviewing a diff, or when something works locally but fails live. Every item here is a real bug that shipped.
---

# Maitri guardrails — real failure modes

Each entry below is a bug that reached the live app. Check the current change
against every relevant section. Report findings as **BLOCKER / HIGH / MEDIUM /
LOW / VERIFIED CORRECT**.

---

## A. Privilege leaks

### A1. `grant … to authenticated` includes every customer
Customers are authenticated Supabase users. A grant meant for "logged-in staff"
hands the table to buyers.

**What happened:** an early migration ran `grant select on public.designs to
authenticated`. Customers could call
`GET /rest/v1/designs?select=design_no,image_url` and download every master
product photograph URL. Months later the app was carefully changed to serve
blurred images — while that grant was still open, making the entire effort
decorative.

**Check:** for every `grant` in the diff, ask whether a customer hitting PostgREST
directly should be able to read that. If not, revoke it and route through a
`SECURITY DEFINER` function.

### A2. Revoking a grant breaks non-definer functions
A `stable` function without `security definer` runs with the *caller's*
privileges. Revoke the underlying table grant and it starts failing for exactly
the users it was written for.

**Check:** when revoking a table grant, grep for every function reading that table
and promote it to `SECURITY DEFINER` in the **same** migration.

### A3. Actions without permission entries are unprotected
`admin-api` gates on `ACTION_PERMISSIONS[action]`. An action missing from that map
has `alternatives.length === 0` and passes the check.

**Check:** every new `if (action === "…")` has a matching `ACTION_PERMISSIONS` key.

---

## B. Silent data destruction

### B1. Blank spreadsheet cell coerced to `false`
`data-sync` coerced empty cells by column type; `active` is boolean, so blank
became `false`.

**What happened:** a 450-design catalogue import left the `active` column blank.
Every design was imported deactivated. `lookup_barcode` requires `active = true`,
so **every barcode scan at the event would have failed.** It surfaced only as "the
dropdown is empty".

**Check:** any column where blank plausibly means "unchanged" or "yes" must be in
`BLANK_MEANS_TRUE` or excluded from coercion. Never let a blank cell disable
something.

### B2. Diff-based deletion against a stale sheet
"Row missing from the sheet = delete it in the database" is destructive by
default. Pull at 10am, push at 2pm, and every customer who registered in between
is absent from the sheet and therefore deleted — cascading to their orders and
dispatch records.

**Check:** deletion requires all four rails — freshness token, delete ceiling,
named confirmation, protected-row list. See `maitri-sheet-sync`.

### B3. Service-role writes bypass every business rule
`data-sync` writes with the service role, straight past `_write_order`. While
`order_items.qty` was Sheet-editable, someone could change a line that had already
shipped, past the edit window and the dispatch lock.

**Check:** any table whose writes have business rules must be **read-only** in the
Sheet, or route its push through the guarded function.

### B4. Upsert with duplicate keys in one command
Postgres: `ON CONFLICT DO UPDATE command cannot affect row a second time` (SQLSTATE
21000). Nothing is written. The raw error names no row, which is useless in a
450-row import.

**Check:** de-duplicate by primary key before upserting and name the offending
keys in the error.

---

## C. Shared-function regressions

**This is the most common way this codebase breaks.** Before changing any shared
function, list every caller.

### C1. `lookup_barcode` served both customer and admin
It was changed to stop returning `image_url` (correct, for customer privacy). The
admin Sale Order screen scanned through the same function — staff thumbnails went
blank and the admin PDF had no images.

**Fix pattern:** admin gets full-resolution data from the service-role API
(`listDesigns`), never from a customer-reachable RPC.

### C2. `addEventListener` passes an Event as the first argument
`downloadAdminOrderPdf()` was given an optional `source` parameter so Dispatch
could reuse it. The existing button was wired with
`addEventListener("click", downloadAdminOrderPdf)` — so `source` became a click
Event, which was treated as an order and threw.

**Check:** when adding a first parameter to a function used as an event handler,
either validate the shape (`source && source.order && source.customer`) or wrap
the handler in an arrow function.

### C3. Hardcoded section/module lists in more than one place
Adding the Dispatch module required updating `allowedSections` and
`modulePermission` in **both** `createStaff` and `updateStaff`, plus two CHECK
constraints, plus the nav, plus `TEAM_GROUPS`. Missing any one fails silently or
rejects every save.

**Check:** grep for the other members of the list (`"products"`, `"reception"`)
and confirm every occurrence was updated.

---

## D. UI that fails invisibly

### D1. Filtering to an empty list renders nothing
The mapping typeahead filtered out inactive designs. When a bulk import
deactivated the whole catalogue, it rendered an empty dropdown with no
explanation — indistinguishable from broken code, and it cost hours of debugging
the wrong thing.

**Check:** an empty result must render a *reason*, never nothing. Show inactive
items labelled rather than hiding them.

### D2. Retry loops that never terminate
An "empty list → reload → re-render" fix looped forever when the reload
legitimately returned nothing, hanging on "Loading…".

**Check:** retry at most once, then report.

### D3. Errors surfaced only at save time
Scanning an already-mapped barcode was accepted and only rejected when the whole
batch saved. On a floor, feedback must arrive at the moment of the action.

**Check:** validate at input, not at submit. The server still enforces.

### D4. Nested `<script>` tags in paste-in snippets
A snippet wrapped in `<script>…</script>`, pasted inside the existing script
block, closed it early. The literal `<script>` became a syntax error and killed
every line of JS below it.

**Check:** paste-in snippets are always bare JS, no wrapper tags.

### D5. Conflicting CSS on the same class
A base `.sale-item{display:grid;grid-template-columns:64px …}` crushed a later
card layout, wrapping text character-by-character.

**Check:** grep the class name across the whole file — these are single-file apps
with long stylesheets and duplicate selectors are easy to miss.

---

## E. Deployment and caching

### E1. GitHub Pages caches HTML for ~10 minutes
Staff who opened the console yesterday keep running yesterday's build. Cache-control
meta tags help but are advisory — real HTTP headers win.

**Check:** after deploying, verify with
`curl -s <url> | grep -c "<a-string-only-in-the-new-build>"`. Distribute a
`?v=N` link to staff and bump N. A private window is the definitive local test.

### E2. Migrations and functions deploy separately
A feature usually needs `npx supabase db push` **and**
`npx supabase functions deploy <name>`. Doing one leaves the app half-updated,
often with confusing symptoms (function calls a function that does not exist yet).

**Check:** list every artifact the change touches — migration, each function, HTML,
Apps Script — and confirm each is deployed.

---

## F. Verification commands

Run these; do not eyeball.

```bash
# HTML: script syntax + every $("id") resolves
python3 - <<'PY'
import re,subprocess
for p in ["web/user.html","web/admin-<random>.html"]:
    s=open(p,encoding='utf-8').read()
    js="\n;\n".join(re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>',s,re.S))
    open('/tmp/c.js','w').write(js)
    r=subprocess.run(['node','--check','/tmp/c.js'],capture_output=True,text=True)
    ids=set(re.findall(r'\bid="([^"]+)"',s)); used=set(re.findall(r'\$\(\s*"([^"]+)"\s*\)',s))
    print(p,"syntax:","OK" if r.returncode==0 else r.stderr[:300],
          "| unresolved:",sorted(u for u in used if u not in ids) or "none")
PY

# SQL parses
pip install pglast --break-system-packages -q
python3 -c "from pglast import parse_sql; import glob
for p in sorted(glob.glob('supabase/migrations/*.sql')):
    parse_sql(open(p).read())
print('migrations parse')"

# TypeScript parses
npx esbuild supabase/functions/<name>/index.ts --bundle --format=esm --outfile=/dev/null

# Apps Script
cp apps-script/DataSync.gs /tmp/ds.js && node --check /tmp/ds.js
```

For behavioural checks, drive the real page headlessly with `jsdom` rather than
reasoning about it — stub `supabase.createClient`, `Chart`, and `crypto`, eval the
script blocks, then dispatch real events and assert on the DOM. This caught
several bugs that looked correct on inspection.

---

## G. Standing constraints

- This is a **live exhibition environment**. Never create or delete records in
  bulk without isolation. Test data uses an obvious prefix (`STRESS-`, `TEST-`).
- Never display, copy into reports, log, or commit the service-role key or
  `SHEET_SYNC_SECRET`.
- Only delete records created by your own test.
- **Creating a test `auth.users` row directly via SQL?** Set the token columns
  (`confirmation_token`, `recovery_token`, `email_change`,
  `email_change_token_new`, `email_change_token_current`, `phone_change`,
  `phone_change_token`, `reauthentication_token`) to **empty strings, not NULL**.
  A NULL token column makes GoTrue sign-in fail with `AuthRetryableFetchError`
  and a generic 500 — the row looks correct in SQL but GoTrue cannot scan it.
  Also set `aud`/`role` to `'authenticated'`, an `email_confirmed_at`, and a
  bcrypt `encrypted_password` via
  `extensions.crypt(pw, extensions.gen_salt('bf'))`. (Lost real time to this.)
- Runtime verification against the real database is the operator's to run — say so
  plainly rather than implying something was tested when it was not.

---

## See also

This is the GATE — the review pass before every deploy. The skills each section
maps back to:

- `maitri-architecture` — the hub; the choke points these bugs bypass.
- `maitri-orders` — §C shared writers; the merge-safe write path and dispatch lock.
- `maitri-media` — §A1 the `authenticated` image-URL leak.
- `maitri-frontend` — §D UI failure modes and §F the verification commands.
- `maitri-migration` — §A grants and CHECK constraints.
- `maitri-sheet-sync` — §B blank-cell coercion and stale-sheet deletion rails.
- `maitri-deploy` — §E caching and split migration/function deploys.
