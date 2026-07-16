-- Merge-safe concurrent ordering + per-design notes + style/pcs-per-set.
-- Keeps legacy color/description columns for backward compatibility, but the
-- active product/order flows use category + style + fabric and calculate true
-- pieces as sets * pcs_per_set.

-- ---------------------------------------------------------------------------
-- Schema additions (non-destructive)
-- ---------------------------------------------------------------------------
alter table public.designs add column if not exists style text not null default '';
alter table public.designs add column if not exists pcs_per_set integer not null default 1;
alter table public.designs drop constraint if exists designs_pcs_per_set_check;
alter table public.designs add constraint designs_pcs_per_set_check check (pcs_per_set between 1 and 9999);

alter table public.order_items add column if not exists style_snapshot text not null default '';
alter table public.order_items add column if not exists pcs_per_set_snapshot integer not null default 1;
alter table public.order_items add column if not exists line_note text not null default '';
alter table public.order_items drop constraint if exists order_items_pcs_per_set_snapshot_check;
alter table public.order_items add constraint order_items_pcs_per_set_snapshot_check check (pcs_per_set_snapshot between 1 and 9999);
alter table public.order_items drop constraint if exists order_items_line_note_check;
alter table public.order_items add constraint order_items_line_note_check check (length(line_note) <= 500);

alter table public.orders add column if not exists total_sets integer not null default 0;
alter table public.orders drop constraint if exists orders_total_sets_check;
alter table public.orders add constraint orders_total_sets_check check (total_sets >= 0);

alter table public.order_save_requests add column if not exists total_sets integer not null default 0;
update public.order_save_requests set total_sets = total_pieces where total_sets = 0 and total_pieces > 0;

-- Existing qty values represented sets. Existing products default to 1 pc/set,
-- so historical totals remain numerically consistent until masters are updated.
update public.order_items set pcs_per_set_snapshot = 1 where pcs_per_set_snapshot is null or pcs_per_set_snapshot < 1;

update public.orders o
set total_sets = x.total_sets,
    total_pieces = x.total_pieces
from (
  select o2.id,
         coalesce(sum(i.qty), 0)::integer as total_sets,
         coalesce(sum(i.qty * i.pcs_per_set_snapshot), 0)::integer as total_pieces
  from public.orders o2
  left join public.order_items i on i.order_id = o2.id
  group by o2.id
) x
where x.id = o.id;

-- ---------------------------------------------------------------------------
-- Lookups: add style while retaining color rows for old data compatibility.
-- ---------------------------------------------------------------------------
alter table public.lookup_values drop constraint if exists lookup_values_kind_check;
alter table public.lookup_values
  add constraint lookup_values_kind_check
  check (kind in ('category','fabric','style','color','city','agent'));

