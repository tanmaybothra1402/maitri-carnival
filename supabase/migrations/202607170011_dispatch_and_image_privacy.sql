-- ---------------------------------------------------------------------------
-- Maitri Carnival 2026 — Dispatch module + customer image privacy.
--
-- 1. Dispatch state (per order line) with an append-only event log.
-- 2. A dispatched line becomes immutable for BOTH customer and staff.
--    This lock deliberately outranks orders.admin_unlocked: reopening an
--    order does NOT reopen a dispatched line. Staff must undispatch first.
-- 3. Customer-facing readers no longer return designs.image_url. Customers
--    receive a design key only; the `design-image` Edge Function serves a
--    medium-blur JPEG. Admin paths keep full resolution.
-- ---------------------------------------------------------------------------

-- ── 1. Dispatch tables ─────────────────────────────────────────────────────

create table if not exists public.dispatch_lines (
  order_id        uuid    not null references public.orders(id) on delete cascade,
  design_no       text    not null,
  dispatched_sets integer not null default 0 check (dispatched_sets >= 0),
  ordered_sets    integer not null default 0 check (ordered_sets >= 0),
  dispatched_at   timestamptz not null default now(),
  dispatched_by   uuid,
  updated_at      timestamptz not null default now(),
  primary key (order_id, design_no)
);

create index if not exists dispatch_lines_order_idx
  on public.dispatch_lines(order_id);

-- Append-only. Every save writes one row, so partial-then-complete-later
-- keeps its full history instead of overwriting a single record.
create table if not exists public.dispatch_events (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders(id) on delete cascade,
  actor_id   uuid,
  note       text not null default '',
  lines      jsonb not null default '[]'::jsonb,
  status     text not null default 'Pending',
  created_at timestamptz not null default now()
);

create index if not exists dispatch_events_order_idx
  on public.dispatch_events(order_id, created_at desc);

-- Rolled-up state so the queue can filter without aggregating every time.
alter table public.orders
  add column if not exists dispatch_status text not null default 'Pending';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_dispatch_status_check'
  ) then
    alter table public.orders
      add constraint orders_dispatch_status_check
      check (dispatch_status in ('Pending', 'Partial', 'Completed'));
  end if;
end $$;

create index if not exists orders_dispatch_status_idx
  on public.orders(dispatch_status);

alter table public.dispatch_lines  enable row level security;
alter table public.dispatch_events enable row level security;
-- No policies: customers must never read dispatch data. Service role only.

-- ── 2. Helpers ─────────────────────────────────────────────────────────────

-- A design is locked once any sets have actually gone out.
create or replace function public.is_design_dispatched(p_order_id uuid, p_design_no text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.dispatch_lines
    where order_id = p_order_id
      and design_no = p_design_no
      and dispatched_sets > 0
  );
$$;

