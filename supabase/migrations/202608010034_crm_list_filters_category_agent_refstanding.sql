-- 202608010034_crm_list_filters_category_agent_refstanding.sql
--
-- Make the new CRM data FINDABLE in the list. Adds three filters to crm_list_customers,
-- ALL applied in SQL inside the same WHERE as the existing filters, BEFORE the LIMIT —
-- the list caps at 500 of 875, so a post-LIMIT filter would silently under-report (the
-- 300-row dispatch cap failure). Plus agentName + refPending per row.
--   category    MR/KT/NRK/MU/BS — matches derived (order prefix) OR manual chips.
--   agentId     uuid           — customer_crm.agent_id.
--   refStanding pending/approved/rejected/none — on the customer_references VERDICTS:
--               pending  = has a reference row verdict='pending' (the call queue),
--               approved/rejected = has one with that verdict, none = has no references.
-- Whole function restated; the 022 tier-first ORDER BY is preserved verbatim; the
-- {customers, assigneeCounts, unassignedCount, totalCount} object shape and every
-- existing key are unchanged.

create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql stable security definer set search_path to 'public'
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
      case when nullif(btrim(coalesce(p_filters ->> 'category','')),'') in ('MR','KT','NRK','MU','BS')
           then btrim(p_filters ->> 'category') end             as category,
      case when nullif(btrim(coalesce(p_filters ->> 'agentId','')),'') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then (btrim(p_filters ->> 'agentId'))::uuid end       as agent_id,
      case when nullif(btrim(coalesce(p_filters ->> 'refStanding','')),'') in ('pending','approved','rejected','none')
           then btrim(p_filters ->> 'refStanding') end          as ref_standing,
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
           cc.assigned_to, cc.reference_standing, cc.agent_id,
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
      and (p.agent_id is null or s.agent_id = p.agent_id)
      and (p.category is null
           or exists (select 1 from public.order_items oi join public.orders o on o.id = oi.order_id
                      where o.customer_id = s.id and upper(substring(oi.design_no from '^[A-Za-z]+')) = p.category)
           or exists (select 1 from public.customer_category_interest ci
                      where ci.customer_id = s.id and ci.category = p.category))
      and (p.ref_standing is null
           or (p.ref_standing = 'pending'  and exists (select 1 from public.customer_references r where r.customer_id = s.id and r.verdict = 'pending'))
           or (p.ref_standing = 'approved' and exists (select 1 from public.customer_references r where r.customer_id = s.id and r.verdict = 'approved'))
           or (p.ref_standing = 'rejected' and exists (select 1 from public.customer_references r where r.customer_id = s.id and r.verdict = 'rejected'))
           or (p.ref_standing = 'none'     and not exists (select 1 from public.customer_references r where r.customer_id = s.id)))
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
  select jsonb_build_object(
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', f.id, 'companyName', f.company_name, 'contactName', f.contact_name,
          'phone', f.phone_e164, 'city', f.city, 'state', f.state,
          'buyerType', f.buyer_type, 'tier', f.tier, 'crmStatus', f.crm_status,
          'assignedTo', f.assigned_to, 'assignedName', sp.staff_name,
          'agentName', (select a.name from public.agents a where a.id = f.agent_id),
          'hasReference', f.has_reference, 'tokenAgreed', f.token_agreed, 'tokenAmount', f.token_amount,
          'checkedInAt', f.checked_in_at,
          'referenceStanding', f.reference_standing,
          'refRejected', exists(select 1 from public.customer_references r where r.customer_id = f.id and r.verdict = 'rejected'),
          'refPending',  exists(select 1 from public.customer_references r where r.customer_id = f.id and r.verdict = 'pending'),
          'categories', coalesce((
            select jsonb_agg(jsonb_build_object('c', cat, 'm', is_manual) order by cat)
            from (
              select cat, bool_and(src = 'manual') as is_manual
              from (
                select upper(substring(oi.design_no from '^[A-Za-z]+')) cat, 'auto' src
                  from public.order_items oi join public.orders o on o.id = oi.order_id where o.customer_id = f.id
                union all
                select ci.category, 'manual' from public.customer_category_interest ci where ci.customer_id = f.id
              ) u where cat in ('MR','KT','NRK','MU','BS') group by cat
            ) z
          ), '[]'::jsonb),
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
      )
      from filtered f
      left join public.staff_profiles sp on sp.auth_user_id = f.assigned_to, params p
    ), '[]'::jsonb),
    'assigneeCounts', coalesce((
      select jsonb_agg(jsonb_build_object('assignedTo', z.assigned_to, 'count', z.n) order by z.n desc, z.assigned_to)
      from (select assigned_to, count(*) n from scoped where assigned_to is not null group by assigned_to) z
    ), '[]'::jsonb),
    'unassignedCount', (select count(*) from scoped where assigned_to is null),
    'totalCount',      (select count(*) from scoped)
  );
$function$;
revoke all on function public.crm_list_customers(jsonb) from public, anon, authenticated;
grant execute on function public.crm_list_customers(jsonb) to service_role;
