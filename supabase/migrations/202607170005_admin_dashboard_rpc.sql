-- Server-side dashboard aggregation. Keeps the admin dashboard fast at scale
-- (hundreds of customers, thousands of order items) by computing KPIs, the
-- selected breakdown (top 100) and a page of orders in SQL. Admin-gated.

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
  if p_breakdown not in ('firm','category','fabric','color','designNo','companyName','state','city') then
    p_breakdown := 'firm';
  end if;

  drop table if exists _f;
  create temporary table _f on commit drop as
  select
    o.id as order_id, o.firm, o.status, o.updated_at,
    o.customer_id,
    i.design_no, i.qty,
    coalesce(nullif(btrim(i.category_snapshot),''),'—') as category,
    coalesce(nullif(btrim(i.fabric_snapshot),''),'—') as fabric,
    coalesce(nullif(btrim(i.color_snapshot),''),'—') as color,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.state),''),'—') as state,
    coalesce(nullif(btrim(c.city),''),'—') as city,
    c.agent
  from public.order_items i
  join public.orders o on o.id = i.order_id
  join public.customers c on c.id = o.customer_id
  where
    (not (p_filters ? 'firm')       or o.firm = any(select jsonb_array_elements_text(p_filters->'firm')))
    and (not (p_filters ? 'state')  or coalesce(nullif(btrim(c.state),''),'—') = any(select jsonb_array_elements_text(p_filters->'state')))
    and (not (p_filters ? 'city')   or coalesce(nullif(btrim(c.city),''),'—') = any(select jsonb_array_elements_text(p_filters->'city')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'category')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'fabric')))
    and (not (p_filters ? 'color')  or coalesce(nullif(btrim(i.color_snapshot),''),'—') = any(select jsonb_array_elements_text(p_filters->'color')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters->'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters->'companyName')))
    and (
      btrim(coalesce(p_search,'')) = '' or
      c.company_name ilike v_search or c.contact_name ilike v_search or
      c.phone_e164 ilike v_search or i.design_no ilike v_search
    );

  -- KPIs
  select jsonb_build_object(
    'totalSets', coalesce(sum(qty),0),
    'customers', count(distinct customer_id),
    'orders', count(distinct order_id),
    'designs', count(distinct design_no),
    'maitriSets', coalesce(sum(qty) filter (where firm='Maitri'),0),
    'niharikaSets', coalesce(sum(qty) filter (where firm='Niharika'),0)
  ) into v_kpis from _f;

  -- Breakdown (top 100) for the requested dimension
  execute format($q$
    select coalesce(jsonb_agg(rec order by (rec->>'sets')::int desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'label', %1$s,
        'sets', sum(qty),
        'designs', count(distinct design_no),
        'customers', count(distinct customer_id)
      ) as rec
      from _f group by %1$s order by sum(qty) desc limit 100
    ) s
  $q$, case p_breakdown
        when 'designNo' then 'design_no'
        when 'companyName' then 'company_name'
        else quote_ident(p_breakdown) end)
  into v_breakdown;

  -- Orders page
  select count(*) into v_total from (select distinct order_id from _f) t;

  select coalesce(jsonb_agg(o), '[]'::jsonb) into v_orders from (
    select jsonb_build_object(
      'orderId', order_id, 'firm', min(firm), 'status', min(status),
      'companyName', min(company_name), 'contactName', min(contact_name),
      'phone', min(phone_e164), 'city', min(city), 'state', min(state), 'agent', min(agent),
      'customerId', min(customer_id::text),
      'sets', sum(qty), 'designs', count(distinct design_no),
      'updatedAt', max(updated_at)
    ) as o
    from _f group by order_id
    order by max(updated_at) desc
    limit greatest(1, least(200, coalesce(p_limit,50))) offset greatest(0, coalesce(p_offset,0))
  ) t;

  select coalesce(jsonb_agg(distinct state order by state), '[]'::jsonb)
  into v_states from (select coalesce(nullif(btrim(state),''),'—') as state from public.customers where btrim(coalesce(state,'')) <> '') s;

  return jsonb_build_object(
    'kpis', v_kpis,
    'breakdown', v_breakdown,
    'orders', v_orders,
    'totalOrders', v_total,
    'states', v_states,
    'generatedAt', now()
  );
end;
$$;

revoke all on function public.admin_dashboard(jsonb, text, text, integer, integer) from public, anon;
grant execute on function public.admin_dashboard(jsonb, text, text, integer, integer) to authenticated;