create or replace function public.recompute_dispatch_status(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lines    integer;
  v_full     integer;
  v_any      integer;
  v_status   text;
begin
  select count(*)::integer into v_lines
  from public.order_items where order_id = p_order_id;

  select
    count(*) filter (where dl.dispatched_sets >= oi.qty and dl.dispatched_sets > 0)::integer,
    count(*) filter (where dl.dispatched_sets > 0)::integer
  into v_full, v_any
  from public.order_items oi
  join public.dispatch_lines dl
    on dl.order_id = oi.order_id and dl.design_no = oi.design_no
  where oi.order_id = p_order_id;

  v_status := case
    when v_lines = 0 or coalesce(v_any, 0) = 0 then 'Pending'
    when coalesce(v_full, 0) >= v_lines        then 'Completed'
    else 'Partial'
  end;

  update public.orders
  set dispatch_status = v_status, updated_at = now()
  where id = p_order_id;

  return v_status;
end;
$$;

-- ── 3. Dispatch writer ─────────────────────────────────────────────────────
-- p_lines: [{ designNo, dispatchedSets }]. Sending 0 undispatches a line,
-- which returns it to normal editing (subject to the usual window/lock rules).

create or replace function public.admin_save_dispatch(
  p_order_id uuid,
  p_lines    jsonb,
  p_note     text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     public.orders%rowtype;
  v_line      jsonb;
  v_design_no text;
  v_sets      integer;
  v_ordered   integer;
  v_status    text;
begin
  if p_order_id is null then raise exception 'ORDER_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' then
    raise exception 'LINES_MUST_BE_AN_ARRAY';
  end if;
  if length(coalesce(p_note, '')) > 2000 then raise exception 'NOTE_TOO_LONG'; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  for v_line in select value from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_line ->> 'designNo', v_line ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;

    begin
      v_sets := coalesce((v_line ->> 'dispatchedSets')::integer, 0);
    exception when others then
      raise exception 'INVALID_DISPATCH_QUANTITY_FOR_%', v_design_no;
    end;

    select qty into v_ordered
    from public.order_items
    where order_id = p_order_id and design_no = v_design_no;

    if not found then raise exception 'DESIGN_%_NOT_IN_ORDER', v_design_no; end if;
    if v_sets < 0 or v_sets > v_ordered then
      raise exception 'DISPATCH_EXCEEDS_ORDERED_FOR_%', v_design_no;
    end if;

    if v_sets = 0 then
      delete from public.dispatch_lines
      where order_id = p_order_id and design_no = v_design_no;
    else
      insert into public.dispatch_lines(
        order_id, design_no, dispatched_sets, ordered_sets, dispatched_by
      ) values (p_order_id, v_design_no, v_sets, v_ordered, p_actor_id)
      on conflict (order_id, design_no) do update set
        dispatched_sets = excluded.dispatched_sets,
        ordered_sets    = excluded.ordered_sets,
        dispatched_by   = excluded.dispatched_by,
        updated_at      = now();
    end if;
  end loop;

  v_status := public.recompute_dispatch_status(p_order_id);

  insert into public.dispatch_events(order_id, actor_id, note, lines, status)
  values (p_order_id, p_actor_id, coalesce(btrim(p_note), ''), coalesce(p_lines, '[]'::jsonb), v_status);

  return jsonb_build_object('ok', true, 'status', v_status, 'orderId', p_order_id);
end;
$$;

-- Full dispatch view for the admin panel. Full-resolution images: dispatch
-- staff must be able to open and identify the actual product.
create or replace function public.admin_dispatch_detail(p_order_id uuid)
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
    'dispatchStatus', o.dispatch_status,
    'customer', jsonb_build_object(
      'id', c.id,
      'companyName', c.company_name,
      'contactName', c.contact_name,
      'phone', c.phone_e164,
      'city', c.city,
      'state', c.state
    ),
    'lines', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'designNo', i.design_no,
          'imageUrl', d.image_url,
          'qty', i.qty,
          'note', i.line_note,
          'category', i.category_snapshot,
          'style', i.style_snapshot,
          'fabric', i.fabric_snapshot,
          'pcsPerSet', i.pcs_per_set_snapshot,
          'dispatchedSets', coalesce(dl.dispatched_sets, 0)
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      join public.designs d on d.design_no = i.design_no
      left join public.dispatch_lines dl
        on dl.order_id = i.order_id and dl.design_no = i.design_no
      where i.order_id = o.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'note', e.note,
          'status', e.status,
          'createdAt', e.created_at
        ) order by e.created_at desc
      )
      from public.dispatch_events e
      where e.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  join public.customers c on c.id = o.customer_id
  where o.id = p_order_id;
$$;

-- ── 4. Lock dispatched lines inside the single write choke point ───────────
-- Applies to customers, staff and assisted orders alike, because every write
-- path funnels through _write_order.

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
  v_note text;
  v_qty integer;
  v_is_delete boolean;
  v_seen text[] := array[]::text[];
  v_delete_seen text[] := array[]::text[];
  v_normalized jsonb := '[]'::jsonb;
  v_operation_count integer := 0;
  v_design_count integer := 0;
  v_total_sets integer := 0;
  v_total_pieces integer := 0;
  v_new_version integer;
  v_response jsonb;
  v_was_merged boolean := false;
  v_operation_mode boolean := false;
  v_existing_qty integer;
