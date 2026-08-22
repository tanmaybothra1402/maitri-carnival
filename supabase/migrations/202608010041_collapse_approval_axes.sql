-- 202608010041_collapse_approval_axes.sql
--
-- Collapse TWO approval systems into one. reference_standing (0 rows) and the reference
-- verdict two-step (all 3 rows pending, 0 poc/notes) were never used and duplicated the
-- crm_status that actually gates dispatch.
--   * DROP customer_crm.reference_standing + its setter crm_set_reference_standing.
--   * customer_references: verdict -> spoken_to boolean (+ spoken_at/spoken_by); poc_name +
--     notes KEPT. verdict='approved' -> spoken_to=true (none today). crm_verify_reference ->
--     crm_set_reference_spoken.
--   * admin_dispatch_orders returns ONE derived dispatchFlag (SQL, not client-combined):
--     regular->none, unscreened->grey, new+agreed->none, new+pending/on_hold->warn,
--     new+rejected->reject. referenceStanding/refRejected/refRejectReason removed. Button
--     stays enabled (warn, never block).
--   * crm_list_customers/crm_customer_detail drop referenceStanding/refRejected/refPending/
--     the refStanding filter; detail returns spokenTo per reference.
-- DDL runs before the create-or-replace so drops + new bodies land in one transaction.

alter table public.customer_crm drop column if exists reference_standing;

alter table public.customer_references
  add column if not exists spoken_to boolean not null default false,
  add column if not exists spoken_at timestamptz,
  add column if not exists spoken_by uuid;
update public.customer_references
  set spoken_to = true, spoken_at = verified_at, spoken_by = verified_by
  where verdict = 'approved';
alter table public.customer_references drop column if exists verdict;
alter table public.customer_references drop column if exists verified_by;
alter table public.customer_references drop column if exists verified_at;

drop function if exists public.crm_set_reference_standing(uuid,text,uuid);
drop function if exists public.crm_verify_reference(uuid,text,text,text,uuid);

