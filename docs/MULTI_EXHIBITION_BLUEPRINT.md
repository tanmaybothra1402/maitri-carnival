# Multi-exhibition blueprint

Turning the single-event Carnival app into a system that runs many exhibitions
from one Supabase project and one codebase.

**Decisions taken** (from discussion, 1 Aug 2026):

| Question | Decision |
|---|---|
| Shared across exhibitions | **Product master (`designs`) only** |
| Returning buyer | **Registers fresh each exhibition** — new login |
| Catalogue per exhibition | **No** — all active designs orderable everywhere |
| Barcode stickers | **Reprinted and remapped per exhibition** |
| Old account login | **Fails.** Only current-exhibition accounts can log in. Reception must brief returning buyers to register fresh. |
| `orders.exhibition_id` | **Denormalised column**, set from the customer at insert. Dashboards filter on it constantly. |

---

## 1. The core idea

Add one table, `exhibitions`, and stamp `exhibition_id` onto everything that is
event-specific. `designs` alone stays global.

Because **customers are per-exhibition rows**, most existing constraints keep
working untouched — `orders unique (customer_id, firm)` stays correct, because a
returning buyer is a different customer row in the new exhibition.

```
exhibitions ──┬── customers ──┬── orders ── order_items
              │               │              └── dispatch_lines / dispatch_events
              │               └── bookings
              ├── slots ──────────┘
              └── barcode_mappings ── designs   ← designs are GLOBAL
```

## 2. Schema changes

### New table

```sql
create table public.exhibitions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,           -- 'carnival-2026'; used in auth emails
  name text not null,                  -- 'Maitri Carnival 2026'
  start_date date not null,
  end_date date not null,
  registration_enabled boolean not null default true,
  edit_window_hours integer not null default 24,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Exactly one current exhibition. Enforced, not hoped for.
create unique index exhibitions_one_current
  on public.exhibitions(is_current) where is_current;
```

`is_current` drives customer registration and scanning. Admin can *view* any
exhibition via a selector, but customers always act on the current one.

### Columns added

| Table | Change |
|---|---|
| `customers` | `+ exhibition_id`, drop `unique (phone_e164)`, add `unique (phone_e164, exhibition_id)` |
| `slots` | `+ exhibition_id` |
| `barcode_mappings` | `+ exhibition_id`, PK becomes `(barcode, exhibition_id)` |
| `orders` | `+ exhibition_id` (denormalised, set from customer at insert — dashboards filter on it constantly) |
| `bookings` | inherits scope via customer + slot; no column needed |
| `dispatch_lines`, `dispatch_events` | inherit via order |

### Table removed

`system_settings` folds into `exhibitions`. Its singleton row becomes the first
exhibition. `customer_email_domain` moves there too.

### Auth email scheme

Currently `c<phone>@accounts.maitricarnival.app`.
Becomes `c<phone>.<exhibition-slug>@accounts.maitricarnival.app`.

This is what makes fresh registration possible for a returning phone number.

## 3. Function changes

Grouped by how much work each is.

### Needs an exhibition parameter or current-exhibition lookup

- `lookup_barcode(p_barcode)` → resolves within the current exhibition only.
  **Critical**: a leftover Carnival sticker must not scan into the new event.
- `list_slots()`, `book_slot()`, `cancel_my_booking()` — current exhibition.
- `get_my_status()`, `get_my_carnival_bootstrap()`, `get_my_order_state()`,
  `get_my_orders_state()` — scoped by the customer row, which is already scoped.
- `_write_order` — reads `edit_window_hours` from the exhibition, not
  `system_settings`.
- `admin_map_barcode`, `admin_deactivate_barcode` — mappings are now scoped.
- `check_in_customer`, `revoke_entry` — no change (customer row is scoped).

### Needs an exhibition filter argument

- `admin_directory(p_query, p_limit)` → `+ p_exhibition_id`
- `admin_dashboard_v2(...)` → `+ p_exhibition_id`
- `admin_dashboard_drill_v1(...)` → `+ p_exhibition_id`
- `admin_dispatch_detail(p_order_id)` — no change (order is scoped)

### Unchanged

`design_image_source`, `is_design_dispatched`, `recompute_dispatch_status`,
`order_state_json`, `staff_*`, `set_updated_at`, product sync functions.

### Deleted

`list_lookups`, `sync_*_lookups` if any remain — the lookup subsystem was already
dropped.

## 4. RLS changes

