-- 202608010038_dispatch_squareoff.sql
--
-- Checkpoint 4 — square-off: remove a line from the pending dispatch queue without
-- shipping it. Anyone with dispatch.write may square off (decided); the compensating
-- controls are mandatory: reason required, squared lines stay visible, one-tap reverse,
-- a dispatch_events row on both square-off and un-square.
--
-- Flag lives in its OWN service-role table, NOT on buyer-readable order_items — the
-- customer must never see we wrote off their line. Un-squaring DELETEs the row; the
-- dispatch_events trail is the history.
--
-- recompute_dispatch_status is SHARED (callers: admin_save_dispatch, _write_order).
-- Squared-off lines come OUT of the denominator so an order can reach Completed with
-- them outstanding. EDGE CASE — every line squared off: the denominator is 0. Neither
-- 'Completed' (misreports goods as shipped) nor 'Pending' (traps it in the queue) is
-- honest, so this adds a fourth terminal status 'Closed' — left the queue, nothing
-- shipped. Bounded: the CHECK, this function, the category status, and the client pill.
-- data-sync does not touch dispatch_status (not in its orders cols), so no Sheet
-- round-trip; no caller branches on the value. Expected orders affected today: 0.

-- ── the squared-off table (service-role only; NOT a column on order_items) ────
create table if not exists public.dispatch_squareoffs (
  order_id   uuid not null references public.orders(id) on delete cascade,
  design_no  text not null,
  reason     text not null,
  squared_by uuid,
  squared_at timestamptz not null default now(),
  primary key (order_id, design_no)   -- the unique (order_id, design_no)
);
alter table public.dispatch_squareoffs enable row level security;
-- No policies = service-role only. order_items is buyer-readable; this flag must not be.
revoke all on table public.dispatch_squareoffs from public, anon, authenticated;
grant all on table public.dispatch_squareoffs to service_role;
create index if not exists dispatch_squareoffs_order_idx on public.dispatch_squareoffs(order_id);

-- ── dispatch_status gains 'Closed' ───────────────────────────────────────────
alter table public.orders drop constraint if exists orders_dispatch_status_check;
alter table public.orders add constraint orders_dispatch_status_check
  check (dispatch_status in ('Pending','Partial','Completed','Closed'));