create or replace function public.crm_set_reference_spoken(p_reference_id uuid, p_spoken boolean, p_poc text, p_notes text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_customer uuid;
begin
  update public.customer_references
    set spoken_to = coalesce(p_spoken,false),
        spoken_at = case when coalesce(p_spoken,false) then now() else null end,
        spoken_by = case when coalesce(p_spoken,false) then p_actor else null end,
        poc_name  = nullif(btrim(p_poc),''),
        notes     = nullif(btrim(p_notes),'')
    where id = p_reference_id
    returning customer_id into v_customer;
  if v_customer is null then raise exception 'REFERENCE_NOT_FOUND'; end if;
  insert into public.customer_crm_log(customer_id, actor_id, field, new_value)
    values (v_customer, p_actor, 'reference_spoken', case when coalesce(p_spoken,false) then 'spoke to reference' else 'not spoken' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_set_reference_spoken(uuid,boolean,text,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_set_reference_spoken(uuid,boolean,text,text,uuid) to service_role;

-- crm_add_reference: no verdict (spoken_to defaults false)
create or replace function public.crm_add_reference(p_customer_id uuid, p_reference_text text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_name text := btrim(coalesce(p_reference_text,'')); v_company uuid; v_key text;
begin
  if v_name = '' then raise exception 'EMPTY_REFERENCE'; end if;
  v_key := regexp_replace(upper(v_name),'[^A-Z0-9]','','g');
  select id into v_company from public.reference_companies where name_key = v_key;
  if v_company is null then
    insert into public.reference_companies(name, created_by) values (v_name, p_actor) on conflict (name_key) do nothing returning id into v_company;
    if v_company is null then select id into v_company from public.reference_companies where name_key = v_key; end if;
  end if;
  insert into public.customer_references(customer_id, reference_text, company_id, created_by)
    values (p_customer_id, v_name, v_company, p_actor);
  insert into public.customer_crm(customer_id, has_reference, crm_updated_at, crm_updated_by)
    values (p_customer_id, true, now(), p_actor)
    on conflict (customer_id) do update set has_reference=true, crm_updated_at=now(), crm_updated_by=p_actor;
  return jsonb_build_object('ok', true, 'companyId', v_company);
end $$;
revoke all on function public.crm_add_reference(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_add_reference(uuid,text,uuid) to service_role;

-- admin_dispatch_orders: single derived dispatchFlag
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
           cc.tier, cc.buyer_type, coalesce(cc.crm_status,'pending') as crm_status,
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
        'dispatchFlag', case
          when pg.buyer_type = 'regular' then 'none'
          when pg.buyer_type is null then 'unscreened'
          when pg.buyer_type = 'new' and pg.crm_status = 'agreed' then 'none'
          when pg.buyer_type = 'new' and pg.crm_status in ('pending','on_hold') then 'warn'
          when pg.buyer_type = 'new' and pg.crm_status = 'rejected' then 'reject'
          else 'none'
        end,
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

-- crm_customer_detail: spokenTo per reference
create or replace function public.crm_customer_detail(p_customer_id uuid)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', c.id, 'companyName', c.company_name, 'contactName', c.contact_name,
    'phone', c.phone_e164, 'city', c.city, 'state', c.state, 'gstin', c.gstin,
    'buyerType', cc.buyer_type, 'tier', cc.tier,
    'crmStatus', coalesce(cc.crm_status,'pending'),
    'statusReason', cc.status_reason,
    'assignedTo', cc.assigned_to,
    'assignedName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = cc.assigned_to),
    'hasReference', coalesce(cc.has_reference,false),
    'tokenAgreed', coalesce(cc.token_agreed,false),
    'tokenAmount', cc.token_amount,
    'crmUpdatedAt', cc.crm_updated_at,
    'agentId', cc.agent_id,
    'agentName', (select a.name from public.agents a where a.id = cc.agent_id),
    'agentAnswered', (cc.agent_id is null and (nullif(btrim(c.agent),'') is not null or exists(select 1 from public.agent_remap_log l where l.customer_id = c.id and nullif(btrim(l.old_agent),'') is not null))),
    'payMethod', cc.pay_method, 'creditDays', cc.credit_days, 'payNotes', cc.pay_notes,
    'categoriesAuto', coalesce((
      select array_agg(distinct pfx order by pfx) from (
        select upper(substring(i.design_no from '^[A-Za-z]+')) pfx
        from public.order_items i join public.orders o on o.id = i.order_id
        where o.customer_id = c.id
      ) q where pfx in ('MR','KT','NRK','MU','BS')
    ), array[]::text[]),
    'categoriesManual', coalesce((
      select array_agg(ci.category order by ci.category)
      from public.customer_category_interest ci where ci.customer_id = c.id
    ), array[]::text[]),
    'hasDispatchHistory', exists (
      select 1 from public.orders o
      join public.dispatch_lines dl on dl.order_id = o.id and dl.dispatched_sets > 0
      where o.customer_id = c.id
    ),
    'calls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cl.id, 'calledAt', cl.called_at, 'calledBy', cl.called_by,
        'calledByName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = cl.called_by),
        'outcome', cl.outcome, 'notes', cl.notes, 'statusAfter', cl.status_after, 'followupAt', cl.followup_at
      ) order by cl.called_at desc)
      from public.customer_calls cl where cl.customer_id = c.id
    ), '[]'::jsonb),
    'references', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'text', r.reference_text,
        'companyId', r.company_id, 'companyName', coalesce(rc.name, r.reference_text),
        'pocName', r.poc_name, 'notes', r.notes, 'spokenTo', coalesce(r.spoken_to,false),
        'spokenBy', r.spoken_by,
        'spokenByName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = r.spoken_by),
        'spokenAt', r.spoken_at, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from public.customer_references r
      left join public.reference_companies rc on rc.id = r.company_id
      where r.customer_id = c.id
    ), '[]'::jsonb)
  )
  from public.customers c
  left join public.customer_crm cc on cc.customer_id = c.id
  where c.id = p_customer_id;
$function$;
revoke all on function public.crm_customer_detail(uuid) from public, anon, authenticated;
grant execute on function public.crm_customer_detail(uuid) to service_role;

-- crm_list_customers: reference-standing removed
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
           cc.assigned_to, cc.agent_id,
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
          'agentAnswered', (f.agent_id is null and (exists(select 1 from public.customers cu where cu.id = f.id and nullif(btrim(cu.agent),'') is not null) or exists(select 1 from public.agent_remap_log l where l.customer_id = f.id and nullif(btrim(l.old_agent),'') is not null))),
          'hasReference', f.has_reference, 'tokenAgreed', f.token_agreed, 'tokenAmount', f.token_amount,
          'checkedInAt', f.checked_in_at,
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
