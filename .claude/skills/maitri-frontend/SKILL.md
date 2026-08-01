---
name: maitri-frontend
description: Single-file HTML conventions and mandatory verification for the Maitri exhibition app — no build step, supabase-js from CDN, extracting script blocks to node --check, confirming every $("id") resolves, driving behaviour with jsdom, bare paste-in snippets, and grepping a CSS class before adding it. Read this before editing web/user.html or the admin console, or writing paste-in JS.
---

# Maitri frontend — single-file HTML

The customer app (`web/user.html`) and the admin console (`web/admin-<random>.html`)
are **large single files**. One syntax error kills the whole app silently. These
conventions and the verification suite exist because each rule below is a bug that
shipped. Read this before editing either file.

## Conventions

- **No build step.** `supabase-js` loads from a CDN; there is no bundler, no
  transpile. Write browser-native JS that runs as-is.
- **Paste-in snippets are bare JS**, never wrapped in `<script>…</script>`. Pasted
  inside the existing script block, an inner `</script>` closes the block early and
  turns everything below it into a syntax error. (`maitri-guardrails` §D4.)
- **Grep a CSS class across the whole file before adding a selector for it.** These
  are single files with long stylesheets; a duplicate `.sale-item{…}` has silently
  crushed a later card layout. (`maitri-guardrails` §D5.)
- **Errors must say what to do next**, not name a code. The people reading them are
  on phones and tablets on a noisy floor, often mid-sale.
- **An empty list must render a reason, never nothing** — an empty dropdown is
  indistinguishable from broken code and has cost hours. Retry at most once, then
  report; never loop on reload. (`maitri-guardrails` §D1–D3.)
- **Validate at input, not at submit.** The server still enforces, but feedback
  must arrive at the moment of the action on a floor.

## Verification — not optional, do not eyeball

After editing an HTML file, run the suite (full commands in `maitri-guardrails`
§F). At minimum:

1. **Script syntax:** extract every `<script>` block (excluding `src=`), join, and
   `node --check`. A single syntax error kills the app.
2. **Every `$("id")` resolves:** collect `id="…"` attributes and `$("…")` uses;
   assert no `$(…)` references an id that does not exist in the DOM.
3. **Behaviour with jsdom:** stub `supabase.createClient`, `Chart`, and `crypto`,
   eval the script blocks, dispatch real events, and assert on the DOM. Drive the
   real page rather than reasoning about it — this caught bugs that looked correct
   on inspection.

State plainly that **runtime verification against the live database is the
operator's to run**. Never imply something was tested against real data when it was
not.

## Deploy caching gotcha

GitHub Pages caches HTML for ~10 minutes; a refresh is not proof. After deploying,
`curl` for a string that only exists in the new build, distribute a `?v=N` link,
and bump N. Details in `maitri-deploy`.

## See also

- `maitri-architecture` — the hub; where the frontend sits in the whole system.
- `maitri-orders` — building the Sale Order and multi-customer matrix UI.
- `maitri-media` — the in-app photo-capture/upload UI and canvas compression.
- `maitri-deploy` — GitHub Pages cache-busting and the `?v=N` scheme.
- `maitri-guardrails` — §D UI failure modes and §F the full verification commands.
