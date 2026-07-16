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
