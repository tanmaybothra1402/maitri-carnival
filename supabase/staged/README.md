# Staged, Edge-coupled changes — NOT yet applied

These SQL files change an RPC's **return shape**, which the deployed Edge Function
must be updated to read in lockstep. They live here, **outside `supabase/migrations/`,
on purpose**: a file in `migrations/` would be applied by `supabase db push` and
could land before its matched Edge is deployed, breaking a live screen. Do not move
them into `migrations/` until the Edge is deployed.

## Ship order (when the CLI token + git push are unblocked)

1. `git push` the stacked commits (HTML + staged files land in the repo).
2. `supabase functions deploy admin-api` — the on-disk Edge is already **shape-tolerant**
   (reads both the old and new RPC shapes), so this is safe with today's live RPCs.
3. Move the SQL below into `supabase/migrations/` with the next free number and
   `supabase db push` (or apply via MCP). The tolerant Edge handles the flip with no
   breakage window.
4. `curl` + grep a build-unique string per deploy (E1).

## Files

- `admin_dispatch_orders_camelcase_pagination.sql` — BUG 1 (camelCase output) + BUG 4
  (`offset` param + `{orders, total}` so the client can page past the 300 cap and show
  a true total). Proven against prod under a temp name: total=486, camelCase keys,
  offset:300 returns the 186 orders that were previously unreachable.
- `crm_list_customers_object_counts.sql` — the object-shape `crm_list_customers`
  `{ customers, assigneeCounts, unassignedCount, totalCount }` backing the CRM
  salesperson-picker counts (prior session; migration 026 applied then reverted by
  027). The on-disk Edge is already shape-tolerant for it.

Both RPCs' on-disk Edge handlers are shape-tolerant, so step 2 (deploy Edge) is safe
against today's live array-shape RPCs, and step 3 (apply these) has no breakage window.