begin
  if p_customer_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then raise exception 'ITEMS_MUST_BE_AN_ARRAY'; end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 1000 then raise exception 'TOO_MANY_ORDER_OPERATIONS'; end if;

  select exists(
    select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x(value)
    where x.value ? '_op' or x.value ? '_delete' or x.value ? 'delete'
  ) into v_operation_mode;

  select * into v_existing from public.order_save_requests where request_id = p_request_id;
  if found then
    if v_existing.customer_id <> p_customer_id then raise exception 'REQUEST_ID_OWNERSHIP_ERROR'; end if;
    return v_existing.response_json;
  end if;

  select * into v_settings from public.system_settings where singleton = true;
  select * into v_customer from public.customers where id = p_customer_id;
  if not found or not v_customer.active then raise exception 'CUSTOMER_ACCESS_DISABLED'; end if;

  if not p_is_admin and v_customer.checked_in_at is null then raise exception 'NOT_CHECKED_IN'; end if;

  select * into v_order from public.orders where customer_id = p_customer_id and firm = p_firm for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if not p_is_admin then
    if v_order.status = 'Locked' and not v_order.admin_unlocked then raise exception 'ORDER_LOCKED'; end if;
    if v_customer.edit_deadline is not null and now() > v_customer.edit_deadline and not v_order.admin_unlocked then
      raise exception 'EDIT_WINDOW_CLOSED';
    end if;
    v_was_merged := coalesce(p_base_version, 0) <> v_order.version;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_item ->> 'designNo', v_item ->> 'design_no', ''));
    v_is_delete := lower(btrim(coalesce(v_item ->> '_delete', v_item ->> 'delete', 'false'))) in ('true','1','yes');
    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;

    if v_is_delete then
      if v_design_no = any(v_delete_seen) then continue; end if;
      -- Dispatched lines cannot be removed. Undispatch first.
      if public.is_design_dispatched(v_order.id, v_design_no) then
        raise exception 'DESIGN_DISPATCHED_%', v_design_no;
      end if;
      v_delete_seen := array_append(v_delete_seen, v_design_no);
      v_operation_count := v_operation_count + 1;
      continue;
    end if;

    v_barcode := btrim(coalesce(v_item ->> 'barcode', ''));
    v_note := btrim(coalesce(v_item ->> 'note', v_item ->> 'lineNote', v_item ->> 'line_note', ''));
    if length(v_note) > 500 then raise exception 'NOTE_TOO_LONG_FOR_%', v_design_no; end if;

    begin
      v_qty := (v_item ->> 'qty')::integer;
    exception when others then
      raise exception 'INVALID_QUANTITY_FOR_%', v_design_no;
    end;
    if v_qty < 1 or v_qty > 9999 then raise exception 'INVALID_QUANTITY_FOR_%', v_design_no; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_%', v_design_no; end if;

    -- A dispatched line is frozen. Re-sending it unchanged is tolerated so
    -- that a full-cart save from a stale client does not fail outright.
    if public.is_design_dispatched(v_order.id, v_design_no) then
      select qty into v_existing_qty
      from public.order_items
      where order_id = v_order.id and design_no = v_design_no;
      if coalesce(v_existing_qty, -1) <> v_qty then
        raise exception 'DESIGN_DISPATCHED_%', v_design_no;
      end if;
    end if;

    select * into v_design from public.designs where design_no = v_design_no and active = true;
    if not found then raise exception 'INACTIVE_OR_UNKNOWN_DESIGN_%', v_design_no; end if;
    if v_design.firm not in (p_firm, 'Both') then raise exception 'DESIGN_%_DOES_NOT_BELONG_TO_%', v_design_no, p_firm; end if;

    v_seen := array_append(v_seen, v_design_no);
    v_operation_count := v_operation_count + 1;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'barcode', v_barcode,
      'designNo', v_design.design_no,
      'qty', v_qty,
      'category', v_design.category,
      'style', v_design.style,
      'fabric', v_design.fabric,
      'pcsPerSet', v_design.pcs_per_set,
      'note', v_note,
      'color', v_design.color,
      'description', v_design.description
    ));
  end loop;

  if array_length(v_delete_seen, 1) is not null then
    delete from public.order_items
    where order_id = v_order.id and design_no = any(v_delete_seen);
  end if;

  -- Legacy full-cart replacement. Dispatched designs are excluded so a stale
  -- client that omits them cannot silently delete goods already shipped.
  if not v_operation_mode and (p_is_admin or not v_was_merged) then
    delete from public.order_items
    where order_id = v_order.id
      and not (design_no = any(v_seen))
      and not public.is_design_dispatched(v_order.id, design_no);
  end if;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into public.order_items(
      order_id, barcode, design_no, qty,
      category_snapshot, style_snapshot, fabric_snapshot, pcs_per_set_snapshot,
      line_note, color_snapshot, description_snapshot
    ) values (
      v_order.id,
      coalesce(v_item ->> 'barcode', ''),
      v_item ->> 'designNo',
      (v_item ->> 'qty')::integer,
      coalesce(v_item ->> 'category', ''),
      coalesce(v_item ->> 'style', ''),
      coalesce(v_item ->> 'fabric', ''),
      (v_item ->> 'pcsPerSet')::integer,
      coalesce(v_item ->> 'note', ''),
      coalesce(v_item ->> 'color', ''),
      coalesce(v_item ->> 'description', '')
    )
    on conflict (order_id, design_no) do update set
      barcode = excluded.barcode,
      qty = excluded.qty,
      category_snapshot = excluded.category_snapshot,
      style_snapshot = excluded.style_snapshot,
      fabric_snapshot = excluded.fabric_snapshot,
      pcs_per_set_snapshot = excluded.pcs_per_set_snapshot,
      line_note = excluded.line_note,
      color_snapshot = excluded.color_snapshot,
      description_snapshot = excluded.description_snapshot,
      updated_at = now();
  end loop;

  select count(*)::integer,
         coalesce(sum(qty),0)::integer,
         coalesce(sum(qty * pcs_per_set_snapshot),0)::integer
  into v_design_count, v_total_sets, v_total_pieces
  from public.order_items where order_id = v_order.id;

  if v_operation_count = 0 then
    v_new_version := v_order.version;
  else
    v_new_version := v_order.version + 1;
    update public.orders
    set status = case when v_design_count = 0 then 'Draft' else 'Saved' end,
        total_designs = v_design_count,
        total_sets = v_total_sets,
        total_pieces = v_total_pieces,
        version = v_new_version,
        updated_at = now()
    where id = v_order.id;

    if v_customer.ordering_started_at is null then
      update public.customers
      set ordering_started_at = now(),
          edit_deadline = now() + make_interval(hours => v_settings.edit_window_hours),
          updated_at = now()
      where id = p_customer_id;
    end if;

    perform public.recompute_dispatch_status(v_order.id);
  end if;

  v_response := jsonb_build_object(
    'ok', true,
    'code', case when v_operation_count = 0 then 'NO_CHANGES' when v_was_merged then 'MERGED' else 'SAVED' end,
    'message', case
      when v_operation_count = 0 then 'No order changes to save.'
      when v_was_merged then 'Your changes were merged with the latest order.'
      when p_is_admin then 'Order saved by staff.'
      else 'Order saved.'
    end,
    'order', public.order_state_json(v_order.id)
  );

  insert into public.order_save_requests(
    request_id, order_id, customer_id, previous_version, new_version,
    design_count, total_sets, total_pieces, result, response_json
  ) values (
    p_request_id, v_order.id, p_customer_id, v_order.version, v_new_version,
    v_design_count, v_total_sets, v_total_pieces, 'Success', v_response
  );

  return v_response;