-- ── recompute_dispatch_status: squared-off out of the denominator + 'Closed' ──
create or replace function public.recompute_dispatch_status(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_active integer; v_squared integer; v_full integer; v_any integer; v_status text;
begin
  -- active = order lines NOT squared off (the dispatch denominator)
  select count(*)::integer into v_active
  from public.order_items oi
  where oi.order_id = p_order_id
    and not exists (select 1 from public.dispatch_squareoffs s where s.order_id = oi.order_id and s.design_no = oi.design_no);
  -- squared = squared-off rows that still match a line on the order
  select count(*)::integer into v_squared
  from public.dispatch_squareoffs s
  where s.order_id = p_order_id
    and exists (select 1 from public.order_items oi where oi.order_id = p_order_id and oi.design_no = s.design_no);
  -- full/any counted over the ACTIVE (non-squared) lines only
  select
    count(*) filter (where dl.dispatched_sets >= oi.qty and dl.dispatched_sets > 0)::integer,
    count(*) filter (where dl.dispatched_sets > 0)::integer
  into v_full, v_any
  from public.order_items oi
  join public.dispatch_lines dl on dl.order_id = oi.order_id and dl.design_no = oi.design_no
  where oi.order_id = p_order_id
    and not exists (select 1 from public.dispatch_squareoffs s where s.order_id = oi.order_id and s.design_no = oi.design_no);

  v_status := case
    when v_active = 0 and v_squared > 0 then 'Closed'   -- every line squared off
    when v_active = 0 or coalesce(v_any, 0) = 0 then 'Pending'
    when coalesce(v_full, 0) >= v_active            then 'Completed'
    else 'Partial'
  end;

  update public.orders set dispatch_status = v_status, updated_at = now() where id = p_order_id;
  return v_status;
end; $$;
revoke all on function public.recompute_dispatch_status(uuid) from public, anon, authenticated;
grant execute on function public.recompute_dispatch_status(uuid) to service_role;

-- ── square-off / un-square RPCs (both write a dispatch_events row) ────────────
create or replace function public.admin_square_off_line(p_order_id uuid, p_design_no text, p_reason text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_reason text := nullif(btrim(coalesce(p_reason,'')),''); v_dn text := btrim(coalesce(p_design_no,'')); v_status text;
begin
  if p_order_id is null then raise exception 'ORDER_ID_REQUIRED'; end if;
  if v_dn = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;
  if v_reason is null then raise exception 'REASON_REQUIRED'; end if;   -- empty/whitespace rejected
  if not exists (select 1 from public.order_items where order_id = p_order_id and design_no = v_dn) then
    raise exception 'DESIGN_%_NOT_IN_ORDER', v_dn;
  end if;
  insert into public.dispatch_squareoffs(order_id, design_no, reason, squared_by)
    values (p_order_id, v_dn, v_reason, p_actor)
    on conflict (order_id, design_no) do update set reason = excluded.reason, squared_by = excluded.squared_by, squared_at = now();
  v_status := public.recompute_dispatch_status(p_order_id);
  insert into public.dispatch_events(order_id, actor_id, note, lines, status)
    values (p_order_id, p_actor, 'Squared off '||v_dn||': '||v_reason,
            jsonb_build_array(jsonb_build_object('designNo', v_dn, 'squaredOff', true, 'reason', v_reason)), v_status);
  return jsonb_build_object('ok', true, 'status', v_status);
end; $$;
revoke all on function public.admin_square_off_line(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_square_off_line(uuid, text, text, uuid) to service_role;

create or replace function public.admin_unsquare_line(p_order_id uuid, p_design_no text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_dn text := btrim(coalesce(p_design_no,'')); v_status text; v_found boolean;
begin
  if p_order_id is null then raise exception 'ORDER_ID_REQUIRED'; end if;
  if v_dn = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;
  delete from public.dispatch_squareoffs where order_id = p_order_id and design_no = v_dn;
  get diagnostics v_found = row_count;
  v_status := public.recompute_dispatch_status(p_order_id);
  insert into public.dispatch_events(order_id, actor_id, note, lines, status)
    values (p_order_id, p_actor, 'Un-squared '||v_dn,
            jsonb_build_array(jsonb_build_object('designNo', v_dn, 'squaredOff', false)), v_status);
  return jsonb_build_object('ok', true, 'status', v_status, 'removed', v_found);
end; $$;
revoke all on function public.admin_unsquare_line(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_unsquare_line(uuid, text, uuid) to service_role;

-- ── admin_dispatch_orders (035) — filtered pending/status exclude squared-off ─
create or replace function public.admin_dispatch_orders(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  with params as (
    select
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      case when nullif(btrim(coalesce(p_filters ->> 'firm','')),'') in ('Maitri','Niharika')
           then btrim(p_filters ->> 'firm') end as firm,
      case when nullif(btrim(coalesce(p_filters ->> 'dispatchStatus','')),'') in ('Pending','Partial','Completed')
           then btrim(p_filters ->> 'dispatchStatus') end as dispatch_status,
      case when nullif(btrim(coalesce(p_filters ->> 'category','')),'') in ('MR','KT','NRK','MU','BS')
           then btrim(p_filters ->> 'category') end as category,
      nullif(btrim(coalesce(p_filters ->> 'search','')), '') as q,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 300), 500)) as lim,
      greatest(0, coalesce((p_filters ->> 'offset')::int, 0)) as off
  ),
  matched as (
    select o.id, o.customer_id, o.firm, o.status,
           o.updated_at, c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.agent,
           cc.tier, cc.reference_standing, coalesce(cc.crm_status,'pending') as crm_status,
           -- displayed counts + dispatch status: the per-category aggregate when a
           -- category is active, otherwise the whole-order totals. cat.* is NULL when
           -- no category filter is set (the lateral's WHERE short-circuits on p.category).
           case when p.category is null then o.total_designs   else cat.designs end as designs,
           case when p.category is null then o.total_sets      else cat.sets    end as sets,
           case when p.category is null then o.total_pieces    else cat.pieces  end as pieces,
           case when p.category is null then o.dispatch_status  else cat.status  end as disp_status,
           cat.line_count as cat_line_count, cat.pending as cat_pending
    from public.orders o
    join public.customers c on c.id = o.customer_id
    left join public.customer_crm cc on cc.customer_id = o.customer_id
    cross join params p
    left join lateral (
      -- Per-category line aggregate for THIS order. Same Pending/Partial/Completed
      -- logic as recompute_dispatch_status, restricted to the category's lines.
      select
        count(*)::int as line_count,
        count(*)::int as designs,
        coalesce(sum(oi.qty),0)::int as sets,
        coalesce(sum(oi.qty * oi.pcs_per_set_snapshot),0)::int as pieces,
        count(*) filter (where coalesce(dl.dispatched_sets,0) = 0 and sq.order_id is null)::int as pending,
        case
          when count(*) filter (where sq.order_id is null) = 0 and count(*) filter (where sq.order_id is not null) > 0 then 'Closed'
          when count(*) filter (where sq.order_id is null) = 0 then null
          when count(*) filter (where coalesce(dl.dispatched_sets,0) > 0 and sq.order_id is null) = 0 then 'Pending'
          when count(*) filter (where coalesce(dl.dispatched_sets,0) >= oi.qty and coalesce(dl.dispatched_sets,0) > 0 and sq.order_id is null) >= count(*) filter (where sq.order_id is null) then 'Completed'
          else 'Partial'
        end as status
      from public.order_items oi
      left join public.dispatch_lines dl on dl.order_id = oi.order_id and dl.design_no = oi.design_no
      left join public.dispatch_squareoffs sq on sq.order_id = oi.order_id and sq.design_no = oi.design_no
      where oi.order_id = o.id
        and p.category is not null
        and upper(substring(oi.design_no from '^[A-Za-z]+')) = p.category
    ) cat on true
    where o.exhibition_id = p.exhibition_id
      and o.total_designs > 0
      and (p.firm is null or o.firm = p.firm)
      -- category filter: keep an order only if it has >=1 line of the category. BEFORE
      -- the limit (this is inside matched; the limit is applied in the subquery below).
      and (p.category is null or cat.designs > 0)
      -- dispatch-status filter applies to the DISPLAYED status (per-category when filtered).
      and (p.dispatch_status is null
           or (case when p.category is null then o.dispatch_status else cat.status end) = p.dispatch_status)
      and (p.q is null
           or c.company_name ilike '%'||p.q||'%'
           or c.contact_name ilike '%'||p.q||'%'
           or c.phone_e164   ilike '%'||p.q||'%')
  )
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'orderId', pg.id, 'customerId', pg.customer_id, 'firm', pg.firm, 'status', pg.status,
        'dispatchStatus', pg.disp_status, 'designs', pg.designs, 'sets', pg.sets,
        'pieces', pg.pieces, 'updatedAt', pg.updated_at, 'companyName', pg.company_name,
        'contactName', pg.contact_name, 'phone', pg.phone_e164, 'city', pg.city, 'state', pg.state,
        'agent', pg.agent, 'tier', pg.tier,
        'crmStatus', pg.crm_status,
        'referenceStanding', pg.reference_standing,
        'refRejected', exists(select 1 from public.customer_references r where r.customer_id = pg.customer_id and r.verdict = 'rejected'),
        'refRejectReason', (
          select string_agg(distinct coalesce(nullif(btrim(r.notes),''), rc.name, 'rejected'), ' | ')
          from public.customer_references r left join public.reference_companies rc on rc.id = r.company_id
          where r.customer_id = pg.customer_id and r.verdict = 'rejected'),
        'categoryFilter', (select category from params),
        'catLineCount', pg.cat_line_count, 'catPending', pg.cat_pending
      ) order by
        case pg.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
        pg.updated_at desc)
      from (
        select * from matched
        order by
          case matched.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
          matched.updated_at desc
        limit (select lim from params) offset (select off from params)
      ) pg
    ), '[]'::jsonb),
    'total', (select count(*) from matched)
  );
