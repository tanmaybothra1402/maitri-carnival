-- BUNDLE 4 of 6 — DATABASE MIGRATIONS (Postgres). Applied in filename order; later definitions override earlier ones.


################################################################################
# FILE: supabase/migrations/202607150001_schema.sql
################################################################################

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


################################################################################
# FILE: supabase/migrations/202607150002_auth_and_rls.sql
################################################################################

-- Customer provisioning, admin helpers, grants and Row-Level Security.

create or replace function public.is_admin_user(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;

  -- Real-email admin users are intentionally not customer profiles.
  if split_part(lower(coalesce(new.email, '')), '@', 2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164', ''), '\D', '', 'g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  if split_part(lower(new.email), '@', 1) <> v_phone then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code', '');
    if encode(extensions.digest(v_access_code, 'sha256'), 'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin);

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.system_settings enable row level security;
alter table public.customers enable row level security;
alter table public.designs enable row level security;
alter table public.design_assets enable row level security;
alter table public.barcode_mappings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_save_requests enable row level security;
alter table public.barcode_mapping_log enable row level security;
alter table public.product_sync_runs enable row level security;

create policy customers_select_own
on public.customers for select
to authenticated
using (id = auth.uid());

create policy customers_update_own
on public.customers for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy designs_read_active
on public.designs for select
to authenticated
using (active = true);

create policy barcode_mappings_read_active
on public.barcode_mappings for select
to authenticated
using (
  active = true
  and exists (
    select 1 from public.designs d
    where d.design_no = barcode_mappings.design_no
      and d.active = true
  )
);

create policy orders_select_own
on public.orders for select
to authenticated
using (customer_id = auth.uid());

create policy order_items_select_own
on public.order_items for select
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.customer_id = auth.uid()
  )
);

-- Start from least privilege. Customer writes happen only through audited RPCs.
revoke all on public.system_settings from anon, authenticated;
revoke all on public.customers from anon, authenticated;
revoke all on public.designs from anon, authenticated;
revoke all on public.design_assets from anon, authenticated;
revoke all on public.barcode_mappings from anon, authenticated;
revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
revoke all on public.order_save_requests from anon, authenticated;
revoke all on public.barcode_mapping_log from anon, authenticated;
revoke all on public.product_sync_runs from anon, authenticated;

-- RLS still applies to every granted read.
grant select on public.customers to authenticated;
grant update (company_name, contact_name, city, state, gstin) on public.customers to authenticated;
grant select on public.designs to authenticated;
grant select on public.barcode_mappings to authenticated;
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;

revoke all on function public.is_admin_user(uuid) from public, anon, authenticated;
grant execute on function public.is_admin_user(uuid) to authenticated, service_role;


################################################################################
# FILE: supabase/migrations/202607150003_customer_functions.sql
################################################################################

-- Customer-facing PostgreSQL RPCs. These are called directly by supabase-js.

create or replace function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  category text,
  fabric text,
  color text,
  description text
)
language sql
stable
set search_path = public
as $$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.category,
    d.fabric,
    d.color,
    d.description
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$$;