end;
$$;

-- ── 5. Customer image privacy ──────────────────────────────────────────────
-- order_state_json is shared by customer and admin readers, so the master
-- ImageKit URL is removed here and re-injected server-side by admin-api,
-- which holds the service role. Customers receive `imageKey` (the design
-- number) and fetch a medium-blur JPEG from the design-image function.
-- `locked` tells the customer app which lines are frozen by dispatch.

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
    'adminUnlocked', o.admin_unlocked,
    'dispatchStatus', o.dispatch_status,
    'totalDesigns', o.total_designs,
    'totalSets', o.total_sets,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'imageKey', i.design_no,
          'qty', i.qty,
          'category', i.category_snapshot,
          'style', i.style_snapshot,
          'fabric', i.fabric_snapshot,
          'pcsPerSet', i.pcs_per_set_snapshot,
          'totalPieces', i.qty * i.pcs_per_set_snapshot,
          'note', i.line_note,
          'color', i.color_snapshot,
          'description', i.description_snapshot,
          'locked', coalesce(dl.dispatched_sets, 0) > 0
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      left join public.dispatch_lines dl
        on dl.order_id = i.order_id and dl.design_no = i.design_no
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$$;

-- lookup_barcode is granted to `authenticated`, which includes customers.
-- It must not leak the master image URL either.
drop function if exists public.lookup_barcode(text);
create function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  image_key text,
  category text,
  style text,
  fabric text,
  pcs_per_set integer,
  description text,
  color text
)
language sql
stable
-- Must be SECURITY DEFINER now: the direct SELECT grants on designs and
-- barcode_mappings are revoked below, so this function can no longer rely on
-- the caller's table privileges. It returns image_key, never image_url.
security definer
set search_path = public
as $$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.design_no as image_key,
    d.category,
    d.style,
    d.fabric,
    d.pcs_per_set,
    d.description,
    d.color
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$$;

