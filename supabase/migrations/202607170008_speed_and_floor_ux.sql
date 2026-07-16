-- Maitri Carnival 2026: faster customer bootstrap, faster assisted saves,
-- and a single-query reception directory.

create index if not exists bookings_status_customer_idx
  on public.bookings(status, customer_id);
create index if not exists bookings_status_slot_idx
  on public.bookings(status, slot_id);
create index if not exists customers_checked_in_at_idx
  on public.customers(checked_in_at desc);

-- One customer request now returns profile, status, slots, and both firm orders.
create or replace function public.get_my_carnival_bootstrap()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_profile jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select to_jsonb(c) into v_profile
  from public.customers c
  where c.id = v_uid;

  if v_profile is null then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  return jsonb_build_object(
    'profile', v_profile,
    'status', public.get_my_status(),
    'slots', public.list_slots(),
    'orders', jsonb_build_object(
      'Maitri', public.get_my_order_state('Maitri'),
      'Niharika', public.get_my_order_state('Niharika')
    )
  );
end;
$$;

create or replace function public.get_my_orders_state()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
  select jsonb_build_object(
    'Maitri', public.get_my_order_state('Maitri'),
    'Niharika', public.get_my_order_state('Niharika')
  );
$$;

grant execute on function public.get_my_carnival_bootstrap() to authenticated;
grant execute on function public.get_my_orders_state() to authenticated;

-- Reception directory in one database call. Capacity remains number of parties.
create or replace function public.admin_directory(
  p_query text default '',
  p_limit integer default 400
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with matched as (
    select
      c.id,
      c.phone_e164,
      c.company_name,
      c.contact_name,
      c.city,
      c.state,
      c.gstin,
      c.agent,
      c.active,
      c.checked_in_at,
      c.ordering_started_at,
      c.edit_deadline,
      c.created_at,
      b.id booking_id,
      b.party_size,
      b.note booking_note,
      s.id slot_id,
      s.starts_at,
      s.ends_at,
      s.label slot_label
    from public.customers c
    left join lateral (
      select bx.*
      from public.bookings bx
      where bx.customer_id = c.id and bx.status = 'Booked'
      order by bx.updated_at desc
      limit 1
    ) b on true
    left join public.slots s on s.id = b.slot_id
    where nullif(btrim(coalesce(p_query,'')), '') is null
       or c.phone_e164 ilike '%' || btrim(p_query) || '%'
       or c.company_name ilike '%' || btrim(p_query) || '%'
       or c.contact_name ilike '%' || btrim(p_query) || '%'
       or c.city ilike '%' || btrim(p_query) || '%'
       or c.state ilike '%' || btrim(p_query) || '%'
       or c.gstin ilike '%' || btrim(p_query) || '%'
       or c.agent ilike '%' || btrim(p_query) || '%'
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit,400), 600))
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'phone', m.phone_e164,
      'companyName', m.company_name,
      'contactName', m.contact_name,
      'city', m.city,
      'state', m.state,
      'gstin', m.gstin,
      'agent', m.agent,
      'active', m.active,
      'checkedInAt', m.checked_in_at,
      'orderingStartedAt', m.ordering_started_at,
      'editDeadline', m.edit_deadline,
      'booking', case when m.booking_id is null then null else jsonb_build_object(
        'id', m.booking_id,
        'slotId', m.slot_id,
        'startsAt', m.starts_at,
        'endsAt', m.ends_at,
        'label', m.slot_label,
        'partySize', m.party_size,
        'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$$;

revoke all on function public.admin_directory(text,integer) from public, anon, authenticated;
grant execute on function public.admin_directory(text,integer) to service_role;

-- One transaction for order merge plus staff attribution. This removes the
-- per-line update loop that previously made assisted saves feel slow.
create or replace function public.admin_save_order_with_actor(
  p_customer_id uuid,
  p_firm text,
  p_items jsonb,
  p_request_id uuid,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
  v_order_id uuid;
begin
  v_result := public.admin_save_order(
    p_customer_id,
    p_firm,
    coalesce(p_items, '[]'::jsonb),
    p_request_id
  );

  v_order_id := nullif(v_result #>> '{order,id}', '')::uuid;

  if v_order_id is not null then
    update public.order_items oi
    set
      created_by_user_id = case
        when coalesce(oi.created_by_type,'unknown') = 'unknown' then p_admin_user_id
        else oi.created_by_user_id
      end,
      created_by_type = case
        when coalesce(oi.created_by_type,'unknown') = 'unknown' then 'staff'
        else oi.created_by_type
      end,
      last_modified_by_user_id = p_admin_user_id,
      last_modified_by_type = 'staff'
    where oi.order_id = v_order_id
      and oi.design_no in (
        select distinct btrim(coalesce(x.item->>'designNo', x.item->>'design_no', ''))
        from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) as x(item)
        where lower(coalesce(x.item->>'_op','upsert')) <> 'delete'
          and lower(coalesce(x.item->>'_delete','false')) not in ('true','1','yes')
          and btrim(coalesce(x.item->>'designNo', x.item->>'design_no', '')) <> ''
      );
  end if;

  return v_result;
end;
$$;

revoke all on function public.admin_save_order_with_actor(uuid,text,jsonb,uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.admin_save_order_with_actor(uuid,text,jsonb,uuid,uuid)
  to service_role;