create or replace function public.order_state_json(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', o.id,
    'firm', o.firm,
    'status', o.status,
    'version', o.version,
    'totalDesigns', o.total_designs,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'qty', i.qty,
          'category', i.category_snapshot,
          'fabric', i.fabric_snapshot,
          'color', i.color_snapshot,
          'description', i.description_snapshot
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$$;

create or replace function public.get_my_order_state(p_firm text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;

  select id into v_order_id
  from public.orders
  where customer_id = auth.uid() and firm = p_firm;

  if v_order_id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  return public.order_state_json(v_order_id);
end;
$$;

create or replace function public.save_my_order(
  p_firm text,
  p_base_version integer,
  p_items jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_customer public.customers%rowtype;
  v_order public.orders%rowtype;
  v_existing public.order_save_requests%rowtype;
  v_item jsonb;
  v_design public.designs%rowtype;
  v_design_no text;
  v_barcode text;
  v_qty integer;
  v_seen text[] := array[]::text[];
  v_normalized jsonb := '[]'::jsonb;
  v_design_count integer := 0;
  v_total_pieces integer := 0;
  v_new_version integer;
  v_response jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'ITEMS_MUST_BE_AN_ARRAY';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 500 then
    raise exception 'TOO_MANY_ORDER_ITEMS';
  end if;

  select * into v_existing
  from public.order_save_requests
  where request_id = p_request_id;

  if found then
    if v_existing.customer_id <> v_user_id then raise exception 'REQUEST_ID_OWNERSHIP_ERROR'; end if;
    return v_existing.response_json;
  end if;

  select * into v_customer
  from public.customers
  where id = v_user_id;

  if not found or not v_customer.active then raise exception 'CUSTOMER_ACCESS_DISABLED'; end if;

  select * into v_order
  from public.orders
  where customer_id = v_user_id and firm = p_firm
  for update;

  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status = 'Locked' then raise exception 'ORDER_LOCKED'; end if;

  if coalesce(p_base_version, 0) <> v_order.version then
    v_response := jsonb_build_object(
      'ok', false,
      'code', 'ORDER_VERSION_CONFLICT',
      'message', 'This order changed in another tab or device. Reload the latest version before saving.',
      'order', public.order_state_json(v_order.id)
    );

    insert into public.order_save_requests(
      request_id, order_id, customer_id, previous_version, new_version,
      design_count, total_pieces, result, response_json, error
    ) values (
      p_request_id, v_order.id, v_user_id, coalesce(p_base_version, 0), v_order.version,
      v_order.total_designs, v_order.total_pieces, 'Conflict', v_response, 'ORDER_VERSION_CONFLICT'
    );
    return v_response;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_item ->> 'designNo', v_item ->> 'design_no', ''));
    v_barcode := btrim(coalesce(v_item ->> 'barcode', ''));

    begin
      v_qty := (v_item ->> 'qty')::integer;
    exception when others then
      raise exception 'INVALID_QUANTITY_FOR_%', coalesce(nullif(v_design_no, ''), 'ITEM');
    end;

    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;
    if v_qty < 1 or v_qty > 9999 then raise exception 'INVALID_QUANTITY_FOR_%', v_design_no; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_%', v_design_no; end if;

    select * into v_design
    from public.designs
    where design_no = v_design_no and active = true;

    if not found then raise exception 'INACTIVE_OR_UNKNOWN_DESIGN_%', v_design_no; end if;
    if v_design.firm not in (p_firm, 'Both') then
      raise exception 'DESIGN_%_DOES_NOT_BELONG_TO_%', v_design_no, p_firm;
    end if;

    v_seen := array_append(v_seen, v_design_no);
    v_design_count := v_design_count + 1;
    v_total_pieces := v_total_pieces + v_qty;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'barcode', v_barcode,
      'designNo', v_design.design_no,
      'qty', v_qty,
      'category', v_design.category,
      'fabric', v_design.fabric,
      'color', v_design.color,
      'description', v_design.description
    ));
  end loop;

  delete from public.order_items where order_id = v_order.id;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into public.order_items(
      order_id, barcode, design_no, qty,
      category_snapshot, fabric_snapshot, color_snapshot, description_snapshot
    ) values (
      v_order.id,
      coalesce(v_item ->> 'barcode', ''),
      v_item ->> 'designNo',
      (v_item ->> 'qty')::integer,
      coalesce(v_item ->> 'category', ''),
      coalesce(v_item ->> 'fabric', ''),
      coalesce(v_item ->> 'color', ''),
      coalesce(v_item ->> 'description', '')
    );
  end loop;

  v_new_version := v_order.version + 1;
  update public.orders
  set
    status = case when v_design_count = 0 then 'Draft' else 'Saved' end,
    total_designs = v_design_count,
    total_pieces = v_total_pieces,
    version = v_new_version,
    updated_at = now()
  where id = v_order.id;

  v_response := jsonb_build_object(
    'ok', true,
    'code', 'SAVED',
    'message', 'Order saved.',
    'order', public.order_state_json(v_order.id)
  );

  insert into public.order_save_requests(
    request_id, order_id, customer_id, previous_version, new_version,
    design_count, total_pieces, result, response_json
  ) values (
    p_request_id, v_order.id, v_user_id, v_order.version, v_new_version,
    v_design_count, v_total_pieces, 'Success', v_response
  );

  return v_response;
end;
$$;

revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
revoke all on function public.get_my_order_state(text) from public, anon, authenticated;
revoke all on function public.save_my_order(text, integer, jsonb, uuid) from public, anon, authenticated;

grant execute on function public.lookup_barcode(text) to authenticated;
grant execute on function public.get_my_order_state(text) to authenticated;
grant execute on function public.save_my_order(text, integer, jsonb, uuid) to authenticated;
grant execute on function public.order_state_json(uuid) to service_role;


################################################################################
# FILE: supabase/migrations/202607150004_product_sync_functions.sql
################################################################################

-- Service-role-only product master synchronization functions.

create or replace function public.normalize_product_firm(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare v text := lower(btrim(coalesce(p_value, '')));
begin
  if v = 'maitri' then return 'Maitri'; end if;
  if v = 'niharika' then return 'Niharika'; end if;
  if v in ('both', 'maitri/niharika', 'maitri & niharika', 'maitri and niharika') then return 'Both'; end if;
  raise exception 'INVALID_PRODUCT_FIRM_%', p_value;
end;
$$;

create or replace function public.parse_sheet_boolean(p_value text, p_default boolean default true)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when btrim(coalesce(p_value, '')) = '' then p_default
    when lower(btrim(p_value)) in ('true','yes','y','1','active') then true
    when lower(btrim(p_value)) in ('false','no','n','0','inactive') then false
    else p_default
  end;
$$;

create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    insert into public.designs(
      design_no, firm, category, fabric, color, description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      btrim(coalesce(v_row ->> 'Color', v_row ->> 'color', '')),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      category = excluded.category,
      fabric = excluded.fabric,
      color = excluded.color,
      description = excluded.description,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm, public.designs.category, public.designs.fabric,
      public.designs.color, public.designs.description, public.designs.active,
      public.designs.source_updated_at
    ) is distinct from (
      excluded.firm, excluded.category, excluded.fabric, excluded.color,
      excluded.description, excluded.active, excluded.source_updated_at
    );

    insert into public.design_assets(design_no, base_image_url)
    values (
      v_design_no,
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', ''))
    )
    on conflict (design_no) do update set
      base_image_url = excluded.base_image_url,
      updated_at = now()
    where public.design_assets.base_image_url is distinct from excluded.base_image_url;

    v_count := v_count + 1;
  end loop;

  insert into public.product_sync_runs(mode, received_count, upserted_count, status)
  values ('ROWS', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), v_count, 'Success');

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', v_count,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('ROWS', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

