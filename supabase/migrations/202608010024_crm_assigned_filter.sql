-- 202608010024_crm_assigned_filter.sql
-- CRM list: filter by whether a customer HAS a salesperson assigned, independent
-- of who. Three states driven by p_filters->>'assigned':
--   (absent/'')  -> All        (no filter)
--   'assigned'   -> assigned_to is not null
--   'unassigned' -> assigned_to is null
--
-- MUST be server-side: the list is LIMITed (default 500, cap 2000) and there are
-- ~1,035 unassigned of 1,075. Filtering the returned page client-side would drop
-- assigned customers that sort past the fetched page — the same silent-wrong-answer
-- the tier sort (022) exists to prevent. This is a NEW parameter; the RPC had no
-- assignee filter before (the client's "assigned to me" toggle is a separate,
-- client-side control and is unaffected).
--
-- Whole function restated (house style). Only two lines change vs 022: the
-- `assigned` param in the params CTE and the assignee predicate in `filtered`.
-- The tier-first ORDER BY (022) is preserved verbatim in both the CTE and the agg.

create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')   as q,
      nullif(btrim(coalesce(p_filters ->> 'buyerType','')), '') as buyer_type,
      nullif(btrim(coalesce(p_filters ->> 'status','')), '')   as status,
      nullif(btrim(coalesce(p_filters ->> 'tier','')), '')     as tier,
      nullif(btrim(coalesce(p_filters ->> 'assigned','')), '')  as assigned,
      coalesce((p_filters ->> 'withOrders')::boolean, false)    as with_orders,
      coalesce((p_filters ->> 'callbacksDue')::boolean, false)  as callbacks_due,
      coalesce(nullif(btrim(coalesce(p_filters ->> 'sort','')), ''), 'recent') as sort,
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 500), 2000)) as lim
  ),
  scoped as (
    select c.id, c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.created_at, c.checked_in_at,
           cc.buyer_type, cc.tier,
           coalesce(cc.crm_status,'pending')    as crm_status,
           cc.assigned_to,
           coalesce(cc.has_reference,false)      as has_reference,
           coalesce(cc.token_agreed,false)       as token_agreed,
           cc.token_amount,
           regexp_replace(upper(coalesce(c.company_name,'')), '[^A-Z0-9]', '', 'g') as name_key,
           lc.called_at as last_call_at, lc.followup_at as followup_at,
           (lc.followup_at is not null and lc.followup_at <= now()) as followup_due,
           (select count(*) from public.customer_calls cl where cl.customer_id = c.id) as call_count,
           (select count(*) from public.order_items oi join public.orders o on o.id = oi.order_id where o.customer_id = c.id) as order_line_count
    from public.customers c
    left join public.customer_crm cc on cc.customer_id = c.id
    left join lateral (
      select cl.called_at, cl.followup_at from public.customer_calls cl
      where cl.customer_id = c.id order by cl.called_at desc limit 1
    ) lc on true, params p
    where c.active and c.exhibition_id = p.exhibition_id
  ),
  dupes as (
    select name_key, phone_e164, id,
           count(*) over (partition by name_key)  as name_n,
           count(*) over (partition by phone_e164) as phone_n
    from scoped
  ),
  filtered as (
    select s.* from scoped s, params p
    where (p.buyer_type is null
           or (p.buyer_type = 'unscreened' and s.buyer_type is null)
           or (p.buyer_type in ('new','regular') and s.buyer_type = p.buyer_type))
      and (p.status is null or s.crm_status = p.status)
      and (p.tier is null or s.tier = p.tier)
      and (p.assigned is null
           or (p.assigned = 'assigned'   and s.assigned_to is not null)
           or (p.assigned = 'unassigned' and s.assigned_to is null))
      and (not p.with_orders or s.order_line_count > 0)
      and (not p.callbacks_due or s.followup_due)
      and (p.q is null
           or s.company_name ilike '%'||p.q||'%'
           or s.contact_name ilike '%'||p.q||'%'
           or s.phone_e164   ilike '%'||p.q||'%'
           or s.city         ilike '%'||p.q||'%')
    order by
      case when p.sort = 'queue'    then (s.last_call_at is not null) end asc,
      case when p.sort = 'queue'    then s.last_call_at end asc nulls first,
      case when p.sort = 'callback' then s.followup_at end asc nulls last,
      case s.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      s.created_at desc
    limit (select lim from params)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', f.id, 'companyName', f.company_name, 'contactName', f.contact_name,
      'phone', f.phone_e164, 'city', f.city, 'state', f.state,
      'buyerType', f.buyer_type, 'tier', f.tier, 'crmStatus', f.crm_status,
      'assignedTo', f.assigned_to, 'assignedName', sp.staff_name,
      'hasReference', f.has_reference, 'tokenAgreed', f.token_agreed, 'tokenAmount', f.token_amount,
      'checkedInAt', f.checked_in_at,
      'referenceCount', (select count(*) from public.customer_references r where r.customer_id = f.id),
      'callCount', f.call_count, 'lastCallAt', f.last_call_at,
      'followupAt', f.followup_at, 'followupDue', f.followup_due,
      'orderLineCount', f.order_line_count,
      'dupName', coalesce((select d.name_n from dupes d where d.id = f.id), 1) > 1,
      'dupPhone', coalesce((select d.phone_n from dupes d where d.id = f.id), 1) > 1
    ) order by
      case when p.sort = 'queue'    then (f.last_call_at is not null) end asc,
      case when p.sort = 'queue'    then f.last_call_at end asc nulls first,
      case when p.sort = 'callback' then f.followup_at end asc nulls last,
      case f.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      f.created_at desc
  ), '[]'::jsonb)
  from filtered f
  left join public.staff_profiles sp on sp.auth_user_id = f.assigned_to, params p;
$function$;

revoke all on function public.crm_list_customers(jsonb) from public, anon, authenticated;
grant execute on function public.crm_list_customers(jsonb) to service_role;
