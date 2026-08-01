# Setup — multi-exhibition build

Follow in order. Each step is verifiable; do not proceed past a failed check.

---

## Target folder structure

```
maitri-exhibitions/
├── CLAUDE.md                      ← project memory, auto-loaded by Claude Code
├── README.md
├── package.json
│
├── .claude/
│   └── skills/                    ← Claude Code reads ONLY this path
│       ├── maitri-architecture/SKILL.md
│       ├── maitri-guardrails/SKILL.md
│       ├── maitri-migration/SKILL.md
│       ├── maitri-deploy/SKILL.md
│       └── maitri-sheet-sync/SKILL.md
│
├── .github/workflows/pages.yml    ← publishes web/ to GitHub Pages
│
├── web/                           ← everything here is deployed publicly
│   ├── index.html                 (redirects to user.html)
│   ├── user.html                  customer app
│   ├── admin-<random>.html        team console — unguessable filename
│   └── assets/                    logos
│
├── supabase/
│   ├── config.toml                verify_jwt = false per function
│   ├── .env.production            GITIGNORED — service role key
│   ├── migrations/                cumulative, numbered, never rewritten
│   └── functions/
│       ├── _shared/               cors.ts, http.ts, secure.ts, supabase.ts
│       ├── customer-auth/         registration + login
│       ├── admin-api/             every staff action
│       ├── data-sync/             Google Sheets mirror
│       └── design-image/          degraded customer images
│
├── apps-script/
│   ├── DataSync.gs                paste into the workbook's Apps Script editor
│   └── SHEET_SYNC_SECRET.txt      GITIGNORED
│
├── scripts/
│   ├── make-qr-sheets.js          A3 barcode sheets, 120/page
│   └── make-customer-qr.js        table-tent QR for the customer link
│
├── docs/
│   ├── SETUP.md                   this file
│   ├── MULTI_EXHIBITION_BLUEPRINT.md
│   ├── DEPLOY_CARNIVAL.md         runbook
│   └── SHEETS_MIRROR.md
│
├── templates/                     CSV/XLSX import templates
└── barcodes/                      generated PDFs — consider gitignoring (9 MB)
```

### Housekeeping before starting

`chatgpt-upload/` and `tests/` are dead. `supabase/functions/sheet-sync/` is a
legacy product importer superseded by `data-sync`. `DEPLOY_THIS_UPDATE.md` and
`IMPLEMENTATION_NOTES.md` are stale notes. Remove them so Claude Code is not
reading contradictory instructions:

```bash
cd ~/Documents/maitri-carnival
git rm -r --cached chatgpt-upload tests 2>/dev/null
rm -rf chatgpt-upload tests DEPLOY_THIS_UPDATE.md IMPLEMENTATION_NOTES.md
echo "barcodes/" >> .gitignore
git rm -r --cached barcodes 2>/dev/null
```

Leave `supabase/functions/sheet-sync/` for now — deleting a deployed function
needs `npx supabase functions delete sheet-sync` too, and it is harmless.

---

## Step 1 — Install the skills

`.claude/skills/` is the only path Claude Code reads.

```bash
cd ~/Documents/maitri-carnival
mkdir -p .claude/skills
mv claude-skills/maitri-* .claude/skills/
mv claude-skills/CLAUDE.md .
mv claude-skills/NEW_EXHIBITION_SETUP.md docs/
rmdir claude-skills
```

**Verify:** open Claude Code in this folder and run `/skills`. All five
`maitri-*` skills must be listed. If they also appear when you open an unrelated
project, they were installed globally — remove them from `~/.claude/skills/`.

---

## Step 2 — Back up before touching the database

Non-negotiable. The migration rewrites constraints on tables holding real orders.

```bash
cd ~/Documents/maitri-carnival
npx supabase db dump -f backup-pre-multi-exhibition.sql --data-only
ls -lh backup-pre-multi-exhibition.sql
echo "backup-*.sql" >> .gitignore
```

**Verify:** the file exists and is not near-empty. Open it and confirm you can see
customer and order rows.

---

## Step 3 — Record the current state

You need these numbers to prove the backfill worked in Step 5.

