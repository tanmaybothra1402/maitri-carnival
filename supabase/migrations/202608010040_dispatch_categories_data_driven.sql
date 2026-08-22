-- 202608010040_dispatch_categories_data_driven.sql
--
-- Make the dispatch category vocabulary DATA-DRIVEN, deleting the hardcoded 5-prefix
-- list from 2 of its 3 C3 sites (the Edge whitelist and the HTML chips; this RPC keeps
-- the single derivation). A new department at the next exhibition (say SR) now appears
-- as a chip automatically instead of silently breaking the filter.
--
-- Two changes vs migration 039:
--   1. category param: no longer whitelisted to the 5. Any value is accepted (uppercased);
--      an unknown prefix matches zero lines so `cat.designs > 0` yields NO orders — category
--      fails CLOSED (deliberately, unlike dispatchStatus's fail-open): showing all 486 under
--      a chip labelled "SR" would be a lie, so the truthful answer is nothing — and the UI
--      renders a reason (D1). dispatchStatus stays fail-open (a blank dispatch screen reading
--      as "no work" is the danger there; an unknown status can't mislabel the result).
--   2. a `categories` array in the response — distinct prefixes in the exhibition's order
--      lines, computed independent of every active filter (the circularity guard: filtering
--      to MR must not shrink the vocabulary to [MR]).
-- Whole function restated (house style); the ONLY changes are those two.

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
      nullif(upper(btrim(coalesce(p_filters ->> 'category',''))), '') as category,
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
    'total', (select count(*) from matched),
    -- Filter-INDEPENDENT vocabulary: the distinct design-number prefixes present in
    -- THIS exhibition's order LINES (not the catalogue — a deactivated catalogue typo
    -- like MRK never ordered stays out), scoped by exhibition ONLY, never by the active
    -- category/status/firm/search — so selecting a chip cannot collapse the list to itself.
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
revoke all on function public.admin_dispatch_orders(jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_orders(jsonb) to service_role;