create or replace function public.apply_product_snapshot(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_seen text[] := array[]::text[];
  v_row jsonb;
  v_design_no text;
  v_deactivated integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  -- Validate duplicate/blank keys before changing the master.
  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_NO_%', v_design_no; end if;
    v_seen := array_append(v_seen, v_design_no);
  end loop;

  v_result := public.upsert_product_rows(p_rows);

  update public.designs
  set active = false, sync_version = sync_version + 1, updated_at = now()
  where active = true
    and not (design_no = any(v_seen));
  get diagnostics v_deactivated = row_count;

  insert into public.product_sync_runs(mode, received_count, upserted_count, deactivated_count, status)
  values (
    'FULL_SNAPSHOT',
    jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    coalesce((v_result ->> 'upserted')::integer, 0),
    v_deactivated,
    'Success'
  );

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', coalesce((v_result ->> 'upserted')::integer, 0),
    'deactivated', v_deactivated,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('FULL_SNAPSHOT', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

revoke all on function public.normalize_product_firm(text) from public, anon, authenticated;
revoke all on function public.parse_sheet_boolean(text, boolean) from public, anon, authenticated;
revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
revoke all on function public.apply_product_snapshot(jsonb) from public, anon, authenticated;

grant execute on function public.upsert_product_rows(jsonb) to service_role;
grant execute on function public.apply_product_snapshot(jsonb) to service_role;


################################################################################
# FILE: supabase/migrations/202607150005_admin_support.sql
################################################################################

-- Server-side helpers used by admin-api. Browser customers receive no grants.

create or replace function public.admin_map_barcode(
  p_barcode text,
  p_design_no text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barcode text := btrim(coalesce(p_barcode, ''));
  v_design_no text := btrim(coalesce(p_design_no, ''));
  v_existing public.barcode_mappings%rowtype;
  v_action text;
begin
  if v_barcode = '' then raise exception 'BARCODE_REQUIRED'; end if;
  if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
  if not exists (select 1 from public.designs where design_no = v_design_no and active = true) then
    raise exception 'ACTIVE_DESIGN_NOT_FOUND';
  end if;

  select * into v_existing from public.barcode_mappings where barcode = v_barcode for update;

  if found then
    v_action := case
      when v_existing.design_no <> v_design_no then 'Remapped'
      when not v_existing.active then 'Reactivated'
      else 'Remapped'
    end;

    update public.barcode_mappings
    set design_no = v_design_no, active = true, mapped_by = p_admin_user_id, updated_at = now()
    where barcode = v_barcode;
  else
    v_action := 'Created';
    insert into public.barcode_mappings(barcode, design_no, mapped_by)
    values (v_barcode, v_design_no, p_admin_user_id);
  end if;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (
    v_barcode,
    case when v_existing.barcode is null then null else v_existing.design_no end,
    v_design_no,
    v_action,
    p_admin_user_id
  );

  return jsonb_build_object('barcode', v_barcode, 'designNo', v_design_no, 'action', v_action);
end;
$$;

create or replace function public.admin_deactivate_barcode(
  p_barcode text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.barcode_mappings%rowtype;
begin
  select * into v_row from public.barcode_mappings where barcode = btrim(p_barcode) for update;
  if not found then raise exception 'BARCODE_NOT_FOUND'; end if;

  update public.barcode_mappings set active = false, mapped_by = p_admin_user_id, updated_at = now()
  where barcode = v_row.barcode;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (v_row.barcode, v_row.design_no, v_row.design_no, 'Deactivated', p_admin_user_id);

  return jsonb_build_object('barcode', v_row.barcode, 'designNo', v_row.design_no, 'active', false);
end;
$$;

revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
revoke all on function public.admin_deactivate_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;
grant execute on function public.admin_deactivate_barcode(text, uuid) to service_role;


################################################################################
# FILE: supabase/migrations/202607150006_seed.sql
################################################################################

-- Safe seed/configuration defaults. No demo customer or order data is inserted.

update public.system_settings
set
  event_name = 'Maitri × Niharika Office Exhibition',
  event_start_date = date '2026-07-19',
  event_end_date = date '2026-07-21',
  registration_enabled = true,
  customer_email_domain = 'customers.maitri.local'
where singleton = true;

-- Optional sample products are deliberately commented out.
-- Add real products through the ProductMaster Google Sheet instead.
-- insert into public.designs(design_no, firm, category, fabric, color, description, active)
-- values ('MT-DEMO-001', 'Maitri', 'Kurta Set', 'Cotton', 'Blue', 'Demo only', true);


################################################################################
# FILE: supabase/migrations/202607160001_direct_product_images.sql
################################################################################

-- Direct product image delivery.
-- ProductMaster.ImageURL is stored on public.designs and is intentionally
-- readable by authenticated exhibition users together with the design record.

alter table public.designs
  add column if not exists image_url text not null default '';

-- Preserve any URLs already synchronized by the previous private-asset model.
update public.designs d
set image_url = da.base_image_url,
    updated_at = now()
from public.design_assets da
where da.design_no = d.design_no
  and btrim(coalesce(da.base_image_url, '')) <> ''
  and d.image_url is distinct from da.base_image_url;

create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    insert into public.designs(
      design_no, firm, image_url, category, fabric, color, description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', '')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      btrim(coalesce(v_row ->> 'Color', v_row ->> 'color', '')),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      image_url = excluded.image_url,
      category = excluded.category,
      fabric = excluded.fabric,
      color = excluded.color,
      description = excluded.description,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm, public.designs.image_url, public.designs.category,
      public.designs.fabric, public.designs.color, public.designs.description,
      public.designs.active, public.designs.source_updated_at
    ) is distinct from (
      excluded.firm, excluded.image_url, excluded.category, excluded.fabric,
      excluded.color, excluded.description, excluded.active, excluded.source_updated_at
    );

    v_count := v_count + 1;
  end loop;

  insert into public.product_sync_runs(mode, received_count, upserted_count, status)
  values ('ROWS', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), v_count, 'Success');

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', v_count,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('ROWS', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

-- Return the image URL directly with a successful barcode lookup.
drop function if exists public.lookup_barcode(text);

create function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  image_url text,
  category text,
  fabric text,
  color text,
  description text
)
language sql
stable
set search_path = public
as $$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.image_url,
    d.category,
    d.fabric,
    d.color,
    d.description
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$$;

create or replace function public.order_state_json(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', o.id,
    'firm', o.firm,
    'status', o.status,
    'version', o.version,
    'totalDesigns', o.total_designs,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'imageUrl', d.image_url,
          'qty', i.qty,
          'category', i.category_snapshot,
          'fabric', i.fabric_snapshot,
          'color', i.color_snapshot,
          'description', i.description_snapshot
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      join public.designs d on d.design_no = i.design_no
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$$;

revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_product_rows(jsonb) to service_role;

revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated;

revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
grant execute on function public.order_state_json(uuid) to service_role;

-- The separate private asset table and proxy are no longer part of this build.
drop table if exists public.design_assets;


################################################################################
# FILE: supabase/migrations/202607160002_fix_customer_email_domain.sql
################################################################################

update public.system_settings
set
  customer_email_domain = 'customers.maitricarnival.com',
  updated_at = now()
where singleton = true;


################################################################################
# FILE: supabase/migrations/202607160003_phone_password_auth.sql
################################################################################

-- Use Supabase's native phone + password identity.
-- Email-only users are admins and are not provisioned as customers.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_metadata_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  -- Admin users authenticate with a real email and have no phone identity.
  if nullif(btrim(coalesce(new.phone, '')), '') is null then
    return new;
  end if;

  select *
  into v_settings
  from public.system_settings
  where singleton = true;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  -- Supabase stores the phone in E.164 form, such as +919876543210.
  v_phone := regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');

  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  -- Confirm that browser metadata matches the authenticated phone.
  v_metadata_phone :=
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'phone_e164', ''),
      '\D',
      '',
      'g'
    );

  if v_metadata_phone <> '' and v_metadata_phone <> v_phone then
    raise exception 'PHONE_METADATA_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code :=
      coalesce(new.raw_user_meta_data ->> 'access_code', '');

    if encode(extensions.digest(v_access_code, 'sha256'), 'hex')
       <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company :=
    btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));

  v_contact :=
    btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));

  v_city :=
    btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));

  v_state :=
    btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));

  v_gstin :=
    upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;

  if length(v_contact) < 2 then
    raise exception 'CONTACT_NAME_REQUIRED';
  end if;

  insert into public.customers(
    id,
    phone_e164,
    company_name,
    contact_name,
    city,
    state,
    gstin
  )
  values (
    new.id,
    v_phone,
    v_company,
    v_contact,
    v_city,
    v_state,
    v_gstin
  );

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;


