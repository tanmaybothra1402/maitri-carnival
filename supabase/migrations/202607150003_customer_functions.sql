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
