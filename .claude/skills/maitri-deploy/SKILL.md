---
name: maitri-deploy
description: Deploy changes to the Maitri exhibition app — migrations, Edge Functions, GitHub Pages, and the Google Sheet mirror. Use when shipping a change, when a fix "isn't showing up", when staff report an old version, or when planning what must be deployed for a given change. Includes cache-busting and the production check list.
---

# Deploying

Four independent artifacts. Most changes touch two or three, and deploying only
one leaves the app half-updated with confusing symptoms — typically the HTML
calling a function or column that does not exist yet.

**Always start by listing what the change touched:**

| Changed | Deploy with |
|---|---|
| `supabase/migrations/*` | `npx supabase db push` |
| `supabase/functions/<n>/*` | `npx supabase functions deploy <n> --no-verify-jwt` |
| `web/*.html` | `git push` (GitHub Actions publishes `web/`) |
| `apps-script/DataSync.gs` | Paste into the Apps Script editor manually |

## Standard sequence

```bash
cd ~/Documents/maitri-carnival

# 1. Schema first — functions and pages may depend on it
npx supabase db push

# 2. Only the functions that changed
npx supabase functions deploy admin-api    --no-verify-jwt
npx supabase functions deploy customer-auth --no-verify-jwt
npx supabase functions deploy data-sync    --no-verify-jwt
npx supabase functions deploy design-image --no-verify-jwt
npx supabase functions list

# 3. Pages — for a web/admin-*.html change, run the pre-push gate FIRST:
node tests/admin-save-markers.js   # must be all-green (see "Pre-push gate" below)
git add -A && git commit -m "…" && git push
```

## Pre-push gate: admin order-save markers

Before pushing any change to `web/admin-*.html`, run:

```bash
node tests/admin-save-markers.js
```

It must print all-green. This guards the marker-less-payload data-loss path
(`maitri-guardrails` §B5): a marker-less admin order payload is a full-cart
*replace* and deletes every line not in it. The test asserts there is exactly one
`assistedSaveOrder` call and that it lives inside the `sendAdminSave` choke point,
and that every payload the helper emits carries `_op`.

This is **pre-push discipline, not CI.** Do **not** wire it into the GitHub Pages
workflow — between now and 14 Aug a failing or flaky test that blocks an emergency
fix from reaching the floor is worse than the bug it guards. Revisit CI
enforcement (and server-side `_op` enforcement) after the event. Needs the `jsdom`
devDependency (`npm install`).

All functions are `--no-verify-jwt` because each performs its own auth: admin-api
checks `app_metadata.role`, data-sync checks a shared secret, design-image is
intentionally open (it only returns already-degraded bytes, and `<img src>` cannot
send an Authorization header).

Required deployed secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `SHEET_SYNC_SECRET`, and `ALLOWED_ORIGINS` containing
the Pages origin.

## Verify the deploy actually landed

Do not trust a refresh. Check the server:

```bash
curl -s "https://<user>.github.io/<repo>/admin-<random>.html" | grep -c "<string-only-in-the-new-build>"
```

Non-zero = the new file is live and any remaining problem is local caching.
Zero = Pages has not published; check the repo's **Actions** tab for a green tick
on *pages build and deployment*.

If Actions is green but the site is stale, check **Settings → Pages → Source**. It
must be **GitHub Actions**, not *Deploy from a branch* — otherwise the workflow
builds an artifact that Pages ignores and serves an old publish indefinitely.

## Cache-busting

GitHub Pages sets `max-age=600` on HTML. The pages carry no-cache meta tags, but
those are advisory — real HTTP headers win.

- Definitive local test: **private/incognito window**.
- Force a fresh copy: append `?v=N` and bump N. A URL the browser has never seen
  cannot come from cache. This is the only reliable method on iPads, where
  hard-refresh does nothing.
- In Chrome: DevTools open → right-click reload → **Empty Cache and Hard Reload**.
  Plain `Cmd+Shift+R` often leaves the HTML document itself cached.

**Distribute a `?v=N` link to staff after any mid-event deploy.** Anyone who
opened the console earlier is running the old build, and during an event that
means missing modules and missing fixes.

## Verifying a schema change reached the database

```sql
select routine_name from information_schema.routines
where routine_schema='public' and routine_name in ('fn_a','fn_b');
```

Zero rows means `db push` never applied — which usually also means the HTML is
calling something that does not exist.

## Production checks

Run after any significant deploy. These are the paths that have actually broken.

1. Customer registration and login work.
2. Team login accepted only for `app_metadata.role` in (`admin`,`staff`).
3. Entry check-in unlocks ordering.
4. Two stale devices adding different designs preserve both additions.
5. Explicit deletion removes only the selected design.
6. Notes persist after refresh and appear in admin detail and the PDF.
7. Total pieces equals the sum of `sets × pcs_per_set`.
8. Sale-order PDF completes even when one product image fails to fetch.
9. An expired order reopened by staff can be saved from the customer page.
10. Customer thumbnails are identifiable but detail does not survive zooming.
11. `GET /rest/v1/designs?select=image_url` with a customer token is refused.
12. No `ik.imagekit.io` request appears in the customer page's network tab.
13. Ticking a design in Dispatch blocks the customer from editing it.
14. Reopening a dispatched order still does not unlock the dispatched line.
15. Setting a dispatched line back to 0 sets restores normal editing.
16. Mapping typeahead finds a design from any substring of its number.
17. Scanning an already-mapped barcode is refused **at scan time**.
18. A batch of mappings saves in one call; failures stay queued.
19. A dispatch-only staff member sees only Dispatch, with no gap in the nav.
20. Sheet deletes show a named confirmation and respect the ceiling.
21. `select count(*) from designs where active` returns the expected count.

Check 21 sounds trivial and is not — a bulk import once deactivated the entire
catalogue, which would have failed every barcode scan at the event.

## Highest-value end-to-end test

Map one real printed sticker, then log in as a test customer and scan it.
Confirm the design appears with a readable thumbnail and reaches the PDF. That
single path exercises `lookup_barcode`, `design-image`, the mapping guard and the
order writer at once.

## Post-event

```sql
update public.system_settings set registration_enabled = false where singleton = true;
update public.orders set status = 'Locked', admin_unlocked = false where status <> 'Locked';
```

Note that a blanket status update can clobber derived columns — `dispatch_status`
is deliberately a separate column so this does not destroy dispatch state.

## See also

- `maitri-architecture` — the hub; the artifacts a change can span (migration, functions, HTML, Sheet).
- `maitri-frontend` — GitHub Pages caching and the `?v=N` cache-busting scheme.
- `maitri-migration` — ship a migration with the functions whose signatures it changes.
- `maitri-sheet-sync` — redeploying `data-sync` and re-pasting `DataSync.gs`.
- `maitri-guardrails` — the GATE; run it before every deploy.