-- CRITICAL: 202607150002 granted `select on public.designs` to `authenticated`,
-- and customers are authenticated users. Without this revoke, any logged-in
-- customer could call PostgREST directly —
--   GET /rest/v1/designs?select=design_no,image_url
-- — and download every master ImageKit URL in the catalogue, defeating the
-- entire blur. Neither web/user.html nor the admin console reads this table
-- directly; both go through RPCs or the service-role Edge Functions, so the
-- grant is safe to drop.
revoke select on public.designs from authenticated;
revoke all on public.designs from anon, authenticated;

-- Same exposure via the mapping table: barcode -> design_no is harmless on its
-- own, but keep it consistent. lookup_barcode remains the only customer path.
revoke all on public.barcode_mappings from anon, authenticated;

-- Resolver used only by the design-image Edge Function (service role).
create or replace function public.design_image_source(p_design_no text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select d.image_url
  from public.designs d
  where d.design_no = btrim(p_design_no)
    and d.active = true
  limit 1;
$$;

-- ── 6. Grants ──────────────────────────────────────────────────────────────

revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated;

revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
grant execute on function public.order_state_json(uuid) to service_role;

revoke all on function public._write_order(uuid, text, integer, jsonb, uuid, boolean) from public, anon, authenticated;

revoke all on function public.is_design_dispatched(uuid, text) from public, anon, authenticated;
grant execute on function public.is_design_dispatched(uuid, text) to service_role;

revoke all on function public.recompute_dispatch_status(uuid) from public, anon, authenticated;
grant execute on function public.recompute_dispatch_status(uuid) to service_role;

revoke all on function public.admin_save_dispatch(uuid, jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_save_dispatch(uuid, jsonb, text, uuid) to service_role;

revoke all on function public.admin_dispatch_detail(uuid) from public, anon, authenticated;
grant execute on function public.admin_dispatch_detail(uuid) to service_role;

revoke all on function public.design_image_source(text) from public, anon, authenticated;
grant execute on function public.design_image_source(text) to service_role;

-- ── 7. Dispatch permissions for staff ──────────────────────────────────────

-- staff_profiles.preset and .default_section are CHECK-constrained lists that
-- predate this module. Both must accept 'dispatch' or every staff insert and
-- every "default section follows first ticked module" save would fail.
alter table public.staff_profiles drop constraint if exists staff_profiles_preset_check;
alter table public.staff_profiles
  add constraint staff_profiles_preset_check
  check (preset in ('sales','reception','products','dispatch','manager','administrator','custom'));

alter table public.staff_profiles drop constraint if exists staff_profiles_default_section_check;
alter table public.staff_profiles
  add constraint staff_profiles_default_section_check
  check (default_section in ('reception','dashboard','sale','products','dispatch','admin'));

-- Permissions are JSONB keys on staff_profiles, so the presets carry them.
-- Dispatch is deliberately NOT added to 'sales' or 'products': a packer gets
-- Dispatch alone, and a salesperson does not silently gain dispatch rights.
create or replace function public.staff_permission_defaults(p_preset text)
returns jsonb
language sql
immutable
as $$
  select case lower(coalesce(p_preset,''))
    when 'sales' then jsonb_build_object(
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,
      'reception.view',true
    )
    when 'reception' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'admin.bookings',true
    )
    when 'products' then jsonb_build_object(
      'products.view',true,'products.edit',true,'products.mapping',true
    )
    when 'dispatch' then jsonb_build_object(
      'dispatch.view',true,'dispatch.write',true,'sale.pdf',true
    )
    when 'manager' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'admin.slots',true,'admin.bookings',true
    )
    when 'administrator' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'admin.slots',true,'admin.bookings',true,'admin.staff',true,'admin.settings',true
    )
    else '{}'::jsonb
  end;
$$;

revoke all on function public.staff_permission_defaults(text) from public, anon, authenticated;
grant execute on function public.staff_permission_defaults(text) to service_role;

-- Existing administrators keep working: grant them the new keys in place.
update public.staff_profiles
set permissions = permissions
  || jsonb_build_object('dispatch.view', true, 'dispatch.write', true),
    updated_at = now()
where preset in ('administrator', 'manager');

-- Backfill roll-up for any order that predates this migration.
update public.orders set dispatch_status = 'Pending' where dispatch_status is null;