################################################################################
# FILE: supabase/migrations/202607160004_customer_hidden_email_auth.sql
################################################################################

update public.system_settings
set
  customer_email_domain = 'accounts.maitricarnival.app',
  updated_at = now()
where singleton = true;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  select *
  into v_settings
  from public.system_settings
  where singleton = true;

  -- Admin users use real email addresses and must not become customers.
  if split_part(lower(coalesce(new.email, '')), '@', 2)
     <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  v_phone :=
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'phone_e164', ''),
      '\D',
      '',
      'g'
    );

  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  if split_part(lower(new.email), '@', 1) <> ('c' || v_phone) then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code :=
      coalesce(new.raw_user_meta_data ->> 'access_code', '');

    if encode(extensions.digest(v_access_code, 'sha256'), 'hex')
       <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company :=
    btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));

  v_contact :=
    btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));

  v_city :=
    btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));

  v_state :=
    btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));

  v_gstin :=
    upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;

  if length(v_contact) < 2 then
    raise exception 'CONTACT_NAME_REQUIRED';
  end if;

  insert into public.customers(
    id,
    phone_e164,
    company_name,
    contact_name,
    city,
    state,
    gstin
  )
  values (
    new.id,
    v_phone,
    v_company,
    v_contact,
    v_city,
    v_state,
    v_gstin
  );

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;


################################################################################
# FILE: supabase/migrations/202607170001_carnival_entry_slots_window.sql
################################################################################

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


################################################################################
# FILE: supabase/migrations/202607170002_carnival_functions.sql
################################################################################

-- Maitri Carnival 2026 — RPCs for guarded ordering, status, slots, and assisted admin orders.
-- Apply after 202607170001.