create or replace function public.sync_design_lookups()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(new.category,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('category', btrim(new.category)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.fabric,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('fabric', btrim(new.fabric)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.style,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('style', btrim(new.style)) on conflict do nothing;
  end if;
  return new;
end;$$;

drop trigger if exists designs_sync_lookups on public.designs;
create trigger designs_sync_lookups
after insert or update of category, fabric, style on public.designs
for each row execute function public.sync_design_lookups();

insert into public.lookup_values(kind,value)
select 'style', btrim(style) from public.designs where btrim(coalesce(style,'')) <> ''
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Product import: Style + PcsPerSet are now first-class master fields.
-- Missing new fields in an older importer do not erase existing DB values.
-- ---------------------------------------------------------------------------
create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_pcs_text text;
  v_pcs integer;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
  v_has_style boolean;
  v_has_pcs boolean;
  v_has_description boolean;
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    v_has_style := (v_row ? 'Style') or (v_row ? 'style');
    v_has_pcs := (v_row ? 'PcsPerSet') or (v_row ? 'pcs_per_set') or (v_row ? 'Pcs');
    v_has_description := (v_row ? 'Description') or (v_row ? 'description');
    v_pcs_text := btrim(coalesce(v_row ->> 'PcsPerSet', v_row ->> 'pcs_per_set', v_row ->> 'Pcs', ''));
    v_pcs := null;
    if v_has_pcs then
      begin
        v_pcs := v_pcs_text::integer;
      exception when others then
        raise exception 'INVALID_PCS_PER_SET_FOR_%', v_design_no;
      end;
      if v_pcs < 1 or v_pcs > 9999 then raise exception 'INVALID_PCS_PER_SET_FOR_%', v_design_no; end if;
    end if;

    insert into public.designs(
      design_no, firm, image_url, category, style, fabric, pcs_per_set,
      description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', '')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Style', v_row ->> 'style', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      coalesce(v_pcs, 1),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      image_url = excluded.image_url,
      category = excluded.category,
      style = case when v_has_style then excluded.style else public.designs.style end,
      fabric = excluded.fabric,
      pcs_per_set = case when v_has_pcs then excluded.pcs_per_set else public.designs.pcs_per_set end,
      description = case when v_has_description then excluded.description else public.designs.description end,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm,
      public.designs.image_url,
      public.designs.category,
      public.designs.style,
      public.designs.fabric,
      public.designs.pcs_per_set,
      public.designs.description,
      public.designs.active,
      public.designs.source_updated_at
    ) is distinct from (
      excluded.firm,
      excluded.image_url,
      excluded.category,
      case when v_has_style then excluded.style else public.designs.style end,
      excluded.fabric,
      case when v_has_pcs then excluded.pcs_per_set else public.designs.pcs_per_set end,
      case when v_has_description then excluded.description else public.designs.description end,
      excluded.active,
      excluded.source_updated_at
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

-- ---------------------------------------------------------------------------
-- Barcode and order-state readers expose the new fields.
-- Legacy color/description keys remain in responses for compatibility.
-- ---------------------------------------------------------------------------
drop function if exists public.lookup_barcode(text);
create function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  image_url text,
  category text,
  style text,
  fabric text,
  pcs_per_set integer,
  description text,
  color text
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
          'imageUrl', d.image_url,
          'qty', i.qty,
          'category', i.category_snapshot,
          'style', i.style_snapshot,
          'fabric', i.fabric_snapshot,
          'pcsPerSet', i.pcs_per_set_snapshot,
          'totalPieces', i.qty * i.pcs_per_set_snapshot,
          'note', i.line_note,
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

-- ---------------------------------------------------------------------------
-- Merge-safe order writer.
-- p_items is an operation list:
--   normal row = upsert that design; {designNo, _delete:true} = delete it.
-- Omitted designs are preserved. This lets admin/customer saves interleave
-- without losing unrelated additions. Same-design edits are last-save-wins.
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

  -- Backward compatibility during rollout: an older client sends a complete
  -- cart without operation markers. If it saved the current version, preserve
  -- the old replacement behaviour. A stale legacy cart is merged instead.
  if not v_operation_mode and (p_is_admin or not v_was_merged) then
    delete from public.order_items
    where order_id = v_order.id and not (design_no = any(v_seen));
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

-- ---------------------------------------------------------------------------
-- Minimal dashboard compatibility: style replaces color; qty remains sets.
-- The larger dashboard redesign is intentionally deferred.
-- ---------------------------------------------------------------------------
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
  if p_breakdown not in ('firm','category','fabric','style','designNo','companyName','state','city') then p_breakdown := 'firm'; end if;

  drop table if exists _f;
  create temporary table _f on commit drop as
  select
    o.id as order_id, o.firm, o.status, o.updated_at, o.customer_id,
    i.design_no, i.qty, i.pcs_per_set_snapshot, (i.qty * i.pcs_per_set_snapshot) as pieces,
    coalesce(nullif(btrim(i.category_snapshot),''),'—') as category,
    coalesce(nullif(btrim(i.fabric_snapshot),''),'—') as fabric,
    coalesce(nullif(btrim(i.style_snapshot),''),'—') as style,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.state),''),'—') as state,
    coalesce(nullif(btrim(c.city),''),'—') as city,
    c.agent
  from public.order_items i
  join public.orders o on o.id = i.order_id
  join public.customers c on c.id = o.customer_id
  where
    (not (p_filters ? 'firm') or o.firm = any(select jsonb_array_elements_text(p_filters->'firm')))
    and (not (p_filters ? 'state') or coalesce(nullif(btrim(c.state),''),'—') = any(select jsonb_array_elements_text(p_filters->'state')))
    and (not (p_filters ? 'city') or coalesce(nullif(btrim(c.city),''),'—') = any(select jsonb_array_elements_text(p_filters->'city')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'category')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'fabric')))
    and (not (p_filters ? 'style') or coalesce(nullif(btrim(i.style_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'style')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters->'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters->'companyName')))
    and (
      btrim(coalesce(p_search,'')) = '' or c.company_name ilike v_search or c.contact_name ilike v_search or
      c.phone_e164 ilike v_search or i.design_no ilike v_search
    );

  select jsonb_build_object(
    'totalSets', coalesce(sum(qty),0),
    'totalPieces', coalesce(sum(pieces),0),
    'customers', count(distinct customer_id),
    'orders', count(distinct order_id),
    'designs', count(distinct design_no),
    'maitriSets', coalesce(sum(qty) filter (where firm='Maitri'),0),
    'niharikaSets', coalesce(sum(qty) filter (where firm='Niharika'),0)
  ) into v_kpis from _f;

  execute format($q$
    select coalesce(jsonb_agg(rec order by (rec->>'sets')::int desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'label', %1$s,
        'sets', sum(qty),
        'pieces', sum(pieces),
        'designs', count(distinct design_no),
        'customers', count(distinct customer_id)
      ) as rec
      from _f group by %1$s order by sum(qty) desc limit 100
    ) s
  $q$, case p_breakdown when 'designNo' then 'design_no' when 'companyName' then 'company_name' else quote_ident(p_breakdown) end)
  into v_breakdown;

  select count(*) into v_total from (select distinct order_id from _f) t;

  select coalesce(jsonb_agg(o), '[]'::jsonb) into v_orders from (
    select jsonb_build_object(
      'orderId', order_id, 'firm', min(firm), 'status', min(status),
      'companyName', min(company_name), 'contactName', min(contact_name),
      'phone', min(phone_e164), 'city', min(city), 'state', min(state), 'agent', min(agent),
      'customerId', min(customer_id::text),
      'sets', sum(qty), 'pieces', sum(pieces), 'designs', count(distinct design_no),
      'updatedAt', max(updated_at)
    ) as o
    from _f group by order_id
    order by max(updated_at) desc
    limit greatest(1, least(200, coalesce(p_limit,50))) offset greatest(0, coalesce(p_offset,0))
  ) t;

  select coalesce(jsonb_agg(distinct state order by state), '[]'::jsonb)
  into v_states from (select coalesce(nullif(btrim(state),''),'—') as state from public.customers where btrim(coalesce(state,'')) <> '') s;

  return jsonb_build_object(
    'kpis', v_kpis, 'breakdown', v_breakdown, 'orders', v_orders,
    'totalOrders', v_total, 'states', v_states, 'generatedAt', now()
  );
end;
$$;

revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_product_rows(jsonb) to service_role;
revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated;
revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
grant execute on function public.order_state_json(uuid) to service_role;
revoke all on function public._write_order(uuid, text, integer, jsonb, uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_dashboard(jsonb, text, text, integer, integer) from public, anon;
grant execute on function public.admin_dashboard(jsonb, text, text, integer, integer) to authenticated;
