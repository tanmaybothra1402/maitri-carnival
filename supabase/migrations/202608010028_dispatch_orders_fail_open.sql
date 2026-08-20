-- 202608010028_dispatch_orders_fail_open.sql
--
-- BUG 3: admin_dispatch_orders failed CLOSED on an unrecognised filter value —
-- firm='GARBAGE' -> 0 rows, dispatchStatus='GARBAGE' -> 0 rows — the same
-- blank-screen failure fixed across crm_list_customers in migration 025, never
-- applied here (guardrail D1: an empty result must show a reason, not nothing).
--
-- The two enum filters normalise to NULL when unrecognised, so the existing
-- `param is null -> no filter` branches treat a stray value as "show all". search
-- stays free-text (a no-match empty is correct); exhibitionId/limit are typed casts.
--
-- Defense-in-depth: the deployed admin-api already sanitises firm/dispatchStatus to
-- valid-or-null before calling this, so the bad value is not reachable through the
-- current UI — but a future caller (or a direct call) must not blank the screen.
--
-- OUTPUT SHAPE UNCHANGED (still snake_case) so the deployed Edge, which maps those
-- keys to camelCase, keeps working. The separate camelCase alignment (BUG 1) ships
-- WITH its matched Edge change, since changing the keys here would break the live
-- Edge. Whole function restated (house style); the 022 tier-first ORDER BY is
-- preserved verbatim in both the CTE and the jsonb_agg.

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
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 300), 500)) as lim
  ),
  ranked as (
    select
      o.id, o.customer_id, o.firm, o.status, o.dispatch_status,
      o.total_designs, o.total_sets, o.total_pieces, o.updated_at,
      c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.agent,
      cc.tier
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
    order by
      case cc.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      o.updated_at desc
    limit (select lim from params)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', r.id, 'customer_id', r.customer_id, 'firm', r.firm, 'status', r.status,
      'dispatch_status', r.dispatch_status, 'total_designs', r.total_designs,
      'total_sets', r.total_sets, 'total_pieces', r.total_pieces, 'updated_at', r.updated_at,
      'company_name', r.company_name, 'contact_name', r.contact_name, 'phone_e164', r.phone_e164,
      'city', r.city, 'state', r.state, 'agent', r.agent, 'tier', r.tier
    ) order by
      case r.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      r.updated_at desc
  ), '[]'::jsonb)
  from ranked r;
$function$;

revoke all on function public.admin_dispatch_orders(jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_orders(jsonb) to service_role;