Six policies exist. All customer-facing ones filter by `auth.uid()`, which now
implies an exhibition because the customer row is scoped. So:

- `customers_select_own`, `customers_update_own` — unchanged
- `orders_select_own`, `order_items_select_own` — unchanged
- `designs_read_active` — **already revoked** from `authenticated` in migration
  `…0011`; stays revoked
- `barcode_mappings_read_active` — revoked in `…0011`; stays revoked

Good news: scoping customers means RLS needs almost no change.

## 5. Application changes

### `customer-auth`
- Registration looks up the current exhibition, refuses if
  `registration_enabled = false`, and builds the email with the slug.
- Login must resolve which exhibition's account a phone belongs to. Simplest
  rule: **log in against the current exhibition only.** An old Carnival account
  cannot log in during the next exhibition — which is the intended behaviour, but
  reception must be briefed.

### `admin-api`
- New actions: `listExhibitions`, `createExhibition`, `setCurrentExhibition`.
- Every list/dashboard action accepts `exhibitionId`, defaulting to current.
- `ACTION_PERMISSIONS` entries for the new actions (`admin.exhibitions`).
- Adding that permission means the **five-point module checklist** in
  `maitri-architecture` §5 applies — including both CHECK constraints.

### Admin console HTML
- Exhibition selector in the app bar. Changing it re-filters Reception,
  Dashboard, Sale Order and Dispatch.
- Admin → Exhibitions screen: create, set current, edit dates and window.
- **Guard rail**: switching the *current* exhibition mid-event is destructive to
  the floor. Require a typed confirmation.

### Customer HTML
- No selector. Always the current exhibition. Shows its name and dates.

### `data-sync`
- `exhibitions` becomes a mirrored table.
- `customers`, `slots`, `barcode_mappings` gain `exhibition_id` in `cols`
  (read-only — never editable from the Sheet, or a typo reassigns an order to the
  wrong event).
- `designs` unchanged.

## 6. Migration strategy

One additive migration, `202608010001_multi_exhibition.sql`, that leaves all
existing Carnival data working:

1. Create `exhibitions`.
2. Insert **Maitri Carnival 2026** from the existing `system_settings` row, with
   `is_current = true`, slug `carnival-2026`.
3. Add `exhibition_id` columns as **nullable**.
4. Backfill every existing row to the Carnival exhibition id.
5. Set `not null`, add foreign keys and the new unique constraints.
6. Drop the old `unique (phone_e164)`.
7. Recreate the affected functions.
8. Leave `system_settings` in place but unused for one release, so a rollback
   does not lose configuration. Drop it in a later migration.

Step 8 matters: this operates on a database holding real orders, and an
irreversible migration with no fallback is not worth the tidiness.

## 7. Risks, ranked

| Risk | Mitigation |
|---|---|
| Backfill misses rows → orphaned data invisible in every view | Verify counts per table before setting `not null`; the migration should fail loudly, not silently |
| Wrong `is_current` mid-event → registrations land in the wrong exhibition | Partial unique index guarantees exactly one; typed confirmation in the UI |
| Old sticker scans into new exhibition | `lookup_barcode` scoped to current exhibition — this is the single most important functional change |
| Returning buyer confusion at reception | Brief staff: old logins do not work; register fresh. Reception can search last event by phone for their details |
| Dashboard silently mixes exhibitions | Every aggregate takes `p_exhibition_id`; no default-to-all |
| Cross-exhibition reporting lost | Not lost — join on `customers.phone_e164` across exhibitions |

## 8. What this does not solve

- **Two exhibitions running simultaneously.** `is_current` is a single flag. If
  you ever need concurrent events, the customer app must carry an exhibition id
  in its config rather than reading the flag. Worth knowing; not worth building
  now.
- **Shared logins.** Deliberately out of scope per the decision above.
- **Per-exhibition catalogue.** All active designs are orderable everywhere. If
  you later want a subset, add an `exhibition_designs` join table; nothing here
  blocks it.

## 9. Effort estimate

| Phase | Scope |
|---|---|
| 1 | Migration + backfill + function updates |
| 2 | `admin-api` actions and permission wiring |
| 3 | Admin console: selector + Exhibitions screen |
| 4 | Customer app + `customer-auth` |
| 5 | `data-sync` + docs |
| 6 | Verification pass against `maitri-guardrails` |

Phases 1–2 are the risky ones; 3–5 are mechanical. Do not deploy 1 without 2 —
`admin-api` will call functions whose signatures changed.
