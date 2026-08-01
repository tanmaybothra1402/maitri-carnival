---
name: maitri-migration
description: House style for writing Supabase migrations in the Maitri exhibition app. Use when adding a table, changing an RPC, adding a permission or module, altering grants, or any schema change. Covers numbering, create-or-replace discipline, revoke/grant rules, and the CHECK constraints that silently reject writes.
---

# Writing a migration

Migrations live in `supabase/migrations/`, numbered `YYYYMMDDNNNN_snake_name.sql`,
and are **cumulative**. Later definitions win. The file set is the record of how
the schema got here — do not rewrite history, append.

Applied with `npx supabase db push` from the repo root.

## Non-negotiables

### Restate whole functions, don't patch
Use `create or replace function` with the **entire** body, even for a one-line
change. Clever partial edits across migrations make the current definition
impossible to read without mentally replaying every file.

Exception: `drop function if exists` first when the **signature or return type**
changes — Postgres will not replace a function whose `returns table (…)` shape
differs.

### Every function ends with explicit grants

```sql
revoke all on function public.thing(uuid, text) from public, anon, authenticated;
grant execute on function public.thing(uuid, text) to service_role;
```

Decide deliberately who may execute:

| Caller | Grant to | Notes |
|---|---|---|
| Customer app | `authenticated` | Must be `SECURITY DEFINER`. Must not return master image URLs. |
| Admin/Edge Function | `service_role` | Default for anything privileged. |
| Nothing yet | neither | Still revoke — do not leave the implicit public grant. |

**Never `grant … to authenticated` on a table.** Customers are authenticated
users; that hands them the table via PostgREST. This leaked the entire product
catalogue's master image URLs once already.

If you **revoke** a table grant, find every function reading that table and
promote it to `SECURITY DEFINER` in the same migration — otherwise a `stable`
function relying on caller privileges starts failing.

### SECURITY DEFINER always sets search_path

```sql
security definer
set search_path = public
```

Without it, a definer function is exploitable via a hostile `search_path`.

### Business rules go in `_write_order`, not in a new path
Any rule about *when an order may change* — locks, windows, dispatch state —
belongs inside `_write_order`. It is the single choke point for customer, staff
and assisted writes. A second write path is a hole.

## CHECK constraints that will bite you

`staff_profiles` has two enumerated CHECK constraints that predate most modules:

```sql
preset          in ('sales','reception','products','dispatch','manager','administrator','custom')
default_section in ('reception','dashboard','sale','products','dispatch','admin')
```

Adding a module **without** extending both makes every staff insert and every
"default section follows first ticked module" save fail with a constraint
violation. Drop and re-add:

```sql
alter table public.staff_profiles drop constraint if exists staff_profiles_preset_check;
alter table public.staff_profiles
  add constraint staff_profiles_preset_check
  check (preset in (…, 'newmodule'));
```

Same pattern for any enumerated status column (`orders.dispatch_status`, etc.).
Guard `add constraint` with a `pg_constraint` existence check or
`drop constraint if exists` so the migration is re-runnable.

## Adding a permission or module

Permissions are JSONB keys on `staff_profiles`, not rows in a table. There is no
`staff_permission_keys` table — do not insert into one.

To add a module, the migration must:

1. Extend both CHECK constraints above.
2. `create or replace function public.staff_permission_defaults(p_preset text)`
   restating **all** presets, with the new keys added to the relevant ones.
3. Backfill existing staff who should gain it:

```sql
update public.staff_profiles
set permissions = permissions || jsonb_build_object('newmod.view', true),
    updated_at = now()
where preset in ('administrator','manager');
```

Then the matching changes in `admin-api` and the HTML — see
`maitri-architecture` §5 for the full five-point list.

## Customer-facing readers

Any function granted to `authenticated` must **not** return `image_url`. Return
`image_key` (the design number); the `design-image` Edge Function serves reduced
bytes. This applies to `order_state_json`, `lookup_barcode`, and anything new that
reaches the customer app.

## New tables

```sql
create table if not exists public.thing (
  id uuid primary key default gen_random_uuid(),
  ...
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists thing_parent_idx on public.thing(parent_id);

alter table public.thing enable row level security;
-- No policies = service-role only. State this intent in a comment.
```

Think about cascades explicitly. `auth.users` → `customers` → `orders` →
`order_items` / `dispatch_lines` / `bookings` all cascade on delete. Deleting one
auth user removes an entire customer history. That is intended for cleanup and
dangerous during an event.

## Idempotency

Migrations should survive being re-run: `if not exists`, `drop … if exists`,
`on conflict do nothing`, `where … is distinct from`.

## Before you finish

```bash
pip install pglast --break-system-packages -q
python3 -c "from pglast import parse_sql; print(len(parse_sql(open('supabase/migrations/<file>.sql').read())),'statements parse')"
```

Parsing is not correctness — it catches syntax only. State plainly that runtime
verification against the live database is the operator's to run.

Then update `docs/DEPLOY_CARNIVAL.md`: name the new latest migration and call out
any behaviour change staff need to know about (e.g. "reopening an order no longer
unlocks a dispatched line").

## See also

- `maitri-architecture` — the hub; the five-point module checklist and where RPCs sit.
- `maitri-orders` — when a rule change means altering `_write_order` or its wrappers.
- `maitri-media` — grants that must not expose image URLs to `authenticated`.
- `maitri-deploy` — applying migrations alongside the functions that call them.
- `maitri-guardrails` — §A grants/privilege leaks; review before deploying.
