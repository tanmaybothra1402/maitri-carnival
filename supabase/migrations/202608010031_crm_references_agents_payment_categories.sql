-- 202608010031_crm_references_agents_payment_categories.sql
--
-- Four CRM additions, all on the buyer-INVISIBLE CRM side (service-role only):
--   1. category interest — manual table here; AUTO is derived in SQL (migration 032),
--      never stored/cached. Canonical 5 prefixes only (MR/KT/NRK/MU/BS): the leading-
--      letters regex yields 6 on live data (a stray "MRK" typo row), so the set is
--      pinned to 5 in both the CHECK here and the derivation.
--   2. reference_companies — a shared, self-growing list; canonical dedup key so
--      "S4U" / "s4u" / "S 4 U" collapse to one entry (the mess customers.agent has).
--   3. reference verification — poc/notes/verdict/verified_* on customer_references.
--   4. agents self-growing table + customer_crm.agent_id; payment terms on customer_crm.
--
-- A1: every new table is RLS-on with NO policy (service-role only) and revokes
-- anon/authenticated; every new COLUMN lands on customer_crm / customer_references,
-- which are already service-role-only (auth_select=false) — buyers can never read
-- payment terms, credit days, reference notes/verdicts, or reference standing.
-- Nothing is added to public.customers (buyer-readable). No new permission module —
-- these are all crm.view/crm.write; dispatch only READS the standing (warn, never block).
--
-- reference_standing: STAFF-SET overall standing (approved/watch/rejected, null=unset).
-- NOT computed from individual verdicts — references are evidence, staff decide.
-- agents starts EMPTY (operator supplies canonical values); customers.agent is NOT
-- migrated in (that would import the 261-spelling mess) and stays for the dashboard.

-- ── self-growing lookups ──────────────────────────────────────────────────────
create table if not exists public.reference_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text generated always as (regexp_replace(upper(name), '[^A-Z0-9]', '', 'g')) stored,
  created_by uuid,
  created_at timestamptz not null default now()
);
create unique index if not exists reference_companies_key_idx on public.reference_companies(name_key);
alter table public.reference_companies enable row level security;
-- No policies = service-role only. Stated intent.

create table if not exists public.agents (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text generated always as (regexp_replace(upper(name), '[^A-Z0-9]', '', 'g')) stored,
  created_by uuid,
  created_at timestamptz not null default now()
);
create unique index if not exists agents_key_idx on public.agents(name_key);
alter table public.agents enable row level security;

-- ── manual category interest (auto derived in SQL, never stored) ──────────────
create table if not exists public.customer_category_interest (
  customer_id uuid not null references public.customers(id) on delete cascade,
  category text not null check (category in ('MR','KT','NRK','MU','BS')),
  added_by uuid,
  created_at timestamptz not null default now(),
  primary key (customer_id, category)
);
alter table public.customer_category_interest enable row level security;

-- ── reference verification (step 2: we call the company) ──────────────────────
alter table public.customer_references
  add column if not exists company_id  uuid references public.reference_companies(id),
  add column if not exists poc_name     text,
  add column if not exists notes        text,
  add column if not exists verdict      text not null default 'pending' check (verdict in ('pending','approved','rejected')),
  add column if not exists verified_by  uuid,
  add column if not exists verified_at  timestamptz;

-- ── payment terms + agent link + staff-set reference standing (customer_crm) ──
alter table public.customer_crm
  add column if not exists pay_method        text check (pay_method in ('cash','cheque')),
  add column if not exists credit_days       integer check (credit_days is null or (credit_days >= 0 and credit_days <= 3650)),
  add column if not exists pay_notes         text,
  add column if not exists agent_id          uuid references public.agents(id),
  add column if not exists reference_standing text check (reference_standing in ('approved','watch','rejected'));

-- ── migrate the existing free-text references into the shared list ────────────
insert into public.reference_companies (name)
  select distinct btrim(reference_text)
  from public.customer_references
  where nullif(btrim(reference_text), '') is not null
  on conflict (name_key) do nothing;
update public.customer_references r
  set company_id = rc.id
  from public.reference_companies rc
  where r.company_id is null
    and nullif(btrim(r.reference_text), '') is not null
    and rc.name_key = regexp_replace(upper(btrim(r.reference_text)), '[^A-Z0-9]', '', 'g');

-- ── grants: new tables are service-role only ─────────────────────────────────
revoke all on table public.reference_companies       from public, anon, authenticated;
revoke all on table public.agents                    from public, anon, authenticated;
revoke all on table public.customer_category_interest from public, anon, authenticated;
grant all on table public.reference_companies        to service_role;
grant all on table public.agents                     to service_role;
grant all on table public.customer_category_interest to service_role;
