-- 202608010042_dispatch_products_rpcs.sql
-- By-product dispatch, rebuilt as a list RPC + a per-design detail RPC — the DESIGN is the
-- unit, mirroring listDispatch/getDispatch (by-order). This removes the 300-ORDER cap that
-- made by-product show only the top 300 orders: measured against production, that cap hid
-- 2,897 of 6,481 by-product lines (45%), and every one of those hidden lines was still
-- un-shipped — none of the hidden work was already done. Pagination now happens on DESIGNS
-- (what the screen shows), and a product's buyers are fetched only when it is expanded.
--
-- ALL filtering is in SQL before any LIMIT: exhibition, firm, search, category, and the
-- LINE-LEVEL dispatch status. Line status is per (order, design) line:
--   Closed    = squared off                       (checked FIRST — a squared line is Closed
--                                                   even with nothing dispatched, never Pending)
--   Pending   = dispatched = 0
--   Partial   = 0 < dispatched < ordered
--   Completed = dispatched >= ordered
-- Default (no status chip) returns outstanding shippable work only (remaining > 0), which
-- excludes Completed and Closed. A status chip returns exactly its own set — Closed lines
-- are INCLUDED so the Closed chip works (the withLines path stripped them; this does not).
--
-- dispatchFlag is the SAME derivation as admin_dispatch_orders (C3): buyer_type + crm_status.
-- By-order (admin_dispatch_orders) is unchanged and keeps its order-level status meaning.

-- ── list: one row per design, paginated on designs, uncapped in orders ────────
create or replace function public.admin_dispatch_products(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  with params as (
    select
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      case when nullif(btrim(coalesce(p_filters ->> 'firm','')),'') in ('Maitri','Niharika')
           then btrim(p_filters ->> 'firm') end as firm,
      case when nullif(btrim(coalesce(p_filters ->> 'dispatchStatus','')),'') in ('Pending','Partial','Completed','Closed')
           then btrim(p_filters ->> 'dispatchStatus') end as dispatch_status,
      nullif(upper(btrim(coalesce(p_filters ->> 'category',''))), '') as category,
      nullif(btrim(coalesce(p_filters ->> 'search','')), '') as q,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 100), 500)) as lim,
      greatest(0, coalesce((p_filters ->> 'offset')::int, 0)) as off
  ),
  filtered as (
    select
      oi.design_no,
      case when sq.order_id is not null then 0
           else greatest(0, coalesce(oi.qty,0) - coalesce(dl.dispatched_sets,0)) end as remaining,
      case
        when cc.buyer_type = 'regular' then 'none'
        when cc.buyer_type is null then 'unscreened'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') = 'agreed' then 'none'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') in ('pending','on_hold') then 'warn'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') = 'rejected' then 'reject'
        else 'none'
      end as dispatch_flag
    from public.orders o
    join public.customers c on c.id = o.customer_id
    left join public.customer_crm cc on cc.customer_id = o.customer_id
    join public.order_items oi on oi.order_id = o.id
    left join public.dispatch_lines dl on dl.order_id = oi.order_id and dl.design_no = oi.design_no
    left join public.dispatch_squareoffs sq on sq.order_id = oi.order_id and sq.design_no = oi.design_no
    cross join params p
    where o.exhibition_id = p.exhibition_id
      and o.total_designs > 0
      and (p.firm is null or o.firm = p.firm)
      and (p.category is null or upper(substring(oi.design_no from '^[A-Za-z]+')) = p.category)
      and (p.q is null
           or c.company_name ilike '%'||p.q||'%'
           or c.contact_name ilike '%'||p.q||'%'
           or c.phone_e164   ilike '%'||p.q||'%')
      -- LINE-LEVEL status filter, applied before any grouping or limit.
      and case
        when p.dispatch_status = 'Closed'    then sq.order_id is not null
        when p.dispatch_status = 'Pending'   then sq.order_id is null and coalesce(dl.dispatched_sets,0) = 0
        when p.dispatch_status = 'Partial'   then sq.order_id is null and coalesce(dl.dispatched_sets,0) > 0 and coalesce(dl.dispatched_sets,0) < coalesce(oi.qty,0)
        when p.dispatch_status = 'Completed' then sq.order_id is null and coalesce(dl.dispatched_sets,0) >= coalesce(oi.qty,0) and coalesce(oi.qty,0) > 0
        else sq.order_id is null and greatest(0, coalesce(oi.qty,0) - coalesce(dl.dispatched_sets,0)) > 0
      end
  ),
  by_design as (
    select design_no,
           count(*) as buyers,
           sum(remaining) as remaining,
           count(*) filter (where dispatch_flag in ('warn','reject')) as needs_check
    from filtered
    group by design_no
  )
  select jsonb_build_object(
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'designNo', design_no,
        'buyers', buyers,
        'remaining', remaining,
        'needsCheck', needs_check
      ) order by remaining desc, design_no asc)
      from (
        select * from by_design
        order by remaining desc, design_no asc
        limit (select lim from params) offset (select off from params)
      ) pg
    ), '[]'::jsonb),
    'total', (select count(*) from by_design),
    -- Data-driven category vocabulary — filter-independent (same shape as admin_dispatch_orders).
    'categories', coalesce((
      select jsonb_agg(distinct pfx order by pfx) from (
        select upper(substring(oi.design_no from '^[A-Za-z]+')) as pfx
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        cross join params p
        where o.exhibition_id = p.exhibition_id and o.total_designs > 0
          and nullif(upper(substring(oi.design_no from '^[A-Za-z]+')),'') is not null
      ) q
    ), '[]'::jsonb)
  );
