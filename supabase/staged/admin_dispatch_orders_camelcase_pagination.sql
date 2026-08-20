-- STAGED — do NOT apply before the matched admin-api Edge is deployed. See README.md.
--
-- BUG 1: admin_dispatch_orders returns camelCase (orderId, companyName, dispatchStatus,
--        designs, ...), matching every other RPC and the client's own vocabulary, so the
--        Edge mapper stops translating snake_case.
-- BUG 4: adds an `offset` param and returns { orders: [...page...], total: <full count> }
--        so the client can page past the 300 cap (486 orders with lines → the last 186
--        were unreachable) and show a true total, not the page size.
--
-- RETURN SHAPE CHANGE (array -> object) AND KEY CHANGE (snake -> camel): both are read by
-- the Edge, so the Edge must ship first (it is made tolerant of the old array/snake shape,
-- so either deploy order is safe). The 022 tier-first ORDER BY is preserved verbatim in
-- both the page subquery and the jsonb_agg. Proven under a temp name against prod:
-- total=486, camelCase keys, offset:300 returns the previously-invisible 186.
--
-- When applying: move this file into supabase/migrations/ as the next free number.

create or replace function public.admin_dispatch_orders(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with params as (
    select
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      case when nullif(btrim(coalesce(p_filters ->> 'firm','')),'') in ('Maitri','Niharika')
           then btrim(p_filters ->> 'firm') end as firm,
      case when nullif(btrim(coalesce(p_filters ->> 'dispatchStatus','')),'') in ('Pending','Partial','Completed')
           then btrim(p_filters ->> 'dispatchStatus') end as dispatch_status,
      nullif(btrim(coalesce(p_filters ->> 'search','')), '') as q,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 300), 500)) as lim,
      greatest(0, coalesce((p_filters ->> 'offset')::int, 0)) as off
  ),
  matched as (
    select o.id, o.customer_id, o.firm, o.status, o.dispatch_status,
           o.total_designs, o.total_sets, o.total_pieces, o.updated_at,
           c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.agent, cc.tier
    from public.orders o
    join public.customers c on c.id = o.customer_id
    left join public.customer_crm cc on cc.customer_id = o.customer_id, params p
    where o.exhibition_id = p.exhibition_id
      and o.total_designs > 0
      and (p.firm is null or o.firm = p.firm)
      and (p.dispatch_status is null or o.dispatch_status = p.dispatch_status)
      and (p.q is null
           or c.company_name ilike '%'||p.q||'%'
           or c.contact_name ilike '%'||p.q||'%'
           or c.phone_e164   ilike '%'||p.q||'%')
  )
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'orderId', pg.id, 'customerId', pg.customer_id, 'firm', pg.firm, 'status', pg.status,
        'dispatchStatus', pg.dispatch_status, 'designs', pg.total_designs, 'sets', pg.total_sets,
        'pieces', pg.total_pieces, 'updatedAt', pg.updated_at, 'companyName', pg.company_name,
        'contactName', pg.contact_name, 'phone', pg.phone_e164, 'city', pg.city, 'state', pg.state,
        'agent', pg.agent, 'tier', pg.tier
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
