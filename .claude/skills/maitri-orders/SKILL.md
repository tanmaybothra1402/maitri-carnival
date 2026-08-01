---
name: maitri-orders
description: The order write path for the Maitri exhibition app — the single _write_order choke point, operation-list merge semantics, request_id idempotency, the dispatch lock, and multi-customer batch saves. Read this before touching how orders are created, edited, saved, batched, or locked, or before writing anything that inserts into orders/order_items.
---

# Maitri orders — the write path

Every order change in this system flows through one function. Get this wrong and
you lose customer orders on a live floor — the one failure the whole design exists
to prevent. Read this before writing any code that touches `orders` or
`order_items`.

## 1. One write choke point

**Every** order write — customer self-service, staff-assisted, batch — goes
through `public._write_order(...)`. There is not one path per actor. There is one
function.

| Caller | Route |
|---|---|
| Customer app | `save_my_order` → `_write_order` |
| Staff Sale Order | `admin_save_order_with_actor` → `_write_order` |
| Assisted registration | `admin_save_order_with_actor` → `_write_order` |
| Multi-customer batch | **loop** of `admin_save_order_with_actor` → `_write_order` |

A batch save is a loop over the wrapper, one call per customer — never a new bulk
writer that inserts into `order_items` directly.

If you find yourself writing a second thing that inserts into `order_items`, stop.
You are opening a hole. Rules about *when an order may change* live in
`_write_order` and nowhere else, so every actor is covered by one guard.

## 2. Operation-list semantics — merge-safe, never last-write-wins

`_write_order` takes an **operation list**, not a cart snapshot:

- a normal row = upsert that design (`on conflict (order_id, design_no)`)
- `{designNo, _op:"delete", _delete:true}` = remove that design
- **designs not mentioned are left untouched**

Plus `select … for update` on the order row and a `request_id` for idempotency
(the same save retried over flaky exhibition wifi must not double-apply).

**Why this is non-negotiable:** two devices editing one customer's order at once
is normal — the customer on their phone, staff on a tablet. Sending a whole cart
would silently delete the other party's additions. A "simpler" refactor to
full-cart replacement *will* lose orders.

There is a legacy full-cart path for old clients. It excludes dispatched designs
so a stale client cannot delete goods that already shipped. Do not extend it;
route new work through the operation list.

## 3. The dispatch lock outranks everything

Once a line has `dispatched_sets > 0` it is frozen for customer **and** staff.
This deliberately outranks `admin_unlocked`: reopening an order does **not** reopen
a dispatched line. You must undispatch first. Enforced inside `_write_order`, so
all actors are covered by one guard — never re-implement the check in a caller.

Order-lock precedence, highest first: **dispatch lock → edit window → order lock
(`admin_unlocked`)**.

## 4. Units — sets vs pieces

`pieces = sets × pcs_per_set`. Customers order in **sets**. `pcs_per_set` is
snapshotted onto the order line (`pcs_per_set_snapshot`) so a later catalogue edit
never retroactively changes a placed order. Default `pcs_per_set` is 4. Batch and
matrix UIs count in sets; convert to pieces only for display.

## 5. Multi-customer batch saves

The salesperson builds several customers' orders together (see Brief 4). The rules
that keep this safe:

- **Batch = a loop over `admin_save_order_with_actor`, one call per customer.**
  Never a bulk order writer. Each customer still goes through `_write_order`.
- **Partial failure is normal.** Report **per-customer** results. Do **not** roll
  back the customers that succeeded because one failed.
- **Never write a customer whose qty is 0.** Writing an empty order starts that
  customer's 24-hour edit window for nothing. Filter qty-0 customers out *before*
  the call, not inside it.
- Idempotency is per call — give each customer's save its own `request_id` so a
  retry of the batch does not re-apply the ones that already landed.

## 6. Server-side aggregation

~300 customers × thousands of line items. Order/dispatch dashboards call
`admin_dashboard_v2` / `admin_dispatch_detail` and aggregate in Postgres. Never
pull raw order rows to the browser and reduce there.

## Trace every caller before changing a shared writer

`lookup_barcode` served both customer and admin and broke when changed for one.
`_write_order` and its wrappers have more callers than you expect. List every
caller before touching a signature. See `maitri-guardrails` §C.

## See also

- `maitri-architecture` — the hub; where this fits among the other choke points.
- `maitri-media` — images on order screens; customers see none.
- `maitri-frontend` — building the Sale Order / matrix UI and verifying it.
- `maitri-migration` — when a rule change means altering `_write_order`.
- `maitri-guardrails` — §C shared-function regressions; review before deploying.