$function$;
revoke all on function public.admin_dispatch_orders(jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_orders(jsonb) to service_role;

-- ── admin_dispatch_detail (035) + per-line squared-off state ───────────
create or replace function public.admin_dispatch_detail(p_order_id uuid, p_category text default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with cat as (
    select case when nullif(btrim(coalesce(p_category,'')),'') in ('MR','KT','NRK','MU','BS')
                then btrim(p_category) end as cf
  )
  select jsonb_build_object(
    'id', o.id, 'firm', o.firm, 'status', o.status, 'dispatchStatus', o.dispatch_status,
    'categoryFilter', (select cf from cat),
    'allDesigns', (select count(*)::int from public.order_items where order_id = o.id),
    'customer', jsonb_build_object(
      'id', c.id, 'companyName', c.company_name, 'contactName', c.contact_name,
      'phone', c.phone_e164, 'city', c.city, 'state', c.state, 'tier', cc.tier
    ),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'designNo', i.design_no, 'imageUrl', d.image_url, 'qty', i.qty, 'note', i.line_note,
        'category', i.category_snapshot, 'style', i.style_snapshot, 'fabric', i.fabric_snapshot,
        'pcsPerSet', i.pcs_per_set_snapshot, 'dispatchedSets', coalesce(dl.dispatched_sets, 0),
        'squaredOff', (sq.order_id is not null), 'squaredReason', sq.reason, 'squaredAt', sq.squared_at,
        'squaredByName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = sq.squared_by)
      ) order by i.created_at, i.design_no)
      from public.order_items i
      join public.designs d on d.design_no = i.design_no
      left join public.dispatch_lines dl on dl.order_id = i.order_id and dl.design_no = i.design_no
      left join public.dispatch_squareoffs sq on sq.order_id = i.order_id and sq.design_no = i.design_no
      where i.order_id = o.id
        and ((select cf from cat) is null
             or upper(substring(i.design_no from '^[A-Za-z]+')) = (select cf from cat))
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'note', e.note, 'status', e.status, 'createdAt', e.created_at) order by e.created_at desc)
      from public.dispatch_events e where e.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  join public.customers c on c.id = o.customer_id
  left join public.customer_crm cc on cc.customer_id = c.id
  where o.id = p_order_id;
$$;
revoke all on function public.admin_dispatch_detail(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_dispatch_detail(uuid, text) to service_role;