-- ---------------------------------------------------------------------------
-- Internal order writer shared by customer and admin paths.
-- p_is_admin = true bypasses the check-in gate, the edit window and the
-- optimistic-lock conflict (used only by admin_save_order via service_role).
-- ---------------------------------------------------------------------------
create or replace function public._write_order(
  p_customer_id uuid,
  p_firm text,
  p_base_version integer,
  p_items jsonb,
  p_request_id uuid,
  p_is_admin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.system_settings%rowtype;
  v_customer public.customers%rowtype;
  v_order public.orders%rowtype;
  v_existing public.order_save_requests%rowtype;
  v_item jsonb;
  v_design public.designs%rowtype;
  v_design_no text;
  v_barcode text;
  v_qty integer;
  v_seen text[] := array[]::text[];
  v_normalized jsonb := '[]'::jsonb;
  v_design_count integer := 0;
  v_total_pieces integer := 0;
  v_new_version integer;
  v_response jsonb;
begin
  if p_customer_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'ITEMS_MUST_BE_AN_ARRAY';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 500 then
    raise exception 'TOO_MANY_ORDER_ITEMS';
  end if;

  -- Idempotency: a repeated request id returns the stored response.
  select * into v_existing from public.order_save_requests where request_id = p_request_id;
  if found then
    if v_existing.customer_id <> p_customer_id then raise exception 'REQUEST_ID_OWNERSHIP_ERROR'; end if;
    return v_existing.response_json;
  end if;

  select * into v_settings from public.system_settings where singleton = true;

  select * into v_customer from public.customers where id = p_customer_id;
  if not found or not v_customer.active then raise exception 'CUSTOMER_ACCESS_DISABLED'; end if;

  -- Entry gate (customer path only).
  if not p_is_admin and v_customer.checked_in_at is null then
    raise exception 'NOT_CHECKED_IN';
  end if;

  select * into v_order from public.orders where customer_id = p_customer_id and firm = p_firm for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  -- Locks and edit window (customer path only; admin override reopens).
  if not p_is_admin then
    if v_order.status = 'Locked' and not v_order.admin_unlocked then
      raise exception 'ORDER_LOCKED';
    end if;
    if v_customer.edit_deadline is not null
       and now() > v_customer.edit_deadline
       and not v_order.admin_unlocked then
      raise exception 'EDIT_WINDOW_CLOSED';
    end if;

    -- Optimistic concurrency (customer path only).
    if coalesce(p_base_version, 0) <> v_order.version then
      v_response := jsonb_build_object(
        'ok', false,
        'code', 'ORDER_VERSION_CONFLICT',
        'message', 'This order changed in another tab or device. Reload the latest version before saving.',
        'order', public.order_state_json(v_order.id)
      );
      insert into public.order_save_requests(
        request_id, order_id, customer_id, previous_version, new_version,
        design_count, total_pieces, result, response_json, error
      ) values (
        p_request_id, v_order.id, p_customer_id, coalesce(p_base_version, 0), v_order.version,
        v_order.total_designs, v_order.total_pieces, 'Conflict', v_response, 'ORDER_VERSION_CONFLICT'
      );
      return v_response;
    end if;
  end if;

  -- Validate and normalize the incoming cart.
  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_item ->> 'designNo', v_item ->> 'design_no', ''));
    v_barcode := btrim(coalesce(v_item ->> 'barcode', ''));

    begin
      v_qty := (v_item ->> 'qty')::integer;
    exception when others then
      raise exception 'INVALID_QUANTITY_FOR_%', coalesce(nullif(v_design_no, ''), 'ITEM');
    end;

    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;
    if v_qty < 1 or v_qty > 9999 then raise exception 'INVALID_QUANTITY_FOR_%', v_design_no; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_%', v_design_no; end if;

    select * into v_design from public.designs where design_no = v_design_no and active = true;
    if not found then raise exception 'INACTIVE_OR_UNKNOWN_DESIGN_%', v_design_no; end if;
    if v_design.firm not in (p_firm, 'Both') then
      raise exception 'DESIGN_%_DOES_NOT_BELONG_TO_%', v_design_no, p_firm;
    end if;

    v_seen := array_append(v_seen, v_design_no);
    v_design_count := v_design_count + 1;
    v_total_pieces := v_total_pieces + v_qty;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'barcode', v_barcode,
      'designNo', v_design.design_no,
      'qty', v_qty,
      'category', v_design.category,
      'fabric', v_design.fabric,
      'color', v_design.color,
      'description', v_design.description
    ));
  end loop;

  delete from public.order_items where order_id = v_order.id;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into public.order_items(
      order_id, barcode, design_no, qty,
      category_snapshot, fabric_snapshot, color_snapshot, description_snapshot
    ) values (
      v_order.id,
      coalesce(v_item ->> 'barcode', ''),
      v_item ->> 'designNo',
      (v_item ->> 'qty')::integer,
      coalesce(v_item ->> 'category', ''),
      coalesce(v_item ->> 'fabric', ''),
      coalesce(v_item ->> 'color', ''),
      coalesce(v_item ->> 'description', '')
    );
  end loop;

  v_new_version := v_order.version + 1;
  update public.orders
  set
    status = case when v_design_count = 0 then 'Draft' else 'Saved' end,
    total_designs = v_design_count,
    total_pieces = v_total_pieces,
    version = v_new_version,
    updated_at = now()
  where id = v_order.id;

  -- Start the account-level 24h edit window on the first order write.
  if v_customer.ordering_started_at is null then
    update public.customers
    set ordering_started_at = now(),
        edit_deadline = now() + make_interval(hours => v_settings.edit_window_hours),
        updated_at = now()
    where id = p_customer_id;
  end if;

  v_response := jsonb_build_object(
    'ok', true,
    'code', 'SAVED',
    'message', case when p_is_admin then 'Order saved by staff.' else 'Order saved.' end,
    'order', public.order_state_json(v_order.id)
  );

  insert into public.order_save_requests(
    request_id, order_id, customer_id, previous_version, new_version,
    design_count, total_pieces, result, response_json
  ) values (
    p_request_id, v_order.id, p_customer_id, v_order.version, v_new_version,
    v_design_count, v_total_pieces, 'Success', v_response
  );

  return v_response;
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer-facing save (guarded).
-- ---------------------------------------------------------------------------
create or replace function public.save_my_order(
  p_firm text,
  p_base_version integer,
  p_items jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  return public._write_order(auth.uid(), p_firm, p_base_version, p_items, p_request_id, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin assisted save (service_role only). Bypasses gate/window/conflict.
-- ---------------------------------------------------------------------------
create or replace function public.admin_save_order(
  p_customer_id uuid,
  p_firm text,
  p_items jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public._write_order(p_customer_id, p_firm, null, p_items, p_request_id, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer status: check-in state, edit window, and current booking.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_customer public.customers%rowtype;
  v_settings public.system_settings%rowtype;
  v_booking jsonb;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_settings from public.system_settings where singleton = true;
  select * into v_customer from public.customers where id = auth.uid();
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  select jsonb_build_object(
    'id', b.id,
    'slotId', b.slot_id,
    'partySize', b.party_size,
    'note', b.note,
    'status', b.status,
    'startsAt', s.starts_at,
    'endsAt', s.ends_at,
    'label', s.label
  )
  into v_booking
  from public.bookings b
  join public.slots s on s.id = b.slot_id
  where b.customer_id = auth.uid() and b.status = 'Booked';

  return jsonb_build_object(
    'checkedIn', v_customer.checked_in_at is not null,
    'checkedInAt', v_customer.checked_in_at,
    'orderingStartedAt', v_customer.ordering_started_at,
    'editDeadline', v_customer.edit_deadline,
    'windowHours', v_settings.edit_window_hours,
    'active', v_customer.active,
    'now', now(),
    'booking', v_booking
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Slots the customer can book, with live booked counts.
-- ---------------------------------------------------------------------------
create or replace function public.list_slots()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'startsAt', s.starts_at,
      'endsAt', s.ends_at,
      'label', s.label,
      'capacity', s.capacity,
      'booked', coalesce(b.cnt, 0),
      'full', s.capacity is not null and coalesce(b.cnt, 0) >= s.capacity
    ) order by s.starts_at
  ), '[]'::jsonb)
  from public.slots s
  left join (
    select slot_id, count(*) cnt
    from public.bookings
    where status = 'Booked'
    group by slot_id
  ) b on b.slot_id = s.id
  where s.active = true;
$$;

-- ---------------------------------------------------------------------------
-- Book / move / cancel the caller's single slot.
-- ---------------------------------------------------------------------------
create or replace function public.book_slot(
  p_slot_id uuid,
  p_party_size integer,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot public.slots%rowtype;
  v_count integer;
  v_party integer := greatest(1, least(99, coalesce(p_party_size, 1)));
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_slot from public.slots where id = p_slot_id and active = true;
  if not found then raise exception 'SLOT_NOT_FOUND'; end if;

  if v_slot.capacity is not null then
    select count(*) into v_count
    from public.bookings
    where slot_id = p_slot_id and status = 'Booked' and customer_id <> auth.uid();
    if v_count >= v_slot.capacity then raise exception 'SLOT_FULL'; end if;
  end if;

  insert into public.bookings(customer_id, slot_id, party_size, note, status)
  values (auth.uid(), p_slot_id, v_party, btrim(coalesce(p_note, '')), 'Booked')
  on conflict (customer_id) do update
    set slot_id = excluded.slot_id,
        party_size = excluded.party_size,
        note = excluded.note,
        status = 'Booked',
        updated_at = now();

  return jsonb_build_object('ok', true, 'slotId', p_slot_id, 'partySize', v_party);
end;
$$;

create or replace function public.cancel_my_booking()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  delete from public.bookings where customer_id = auth.uid();
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin entry helpers (service_role only).
-- ---------------------------------------------------------------------------
create or replace function public.check_in_customer(p_customer_id uuid, p_admin_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.customers%rowtype;
begin
  update public.customers
  set checked_in_at = coalesce(checked_in_at, now()),
      checked_in_by = coalesce(checked_in_by, p_admin_user_id),
      updated_at = now()
  where id = p_customer_id
  returning * into v_row;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  return jsonb_build_object('id', v_row.id, 'checkedInAt', v_row.checked_in_at);
end;
$$;

create or replace function public.revoke_entry(p_customer_id uuid, p_admin_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.customers%rowtype;
begin
  update public.customers
  set checked_in_at = null, checked_in_by = null, updated_at = now()
  where id = p_customer_id
  returning * into v_row;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  return jsonb_build_object('id', v_row.id, 'checkedInAt', null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function public._write_order(uuid, text, integer, jsonb, uuid, boolean) from public, anon, authenticated;
revoke all on function public.save_my_order(text, integer, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.admin_save_order(uuid, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.get_my_status() from public, anon, authenticated;
revoke all on function public.list_slots() from public, anon, authenticated;
revoke all on function public.book_slot(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.cancel_my_booking() from public, anon, authenticated;
revoke all on function public.check_in_customer(uuid, uuid) from public, anon, authenticated;
revoke all on function public.revoke_entry(uuid, uuid) from public, anon, authenticated;

grant execute on function public.save_my_order(text, integer, jsonb, uuid) to authenticated;
grant execute on function public.get_my_status() to authenticated;
grant execute on function public.list_slots() to authenticated;
grant execute on function public.book_slot(uuid, integer, text) to authenticated;
grant execute on function public.cancel_my_booking() to authenticated;

grant execute on function public.admin_save_order(uuid, text, jsonb, uuid) to service_role;
grant execute on function public.check_in_customer(uuid, uuid) to service_role;
grant execute on function public.revoke_entry(uuid, uuid) to service_role;


################################################################################
# FILE: supabase/migrations/202607170003_supabase_master_products.sql
################################################################################

-- Supabase is the authoritative product master. The Google Sheet is an
-- import/mirror only and must never deactivate designs that live in Supabase.
-- This redefines apply_product_snapshot to upsert without deactivating.

create or replace function public.apply_product_snapshot(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  v_result := public.upsert_product_rows(p_rows);

  insert into public.product_sync_runs(mode, received_count, upserted_count, deactivated_count, status)
  values (
    'FULL_SNAPSHOT',
    jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    coalesce((v_result ->> 'upserted')::integer, 0),
    0,
    'Success'
  );

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', coalesce((v_result ->> 'upserted')::integer, 0),
    'deactivated', 0,
    'note', 'Supabase is master; sheet sync no longer deactivates designs.',
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('FULL_SNAPSHOT', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

revoke all on function public.apply_product_snapshot(jsonb) from public, anon, authenticated;
grant execute on function public.apply_product_snapshot(jsonb) to service_role;


################################################################################
# FILE: supabase/migrations/202607170004_lookups_agent.sql
################################################################################

-- Shared lookup values (dropdowns with add-new) + customer agent field.

-- ---------------------------------------------------------------------------
-- Lookup values: category / fabric / color / city / agent
-- ---------------------------------------------------------------------------
create table if not exists public.lookup_values (
  kind text not null check (kind in ('category','fabric','color','city','agent')),
  value text not null check (length(btrim(value)) between 1 and 120),
  created_at timestamptz not null default now(),
  primary key (kind, value)
);

alter table public.lookup_values enable row level security;

-- Reference data: readable by anyone (registration form needs city/agent before login).
drop policy if exists lookup_values_read on public.lookup_values;
create policy lookup_values_read on public.lookup_values for select to anon, authenticated using (true);
revoke all on public.lookup_values from anon, authenticated;
grant select on public.lookup_values to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Customer agent
-- ---------------------------------------------------------------------------
alter table public.customers add column if not exists agent text not null default '';
grant update (company_name, contact_name, city, state, gstin, agent) on public.customers to authenticated;

-- ---------------------------------------------------------------------------
-- Auto-maintain lookup_values from live data (no manual upkeep, no dupes)
-- ---------------------------------------------------------------------------
create or replace function public.sync_customer_lookups()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(new.city,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('city', btrim(new.city)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.agent,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('agent', btrim(new.agent)) on conflict do nothing;
  end if;
  return new;
end;$$;

drop trigger if exists customers_sync_lookups on public.customers;
create trigger customers_sync_lookups
after insert or update of city, agent on public.customers
for each row execute function public.sync_customer_lookups();

create or replace function public.sync_design_lookups()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(new.category,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('category', btrim(new.category)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.fabric,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('fabric', btrim(new.fabric)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.color,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('color', btrim(new.color)) on conflict do nothing;
  end if;
  return new;
end;$$;

drop trigger if exists designs_sync_lookups on public.designs;
create trigger designs_sync_lookups
after insert or update of category, fabric, color on public.designs
for each row execute function public.sync_design_lookups();

-- Seed from existing data.
insert into public.lookup_values(kind,value)
select 'category', btrim(category) from public.designs where btrim(coalesce(category,'')) <> ''
union select 'fabric', btrim(fabric) from public.designs where btrim(coalesce(fabric,'')) <> ''
union select 'color', btrim(color) from public.designs where btrim(coalesce(color,'')) <> ''
union select 'city', btrim(city) from public.customers where btrim(coalesce(city,'')) <> ''
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- list_lookups(): all dropdown values grouped by kind (anon + authenticated)
-- ---------------------------------------------------------------------------
create or replace function public.list_lookups()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(kind, vals), '{}'::jsonb)
  from (
    select kind, jsonb_agg(value order by value) as vals
    from public.lookup_values group by kind
  ) t;
$$;

revoke all on function public.list_lookups() from public;
grant execute on function public.list_lookups() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Provision agent on registration (extend the auth trigger)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text; v_contact text; v_city text; v_state text; v_gstin text; v_agent text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;
  if split_part(lower(coalesce(new.email,'')),'@',2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;
  if not v_settings.registration_enabled then raise exception 'REGISTRATION_CLOSED'; end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164',''),'\D','','g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then raise exception 'INVALID_CUSTOMER_PHONE'; end if;
  if split_part(lower(new.email),'@',1) <> ('c' || v_phone) then raise exception 'PHONE_EMAIL_MISMATCH'; end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code','');
    if encode(extensions.digest(v_access_code,'sha256'),'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name',''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name',''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city',''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state',''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin','')));
  v_agent := btrim(coalesce(new.raw_user_meta_data ->> 'agent',''));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin, agent)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin, v_agent);

  insert into public.orders(customer_id, firm, status)
  values (new.id,'Maitri','Draft'), (new.id,'Niharika','Draft');

  return new;
end;
$$;


################################################################################
# FILE: supabase/migrations/202607170005_admin_dashboard_rpc.sql
################################################################################

-- Server-side dashboard aggregation. Keeps the admin dashboard fast at scale
-- (hundreds of customers, thousands of order items) by computing KPIs, the
-- selected breakdown (top 100) and a page of orders in SQL. Admin-gated.

create or replace function public.admin_dashboard(
  p_filters jsonb default '{}'::jsonb,
  p_search text default '',
  p_breakdown text default 'firm',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
  v_search text := '%' || btrim(coalesce(p_search, '')) || '%';
  v_kpis jsonb;
  v_breakdown jsonb;
  v_orders jsonb;
  v_total integer;
  v_states jsonb;
begin
  if not public.is_admin_user(auth.uid()) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_breakdown not in ('firm','category','fabric','color','designNo','companyName','state','city') then
    p_breakdown := 'firm';
  end if;

  drop table if exists _f;
  create temporary table _f on commit drop as
  select
    o.id as order_id, o.firm, o.status, o.updated_at,
    o.customer_id,
    i.design_no, i.qty,
    coalesce(nullif(btrim(i.category_snapshot),''),'—') as category,
    coalesce(nullif(btrim(i.fabric_snapshot),''),'—') as fabric,
    coalesce(nullif(btrim(i.color_snapshot),''),'—') as color,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.state),''),'—') as state,
    coalesce(nullif(btrim(c.city),''),'—') as city,
    c.agent
  from public.order_items i
  join public.orders o on o.id = i.order_id
  join public.customers c on c.id = o.customer_id
  where
    (not (p_filters ? 'firm')       or o.firm = any(select jsonb_array_elements_text(p_filters->'firm')))
    and (not (p_filters ? 'state')  or coalesce(nullif(btrim(c.state),''),'—') = any(select jsonb_array_elements_text(p_filters->'state')))
    and (not (p_filters ? 'city')   or coalesce(nullif(btrim(c.city),''),'—') = any(select jsonb_array_elements_text(p_filters->'city')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'category')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'fabric')))
    and (not (p_filters ? 'color')  or coalesce(nullif(btrim(i.color_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'color')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters->'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters->'companyName')))
    and (
      btrim(coalesce(p_search,'')) = '' or
      c.company_name ilike v_search or c.contact_name ilike v_search or
      c.phone_e164 ilike v_search or i.design_no ilike v_search
    );

  -- KPIs
  select jsonb_build_object(
    'totalSets', coalesce(sum(qty),0),
    'customers', count(distinct customer_id),
    'orders', count(distinct order_id),
    'designs', count(distinct design_no),
    'maitriSets', coalesce(sum(qty) filter (where firm='Maitri'),0),
    'niharikaSets', coalesce(sum(qty) filter (where firm='Niharika'),0)
  ) into v_kpis from _f;

  -- Breakdown (top 100) for the requested dimension
  execute format($q$
    select coalesce(jsonb_agg(rec order by (rec->>'sets')::int desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'label', %1$s,
        'sets', sum(qty),
        'designs', count(distinct design_no),
        'customers', count(distinct customer_id)
      ) as rec
      from _f group by %1$s order by sum(qty) desc limit 100
    ) s
  $q$, case p_breakdown
        when 'designNo' then 'design_no'
        when 'companyName' then 'company_name'
        else quote_ident(p_breakdown) end)
  into v_breakdown;

  -- Orders page
  select count(*) into v_total from (select distinct order_id from _f) t;

  select coalesce(jsonb_agg(o), '[]'::jsonb) into v_orders from (
    select jsonb_build_object(
      'orderId', order_id, 'firm', min(firm), 'status', min(status),
      'companyName', min(company_name), 'contactName', min(contact_name),
      'phone', min(phone_e164), 'city', min(city), 'state', min(state), 'agent', min(agent),
      'customerId', min(customer_id::text),
      'sets', sum(qty), 'designs', count(distinct design_no),
      'updatedAt', max(updated_at)
    ) as o
    from _f group by order_id
    order by max(updated_at) desc
    limit greatest(1, least(200, coalesce(p_limit,50))) offset greatest(0, coalesce(p_offset,0))
  ) t;

  select coalesce(jsonb_agg(distinct state order by state), '[]'::jsonb)
  into v_states from (select coalesce(nullif(btrim(state),''),'—') as state from public.customers where btrim(coalesce(state,'')) <> '') s;

  return jsonb_build_object(
    'kpis', v_kpis,
    'breakdown', v_breakdown,
    'orders', v_orders,
    'totalOrders', v_total,
    'states', v_states,
    'generatedAt', now()
  );
end;
$$;

revoke all on function public.admin_dashboard(jsonb, text, text, integer, integer) from public, anon;
grant execute on function public.admin_dashboard(jsonb, text, text, integer, integer) to authenticated;