```sql
select 'customers' t, count(*) from public.customers
union all select 'orders',           count(*) from public.orders
union all select 'order_items',      count(*) from public.order_items
union all select 'slots',            count(*) from public.slots
union all select 'bookings',         count(*) from public.bookings
union all select 'barcode_mappings', count(*) from public.barcode_mappings
union all select 'designs',          count(*) from public.designs
union all select 'dispatch_lines',   count(*) from public.dispatch_lines
order by 1;
```

Save the output somewhere you can see it during Step 5.

---

## Step 4 — Commit a clean baseline

So you can `git revert` in one command if Phase 1 goes wrong.

```bash
git add -A
git commit -m "Baseline before multi-exhibition refactor"
git push
git rev-parse --short HEAD          # note this hash
```

---

## Step 5 — Phase 1: the migration

Written as `supabase/migrations/202608010001_multi_exhibition.sql`.

It is additive and ordered so nothing breaks mid-way:

1. Create `exhibitions`
2. Seed **Maitri Carnival 2026** from `system_settings`, `is_current = true`
3. Add `exhibition_id` columns as **nullable**
4. Backfill every existing row to that exhibition
5. **Verify counts, then** set `not null` + foreign keys + new unique constraints
6. Drop `unique (phone_e164)`
7. Recreate the ~12 affected functions
8. Leave `system_settings` in place, unused, for one release

Apply:

```bash
npx supabase db push
```

**Verify before going further:**

```sql
-- Nothing orphaned. Every count must be 0.
select 'customers'        t, count(*) from public.customers        where exhibition_id is null
union all select 'orders',   count(*) from public.orders           where exhibition_id is null
union all select 'slots',    count(*) from public.slots            where exhibition_id is null
union all select 'mappings', count(*) from public.barcode_mappings where exhibition_id is null;

-- Exactly one current exhibition.
select count(*) from public.exhibitions where is_current;   -- must be 1

-- Totals match Step 3 exactly.
```

If any count differs from Step 3, **stop and restore**. Do not continue.

---

## Step 6 — Phase 2: `admin-api`

Ships **with** Phase 1, never after. The migration changes function signatures
that `admin-api` calls; deploying one without the other breaks the console.

```bash
npx supabase functions deploy admin-api --no-verify-jwt
```

---

## Step 7 — Phases 3–5

- Admin console: exhibition selector + Admin → Exhibitions screen
- Customer app + `customer-auth`: slug-based emails, current-exhibition scoping
- `data-sync`: mirror `exhibitions`, add read-only `exhibition_id` columns

```bash
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions deploy data-sync     --no-verify-jwt
npx supabase functions deploy design-image  --no-verify-jwt
git add -A && git commit -m "Multi-exhibition support" && git push
```

---

## Step 8 — Verify

Run the full list in `docs/DEPLOY_CARNIVAL.md`, plus these:

1. Carnival data is intact and visible under the Carnival exhibition.
2. Creating a second exhibition and setting it current does not alter Carnival.
3. A phone that registered at Carnival **can** register again in the new
   exhibition, and gets a different login.
4. A Carnival barcode does **not** resolve when the new exhibition is current.
   *This is the most important check in the list.*
5. Dashboard filtered to the new exhibition shows zero orders, not Carnival's.
6. Reception, Sale Order and Dispatch all respect the selected exhibition.
7. Switching the current exhibition requires a typed confirmation.

Check 4 is the one that costs you real money if it is wrong — a leftover sticker
scanning into the wrong event corrupts the order silently.

---

## Rollback

```bash
git revert <hash-from-step-4>
npx supabase db reset --db-url <url>   # then reapply the backup
psql <url> -f backup-pre-multi-exhibition.sql
```

Because `system_settings` is left in place through this release, reverting the
code alone restores working behaviour for the Carnival exhibition without a
database restore. That is the point of leaving it.

---

## Creating the next exhibition once this is live

1. Admin → Exhibitions → Create. Name, slug, dates, edit window.
2. **Do not** set it current until you are ready — registrations follow the flag.
3. Add slots for the new dates.
4. Print new barcode sheets: `node scripts/make-qr-sheets.js`
5. Map stickers with the new exhibition current.
6. Set current on the morning of day one, with the typed confirmation.

Designs carry over automatically. Customers, orders, slots, bookings and mappings
all start empty.
