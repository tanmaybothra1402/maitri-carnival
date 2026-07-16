-- Maitri × Niharika self-service exhibition system
-- Core relational schema. Apply before the remaining numbered migrations.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.system_settings (
  singleton boolean primary key default true check (singleton),
  event_name text not null default 'Maitri × Niharika Office Exhibition',
  event_start_date date not null default date '2026-07-19',
  event_end_date date not null default date '2026-07-21',
  registration_enabled boolean not null default true,
  registration_access_code_hash text,
  customer_email_domain text not null default 'customers.maitri.local',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.system_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table public.customers (
  id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null unique check (phone_e164 ~ '^91[6-9][0-9]{9}$'),
  company_name text not null check (length(btrim(company_name)) between 2 and 120),
  contact_name text not null check (length(btrim(contact_name)) between 2 and 100),
  city text not null default '',
  state text not null default '',
  gstin text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.designs (
  design_no text primary key,
  firm text not null check (firm in ('Maitri', 'Niharika', 'Both')),
  category text not null default '',
  fabric text not null default '',
  color text not null default '',
  description text not null default '',
  active boolean not null default true,
  source_updated_at timestamptz,
  sync_version bigint not null default 1 check (sync_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(design_no)) between 1 and 80)
);

-- Kept separate so customer-facing SELECT access never exposes the base image URL.
create table public.design_assets (
  design_no text primary key references public.designs(design_no) on update cascade on delete cascade,
  base_image_url text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.barcode_mappings (
  barcode text primary key,
  design_no text not null references public.designs(design_no) on update cascade on delete restrict,
  active boolean not null default true,
  mapped_by uuid references auth.users(id) on delete set null,
  mapped_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(barcode)) between 1 and 160)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  firm text not null check (firm in ('Maitri', 'Niharika')),
  status text not null default 'Draft' check (status in ('Draft', 'Saved', 'Locked')),
  total_designs integer not null default 0 check (total_designs >= 0),
  total_pieces integer not null default 0 check (total_pieces >= 0),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, firm)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  barcode text not null default '',
  design_no text not null references public.designs(design_no) on update cascade on delete restrict,
  qty integer not null check (qty between 1 and 9999),
  category_snapshot text not null default '',
  fabric_snapshot text not null default '',
  color_snapshot text not null default '',
  description_snapshot text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, design_no)
);

create table public.order_save_requests (
  request_id uuid primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  previous_version integer not null,
  new_version integer not null,
  design_count integer not null default 0,
  total_pieces integer not null default 0,
  result text not null check (result in ('Success', 'Conflict', 'Failed')),
  response_json jsonb,
  error text not null default '',
  created_at timestamptz not null default now()
);

create table public.barcode_mapping_log (
  id bigint generated always as identity primary key,
  barcode text not null,
  previous_design_no text,
  new_design_no text,
  action text not null check (action in ('Created', 'Remapped', 'Deactivated', 'Reactivated')),
  admin_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.product_sync_runs (
  id bigint generated always as identity primary key,
  source text not null default 'GOOGLE_SHEETS',
  mode text not null check (mode in ('ROWS', 'FULL_SNAPSHOT')),
  received_count integer not null default 0,
  upserted_count integer not null default 0,
  deactivated_count integer not null default 0,
  status text not null check (status in ('Success', 'Failed')),
  error text not null default '',
  created_at timestamptz not null default now()
);

create index orders_customer_idx on public.orders(customer_id, firm);
create index orders_updated_idx on public.orders(updated_at desc);
create index order_items_order_idx on public.order_items(order_id);
create index order_items_design_idx on public.order_items(design_no);
create index designs_active_firm_idx on public.designs(active, firm);
create index barcode_mappings_design_idx on public.barcode_mappings(design_no) where active;
create index customers_company_idx on public.customers(lower(company_name));
create index customers_phone_idx on public.customers(phone_e164);
create index save_requests_customer_idx on public.order_save_requests(customer_id, created_at desc);

create trigger system_settings_updated_at
before update on public.system_settings
for each row execute function public.set_updated_at();

create trigger customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger designs_updated_at
before update on public.designs
for each row execute function public.set_updated_at();

create trigger design_assets_updated_at
before update on public.design_assets
for each row execute function public.set_updated_at();

create trigger barcode_mappings_updated_at
before update on public.barcode_mappings
for each row execute function public.set_updated_at();

create trigger orders_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create trigger order_items_updated_at
before update on public.order_items
for each row execute function public.set_updated_at();

comment on table public.design_assets is
'Private base ImageKit URLs. Never grant anon/authenticated SELECT; image-proxy reads with service_role.';
