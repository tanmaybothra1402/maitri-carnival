-- Maitri Carnival 2026 — entry gate, slot booking, and account-level edit window.
-- Additive over the existing schema. Apply after 202607160004.

-- ---------------------------------------------------------------------------
-- 1. Event configuration
-- ---------------------------------------------------------------------------
alter table public.system_settings
  add column if not exists edit_window_hours integer not null default 24
    check (edit_window_hours between 1 and 240);

update public.system_settings
set
  event_name = 'Maitri Carnival 2026',
  event_start_date = date '2026-07-19',
  event_end_date = date '2026-07-21',
  registration_enabled = true,
  edit_window_hours = 24,
  updated_at = now()
where singleton = true;

-- ---------------------------------------------------------------------------
-- 2. Customer entry (check-in) + account-level 24h edit window
-- ---------------------------------------------------------------------------
alter table public.customers
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_in_by uuid references auth.users(id) on delete set null,
  add column if not exists ordering_started_at timestamptz,
  add column if not exists edit_deadline timestamptz;

create index if not exists customers_checked_in_idx on public.customers(checked_in_at);

-- Per-order admin override so staff can reopen a specific locked order.
alter table public.orders
  add column if not exists admin_unlocked boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3. Slots (admin-defined visit windows) and bookings (planning only)
-- ---------------------------------------------------------------------------
create table if not exists public.slots (
  id uuid primary key default gen_random_uuid(),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  label text not null default '',
  capacity integer check (capacity is null or capacity > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index if not exists slots_starts_idx on public.slots(starts_at);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.customers(id) on delete cascade,
  slot_id uuid not null references public.slots(id) on delete restrict,
  party_size integer not null default 1 check (party_size between 1 and 99),
  note text not null default '',
  status text not null default 'Booked' check (status in ('Booked', 'Cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bookings_slot_idx on public.bookings(slot_id) where status = 'Booked';

create trigger slots_updated_at
before update on public.slots
for each row execute function public.set_updated_at();

create trigger bookings_updated_at
before update on public.bookings
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Row-Level Security
-- ---------------------------------------------------------------------------
alter table public.slots enable row level security;
alter table public.bookings enable row level security;

-- Customers may read active slots to choose one.
create policy slots_read_active
on public.slots for select
to authenticated
using (active = true);

-- Customers may read only their own booking. Writes happen through RPCs.
create policy bookings_select_own
on public.bookings for select
to authenticated
using (customer_id = auth.uid());

-- Least privilege: no direct writes to either table from the browser.
revoke all on public.slots from anon, authenticated;
revoke all on public.bookings from anon, authenticated;
grant select on public.slots to authenticated;
grant select on public.bookings to authenticated;
