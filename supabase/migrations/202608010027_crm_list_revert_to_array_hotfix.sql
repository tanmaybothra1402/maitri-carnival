-- 202608010027_crm_list_revert_to_array_hotfix.sql
--
-- HOTFIX / REVERT. 026 changed crm_list_customers to return an OBJECT
-- { customers, assigneeCounts, unassignedCount, totalCount } for the salesperson
-- picker counts, but its matched admin-api Edge (which unwraps that object) could
-- NOT be deployed in the same session — the Supabase CLI access token was
-- unavailable. The LIVE Edge still does `customers: data ?? []`, so an object shape
-- makes it hand the whole object to the client and the CRM list throws.
--
-- This restores the 025 ARRAY shape verbatim so the live Edge + live HTML work
-- again. The counts feature ships as a coordinated set once the Edge can be
-- deployed: a shape-TOLERANT admin-api (already staged on disk) + re-applying the
-- object shape. No behaviour change for staff vs 025.
create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')   as q,
      case when nullif(btrim(coalesce(p_filters ->> 'buyerType','')),'') in ('unscreened','new','regular')
           then btrim(p_filters ->> 'buyerType') end            as buyer_type,
      case when nullif(btrim(coalesce(p_filters ->> 'status','')),'') in ('pending','on_hold','agreed','rejected')
           then btrim(p_filters ->> 'status') end               as status,
      case when nullif(btrim(coalesce(p_filters ->> 'tier','')),'') in ('A','B','C')
           then btrim(p_filters ->> 'tier') end                 as tier,
      case when nullif(btrim(coalesce(p_filters ->> 'assigned','')),'') in ('assigned','unassigned')
           then btrim(p_filters ->> 'assigned') end             as assigned,
      case when nullif(btrim(coalesce(p_filters ->> 'assignedTo','')),'') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then (btrim(p_filters ->> 'assignedTo'))::uuid end    as assigned_to_id,
      coalesce(lower(nullif(btrim(p_filters ->> 'withOrders'),''))   in ('true','t','1','yes','on'), false) as with_orders,
      coalesce(lower(nullif(btrim(p_filters ->> 'callbacksDue'),'')) in ('true','t','1','yes','on'), false) as callbacks_due,
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
      and (p.assigned_to_id is null or s.assigned_to = p.assigned_to_id)
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
