-- 202608010039_dispatch_status_closed_filter.sql
--
-- Defect fix: admin_dispatch_orders whitelisted dispatchStatus as (Pending,Partial,
-- Completed) — but migration 038 made recompute_dispatch_status PRODUCE a fourth value,
-- 'Closed'. A 'Closed' filter fell through the whitelist to NULL and the fail-open
-- branch returned EVERY order (486), silently — the same under-report shape as the
-- 300-row cap. Harmless only while zero orders are Closed. Add 'Closed' to the
-- whitelist so the real status can be selected.
--
-- Fail-open is DELIBERATELY kept (migration 028): an unrecognised value still returns
-- all orders rather than a blank screen (D1 — an empty dispatch list reads as "no
-- work"). The defect was never fail-open, it was an incomplete whitelist; now every
-- status the system can produce is listed, so the only way to reach fail-open is a
-- genuinely malformed value (e.g. 'Nonsense'), which the sanitising Edge can't send.
-- The Edge listDispatch ALSO whitelists this value and ships the matching 'Closed'
-- (admin-api v48) — both layers must list it. Whole function restated (house style);
-- the ONLY change vs migration 038 is 'Closed' added to the dispatchStatus case.
-- NOTE (separate task): the category whitelist has the same shape and CAN grow from
-- DATA (a new design prefix) — tracked for a data-driven-chips decision, not here.

create or replace function public.admin_dispatch_orders(p_filters jsonb default '{}'::jsonb)
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