$function$;
revoke all on function public.admin_dispatch_products(jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_products(jsonb) to service_role;

-- ── detail: every buyer for ONE design, uncapped ─────────────────────────────
create or replace function public.admin_dispatch_product_buyers(p_design_no text, p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  with params as (
    select
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      case when nullif(btrim(coalesce(p_filters ->> 'firm','')),'') in ('Maitri','Niharika')
           then btrim(p_filters ->> 'firm') end as firm,
      case when nullif(btrim(coalesce(p_filters ->> 'dispatchStatus','')),'') in ('Pending','Partial','Completed','Closed')
           then btrim(p_filters ->> 'dispatchStatus') end as dispatch_status,
      nullif(upper(btrim(coalesce(p_filters ->> 'category',''))), '') as category,
      nullif(btrim(coalesce(p_filters ->> 'search','')), '') as q
  ),
  filtered as (
    select
      o.id as order_id,
      coalesce(nullif(c.company_name,''), nullif(c.contact_name,''), 'Unnamed party') as company,
      cc.tier,
      concat_ws(', ', nullif(c.city,''), nullif(c.state,'')) as city,
      o.firm,
      dl.dispatched_at,
      coalesce(oi.qty,0) as ordered,
      coalesce(dl.dispatched_sets,0) as dispatched,
      case when sq.order_id is not null then 0
           else greatest(0, coalesce(oi.qty,0) - coalesce(dl.dispatched_sets,0)) end as remaining,
      coalesce(oi.pcs_per_set_snapshot,1) as pcs_per_set,
      (sq.order_id is not null) as squared_off,
      case
        when cc.buyer_type = 'regular' then 'none'
        when cc.buyer_type is null then 'unscreened'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') = 'agreed' then 'none'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') in ('pending','on_hold') then 'warn'
        when cc.buyer_type = 'new' and coalesce(cc.crm_status,'pending') = 'rejected' then 'reject'
        else 'none'
      end as dispatch_flag
    from public.orders o
    join public.customers c on c.id = o.customer_id
    left join public.customer_crm cc on cc.customer_id = o.customer_id
    join public.order_items oi on oi.order_id = o.id
    left join public.dispatch_lines dl on dl.order_id = oi.order_id and dl.design_no = oi.design_no
    left join public.dispatch_squareoffs sq on sq.order_id = oi.order_id and sq.design_no = oi.design_no
    cross join params p
    where o.exhibition_id = p.exhibition_id
      and o.total_designs > 0
      and oi.design_no = p_design_no
      and (p.firm is null or o.firm = p.firm)
      and (p.category is null or upper(substring(oi.design_no from '^[A-Za-z]+')) = p.category)
      and (p.q is null
           or c.company_name ilike '%'||p.q||'%'
           or c.contact_name ilike '%'||p.q||'%'
           or c.phone_e164   ilike '%'||p.q||'%')
      and case
        when p.dispatch_status = 'Closed'    then sq.order_id is not null
        when p.dispatch_status = 'Pending'   then sq.order_id is null and coalesce(dl.dispatched_sets,0) = 0
        when p.dispatch_status = 'Partial'   then sq.order_id is null and coalesce(dl.dispatched_sets,0) > 0 and coalesce(dl.dispatched_sets,0) < coalesce(oi.qty,0)
        when p.dispatch_status = 'Completed' then sq.order_id is null and coalesce(dl.dispatched_sets,0) >= coalesce(oi.qty,0) and coalesce(oi.qty,0) > 0
        else sq.order_id is null and greatest(0, coalesce(oi.qty,0) - coalesce(dl.dispatched_sets,0)) > 0
      end
  )
  select jsonb_build_object(
    'designNo', p_design_no,
    'buyers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'orderId', order_id,
        'company', company,
        'tier', tier,
        'city', city,
        'firm', firm,
        'dispatchedAt', dispatched_at,
        'ordered', ordered,
        'dispatched', dispatched,
        'remaining', remaining,
        'pcsPerSet', pcs_per_set,
        'squaredOff', squared_off,
        'dispatchFlag', dispatch_flag
      ) order by remaining desc, company asc)
      from filtered
    ), '[]'::jsonb)
  );
$function$;
revoke all on function public.admin_dispatch_product_buyers(text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_product_buyers(text, jsonb) to service_role;
