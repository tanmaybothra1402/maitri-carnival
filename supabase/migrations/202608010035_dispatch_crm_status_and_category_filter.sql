-- 202608010035_dispatch_crm_status_and_category_filter.sql
--
-- Checkpoint 3 (dispatch): customer approval status on the card + a category filter.
-- NO square-off here — square-off is the only thing that touches
-- recompute_dispatch_status, and it ships as its own migration so a dispatch-status
-- regression is attributable to one change. This migration does NOT alter
-- recompute_dispatch_status or any dispatch WRITE path; it only reads.
--
-- 3a. admin_dispatch_orders returns crm_status (buyer approval) per order. Warn,
--     never block — the client keeps the dispatch button enabled in every state.
--
-- 3b. Category filter = the design-number PREFIX (leading letters), the SAME
--     derivation the CRM uses (migrations 033/034): upper(substring(design_no from
--     '^[A-Za-z]+')), canonical 5 only (MR/KT/NRK/MU/BS). Deliberately NOT
--     order_items.category_snapshot, which has only four values and collapses MU and
--     NRK together as "Unstiched" — Tanmay wants them as separate departments, and
--     one category definition keeps dispatch and the CRM in agreement (C3).
--
--     The filter scopes LINES, not just which orders appear: an order with MR and MU
--     lines shows for both the MR and the MU person, and each sees only their own
--     lines. So the filter runs in TWO places, both here:
--       * admin_dispatch_orders — includes an order only if it has >=1 line of the
--         category (filtered BEFORE the limit — this list capped at 300 vs 2,149 once
--         and under-reported for days), and the displayed designs/sets/pieces and
--         dispatch status reflect the FILTERED lines, not the whole order.
--       * admin_dispatch_detail — returns only the category's lines (gets a new
--         p_category argument). admin_save_dispatch is unchanged and already touches
--         only the designs in its payload, so a filtered save cannot alter the other
--         category's dispatch_lines.

-- ── 3a + 3b: admin_dispatch_orders ───────────────────────────────────────────
-- Whole function restated. Preserves the {orders, total} shape, every existing key,
-- and the 022 tier-first ORDER BY (in both the paginated subquery and the agg).
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
        count(*) filter (where coalesce(dl.dispatched_sets,0) = 0)::int as pending,
        case
          when count(*) = 0 then null
          when count(*) filter (where coalesce(dl.dispatched_sets,0) > 0) = 0 then 'Pending'
          when count(*) filter (where coalesce(dl.dispatched_sets,0) >= oi.qty and coalesce(dl.dispatched_sets,0) > 0) >= count(*) then 'Completed'
          else 'Partial'
        end as status
      from public.order_items oi
      left join public.dispatch_lines dl on dl.order_id = oi.order_id and dl.design_no = oi.design_no
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

-- ── 3b: admin_dispatch_detail — scope the LINES to the category ───────────────
-- Signature changes (adds p_category), so drop the (uuid) overload first. Every
-- caller is in admin-api (getDispatch, saveDispatch) and is updated to pass p_category.
-- When p_category is one of the 5, the lines array contains ONLY that prefix's lines;
-- allDesigns still reports the whole order's design count so the UI can say "N of M".
drop function if exists public.admin_dispatch_detail(uuid);
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
        'pcsPerSet', i.pcs_per_set_snapshot, 'dispatchedSets', coalesce(dl.dispatched_sets, 0)
      ) order by i.created_at, i.design_no)
      from public.order_items i
      join public.designs d on d.design_no = i.design_no
      left join public.dispatch_lines dl on dl.order_id = i.order_id and dl.design_no = i.design_no
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
