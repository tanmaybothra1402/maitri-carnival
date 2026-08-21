-- 202608010033_crm_rpcs_references_agents_payment_categories.sql
--
-- RPC layer for the four CRM additions. All SECURITY DEFINER, search_path=public,
-- service-role only (revoke public/anon/authenticated). crm_list_customers and
-- admin_dispatch_orders are restated WHOLE; the 022 tier-first ORDER BY is preserved
-- verbatim in both. Category interest is DERIVED here (never stored): auto = the 5
-- canonical prefixes (MR/KT/NRK/MU/BS) from the customer's orders, manual-only chips
-- flagged. Reference standing + rejected flag are surfaced to dispatch (warn, never
-- block — the client keeps the button enabled).

-- ── crm_customer_detail: + agent, payment, standing, categories, ref verification ──
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
    'payMethod', cc.pay_method, 'creditDays', cc.credit_days, 'payNotes', cc.pay_notes,
    'referenceStanding', cc.reference_standing,
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
        'pocName', r.poc_name, 'notes', r.notes, 'verdict', coalesce(r.verdict,'pending'),
        'verifiedBy', r.verified_by,
        'verifiedByName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = r.verified_by),
        'verifiedAt', r.verified_at, 'createdAt', r.created_at
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

-- ── setters ───────────────────────────────────────────────────────────────────
create or replace function public.crm_set_payment(p_customer_id uuid, p_method text, p_credit_days integer, p_notes text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_m text := case when p_method in ('cash','cheque') then p_method else null end;
begin
  insert into public.customer_crm (customer_id, pay_method, credit_days, pay_notes, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_m, p_credit_days, nullif(btrim(p_notes),''), now(), p_actor)
  on conflict (customer_id) do update set pay_method=v_m, credit_days=p_credit_days, pay_notes=nullif(btrim(excluded.pay_notes),''), crm_updated_at=now(), crm_updated_by=p_actor;
  insert into public.customer_crm_log(customer_id, actor_id, field, new_value)
    values (p_customer_id, p_actor, 'payment', coalesce(v_m,'')||'/'||coalesce(p_credit_days::text,'')||'d');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_set_payment(uuid,text,integer,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_set_payment(uuid,text,integer,text,uuid) to service_role;

create or replace function public.crm_set_agent(p_customer_id uuid, p_agent_name text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_name text := btrim(coalesce(p_agent_name,'')); v_id uuid; v_key text;
begin
  if v_name = '' then
    insert into public.customer_crm (customer_id, agent_id, crm_updated_at, crm_updated_by)
      values (p_customer_id, null, now(), p_actor)
      on conflict (customer_id) do update set agent_id=null, crm_updated_at=now(), crm_updated_by=p_actor;
    update public.customers set agent='', updated_at=now() where id=p_customer_id;
  else
    v_key := regexp_replace(upper(v_name),'[^A-Z0-9]','','g');
    select id into v_id from public.agents where name_key = v_key;
    if v_id is null then
      insert into public.agents(name, created_by) values (v_name, p_actor) on conflict (name_key) do nothing returning id into v_id;
      if v_id is null then select id into v_id from public.agents where name_key = v_key; end if;
    end if;
    insert into public.customer_crm (customer_id, agent_id, crm_updated_at, crm_updated_by)
      values (p_customer_id, v_id, now(), p_actor)
      on conflict (customer_id) do update set agent_id=v_id, crm_updated_at=now(), crm_updated_by=p_actor;
    -- keep the buyer-visible free-text agent (dashboard reads it) in sync with the canonical name
    update public.customers set agent=(select name from public.agents where id=v_id), updated_at=now() where id=p_customer_id;
  end if;
  insert into public.customer_crm_log(customer_id, actor_id, field, new_value) values (p_customer_id, p_actor, 'agent', v_name);
  return jsonb_build_object('ok', true, 'agentId', v_id);
end $$;
revoke all on function public.crm_set_agent(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_set_agent(uuid,text,uuid) to service_role;

create or replace function public.crm_set_reference_standing(p_customer_id uuid, p_standing text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_s text := case when p_standing in ('approved','watch','rejected') then p_standing else null end;
begin
  insert into public.customer_crm (customer_id, reference_standing, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_s, now(), p_actor)
    on conflict (customer_id) do update set reference_standing=v_s, crm_updated_at=now(), crm_updated_by=p_actor;
  insert into public.customer_crm_log(customer_id, actor_id, field, new_value) values (p_customer_id, p_actor, 'reference_standing', coalesce(v_s,''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_set_reference_standing(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_set_reference_standing(uuid,text,uuid) to service_role;

create or replace function public.crm_add_category(p_customer_id uuid, p_category text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if p_category not in ('MR','KT','NRK','MU','BS') then raise exception 'INVALID_CATEGORY'; end if;
  insert into public.customer_category_interest(customer_id, category, added_by)
    values (p_customer_id, p_category, p_actor) on conflict (customer_id, category) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_add_category(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_add_category(uuid,text,uuid) to service_role;

create or replace function public.crm_remove_category(p_customer_id uuid, p_category text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  delete from public.customer_category_interest where customer_id=p_customer_id and category=p_category;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_remove_category(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_remove_category(uuid,text,uuid) to service_role;

create or replace function public.crm_verify_reference(p_reference_id uuid, p_poc text, p_notes text, p_verdict text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  update public.customer_references set
    poc_name = nullif(btrim(p_poc),''),
    notes = nullif(btrim(p_notes),''),
    verdict = case when p_verdict in ('pending','approved','rejected') then p_verdict else 'pending' end,
    verified_by = p_actor, verified_at = now()
  where id = p_reference_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_verify_reference(uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_verify_reference(uuid,text,text,text,uuid) to service_role;

-- crm_add_reference restated: resolve/create the shared company by canonical key
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
  insert into public.customer_references(customer_id, reference_text, company_id, created_by, verdict)
    values (p_customer_id, v_name, v_company, p_actor, 'pending');
  insert into public.customer_crm(customer_id, has_reference, crm_updated_at, crm_updated_by)
    values (p_customer_id, true, now(), p_actor)
    on conflict (customer_id) do update set has_reference=true, crm_updated_at=now(), crm_updated_by=p_actor;
  return jsonb_build_object('ok', true, 'companyId', v_company);
end $$;
revoke all on function public.crm_add_reference(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_add_reference(uuid,text,uuid) to service_role;

-- ── crm_list_customers: + category chips, referenceStanding, refRejected (029 + adds) ──
-- Whole function restated; the 022 tier-first ORDER BY is preserved verbatim.
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
           cc.assigned_to, cc.reference_standing,
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
  select jsonb_build_object(
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', f.id, 'companyName', f.company_name, 'contactName', f.contact_name,
          'phone', f.phone_e164, 'city', f.city, 'state', f.state,
          'buyerType', f.buyer_type, 'tier', f.tier, 'crmStatus', f.crm_status,
          'assignedTo', f.assigned_to, 'assignedName', sp.staff_name,
          'hasReference', f.has_reference, 'tokenAgreed', f.token_agreed, 'tokenAmount', f.token_amount,
          'checkedInAt', f.checked_in_at,
          'referenceStanding', f.reference_standing,
          'refRejected', exists(select 1 from public.customer_references r where r.customer_id = f.id and r.verdict = 'rejected'),
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

-- ── admin_dispatch_orders: + referenceStanding, refRejected, refRejectReason (030 + adds) ──
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
      nullif(btrim(coalesce(p_filters ->> 'search','')), '') as q,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 300), 500)) as lim,
      greatest(0, coalesce((p_filters ->> 'offset')::int, 0)) as off
  ),
  matched as (
    select o.id, o.customer_id, o.firm, o.status, o.dispatch_status,
           o.total_designs, o.total_sets, o.total_pieces, o.updated_at,
           c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.agent, cc.tier, cc.reference_standing
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
        'agent', pg.agent, 'tier', pg.tier,
        'referenceStanding', pg.reference_standing,
        'refRejected', exists(select 1 from public.customer_references r where r.customer_id = pg.customer_id and r.verdict = 'rejected'),
        'refRejectReason', (
          select string_agg(distinct coalesce(nullif(btrim(r.notes),''), rc.name, 'rejected'), ' | ')
          from public.customer_references r left join public.reference_companies rc on rc.id = r.company_id
          where r.customer_id = pg.customer_id and r.verdict = 'rejected')
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
