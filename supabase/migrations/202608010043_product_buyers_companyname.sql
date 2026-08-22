-- 202608010043_product_buyers_companyname.sql
-- Key-name alignment (CP2): admin_dispatch_product_buyers returned 'company' while its sibling
-- admin_dispatch_orders returns 'companyName' for the same field. Two endpoints in one feature
-- disagreeing on a key name is a silent-blank bug waiting — a client mapper reading companyName
-- gets undefined and renders an empty name with no error. Align the buyer payload to companyName.
-- ONLY change vs migration 042: the buyers jsonb key 'company' -> 'companyName'.
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
      coalesce(nullif(c.company_name,''), nullif(c.contact_name,''), 'Unnamed party') as company_name,
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
        'companyName', company_name,
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
      ) order by remaining desc, company_name asc)
      from filtered
    ), '[]'::jsonb)
  );
$function$;
revoke all on function public.admin_dispatch_product_buyers(text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_product_buyers(text, jsonb) to service_role;
