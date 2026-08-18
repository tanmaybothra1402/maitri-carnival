-- 202608010020_customer_tier.sql
--
-- Customer ranking (tier A/B/C, NULL = unranked). Stored on public.customer_crm
-- (the RLS-no-policy 1:1 CRM table), NOT on public.customers — customers is
-- readable by the `authenticated` role (a logged-in buyer), and a buyer must never
-- learn they are ranked 'C'. This keeps tier behind the same wall as the rest of
-- the CRM data (migrations 016/017).
--
-- Setters mirror the buyer_type pattern (accept NULL to clear; one customer_crm_log
-- row per customer; security definer / search_path / service-role-only grants).
-- Six existing readers are extended to surface tier for the badge; the two
-- dashboard readers are granted to `authenticated` but guard with
-- staff_has_permission as their FIRST statement (verified: no path returns data
-- before the guard), so extending their payload does not widen exposure.
--
-- Also fixes a latent bug from 019: crm_list_customers still filtered buyer_type on
-- ('new','old'), so filtering by 'regular' returned zero rows. Corrected here.

begin;

-- ── 1. Column ───────────────────────────────────────────────────────────────
alter table public.customer_crm add column if not exists tier text null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='customer_crm_tier_check') then
    alter table public.customer_crm add constraint customer_crm_tier_check
      check (tier is null or tier in ('A','B','C'));
  end if;
end $$;
create index if not exists customer_crm_tier_idx on public.customer_crm(tier);

-- ── 2. Setters ──────────────────────────────────────────────────────────────
create or replace function public.crm_set_tier(p_customer_id uuid, p_tier text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_tier,'')), '');
  if v_new is not null and v_new not in ('A','B','C') then raise exception 'INVALID_TIER'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select tier into v_old from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, tier, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, now(), p_actor)
    on conflict (customer_id) do update set tier = excluded.tier, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'tier', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_bulk_set_tier(p_customer_ids uuid[], p_tier text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_new text; v_count integer;
begin
  v_new := nullif(btrim(coalesce(p_tier,'')), '');
  if v_new is not null and v_new not in ('A','B','C') then raise exception 'INVALID_TIER'; end if;
  if p_customer_ids is null or array_length(p_customer_ids,1) is null then raise exception 'NO_CUSTOMERS'; end if;
  if array_length(p_customer_ids,1) > 2000 then raise exception 'TOO_MANY_CUSTOMERS'; end if;

  with ids as (select distinct unnest(p_customer_ids) as customer_id),
  old as (select i.customer_id, cc.tier as old_val from ids i left join public.customer_crm cc on cc.customer_id = i.customer_id),
  up as (
    insert into public.customer_crm(customer_id, tier, crm_updated_at, crm_updated_by)
    select customer_id, v_new, now(), p_actor from ids
    on conflict (customer_id) do update set tier = excluded.tier, crm_updated_at = now(), crm_updated_by = p_actor
    returning customer_id
  ),
  logged as (
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    select o.customer_id, p_actor, 'tier', o.old_val, v_new
    from old o where o.old_val is distinct from v_new
    returning 1
  )
  select count(*) into v_count from up;
  return jsonb_build_object('ok', true, 'count', v_count);
end; $$;

-- ── 3. crm_list_customers — add tier (field, filter, sort) + fix the 019 filter ─
create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')   as q,
      nullif(btrim(coalesce(p_filters ->> 'buyerType','')), '') as buyer_type,
      nullif(btrim(coalesce(p_filters ->> 'status','')), '')   as status,
      nullif(btrim(coalesce(p_filters ->> 'tier','')), '')     as tier,
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
      case when p.sort = 'tier'     then s.tier end asc nulls last,
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
      case when p.sort = 'tier'     then f.tier end asc nulls last,
      f.created_at desc
  ), '[]'::jsonb)
  from filtered f
  left join public.staff_profiles sp on sp.auth_user_id = f.assigned_to, params p;
$$;

-- ── 4. crm_customer_detail — add tier ───────────────────────────────────────
create or replace function public.crm_customer_detail(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
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
      select jsonb_agg(jsonb_build_object('id', r.id, 'text', r.reference_text, 'createdAt', r.created_at) order by r.created_at desc)
      from public.customer_references r where r.customer_id = c.id
    ), '[]'::jsonb)
  )
  from public.customers c
  left join public.customer_crm cc on cc.customer_id = c.id
  where c.id = p_customer_id;
$$;

-- ── 5. admin_directory (reception + sale search) — add tier ─────────────────
create or replace function public.admin_directory(p_query text default ''::text, p_limit integer default 400, p_exhibition_id uuid default null::uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  with matched as (
    select
      c.id, c.phone_e164, c.company_name, c.contact_name, c.city, c.state,
      c.gstin, c.agent, c.active, c.checked_in_at, c.ordering_started_at,
      c.edit_deadline, c.created_at,
      coalesce(cc.crm_status,'pending') as crm_status, cc.status_reason, cc.crm_updated_at, cc.tier,
      (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = cc.crm_updated_by) as crm_updated_by_name,
      b.id booking_id, b.party_size, b.note booking_note,
      s.id slot_id, s.starts_at, s.ends_at, s.label slot_label
    from public.customers c
    left join public.customer_crm cc on cc.customer_id = c.id
    left join lateral (
      select bx.* from public.bookings bx
      where bx.customer_id = c.id and bx.status = 'Booked'
      order by bx.updated_at desc limit 1
    ) b on true
    left join public.slots s on s.id = b.slot_id
    where c.exhibition_id = coalesce(p_exhibition_id, public.current_exhibition_id())
      and (nullif(btrim(coalesce(p_query,'')), '') is null
       or c.phone_e164 ilike '%' || btrim(p_query) || '%'
       or c.company_name ilike '%' || btrim(p_query) || '%'
       or c.contact_name ilike '%' || btrim(p_query) || '%'
       or c.city ilike '%' || btrim(p_query) || '%'
       or c.state ilike '%' || btrim(p_query) || '%'
       or c.gstin ilike '%' || btrim(p_query) || '%'
       or c.agent ilike '%' || btrim(p_query) || '%')
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit,400), 600))
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'phone', m.phone_e164, 'companyName', m.company_name,
      'contactName', m.contact_name, 'city', m.city, 'state', m.state,
      'gstin', m.gstin, 'agent', m.agent, 'active', m.active,
      'checkedInAt', m.checked_in_at, 'orderingStartedAt', m.ordering_started_at,
      'editDeadline', m.edit_deadline, 'crmStatus', m.crm_status, 'tier', m.tier,
      'crmStatusReason', m.status_reason, 'crmUpdatedAt', m.crm_updated_at, 'crmUpdatedByName', m.crm_updated_by_name,
      'booking', case when m.booking_id is null then null else jsonb_build_object(
        'id', m.booking_id, 'slotId', m.slot_id, 'startsAt', m.starts_at,
        'endsAt', m.ends_at, 'label', m.slot_label, 'partySize', m.party_size, 'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$$;

-- ── 6. admin_dispatch_detail — add tier to the customer block ────────────────
create or replace function public.admin_dispatch_detail(p_order_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', o.id, 'firm', o.firm, 'status', o.status, 'dispatchStatus', o.dispatch_status,
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

-- ── 7. admin_dashboard_v2 — add tier to the customers table + orders ────────
-- (guard is the first statement; only the customer-facing table gains tier.)
create or replace function public.admin_dashboard_v2(p_filters jsonb default '{}'::jsonb, p_search text default ''::text, p_limit integer default 100, p_offset integer default 0, p_exhibition_id uuid default null::uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'auth' as $$
declare
  v_search text := '%' || btrim(coalesce(p_search,'')) || '%';
  v_exhibition uuid := coalesce(p_exhibition_id, public.current_exhibition_id());
  v_summary jsonb; v_charts jsonb; v_orders jsonb; v_total_orders integer; v_options jsonb;
begin
  if not public.staff_has_permission(auth.uid(),'dashboard.view') then raise exception 'PERMISSION_DENIED'; end if;
  drop table if exists _dash_facts;
  create temporary table _dash_facts on commit drop as
  select
    o.id order_id, o.customer_id, o.firm, o.status, o.updated_at,
    i.design_no, i.qty sets, (i.qty * i.pcs_per_set_snapshot) pieces,
    coalesce(nullif(btrim(i.category_snapshot),''),'Not specified') category,
    coalesce(nullif(btrim(i.style_snapshot),''),'Not specified') style,
    coalesce(nullif(btrim(i.fabric_snapshot),''),'Not specified') fabric,
    coalesce(nullif(btrim(i.last_modified_by_type),''),'unknown') source,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.city),''),'Not specified') city,
    coalesce(nullif(btrim(c.state),''),'Not specified') state,
    coalesce(nullif(btrim(c.agent),''),'Not specified') agent,
    c.checked_in_at, cc.tier
  from public.order_items i
  join public.orders o on o.id=i.order_id
  join public.customers c on c.id=o.customer_id
  left join public.customer_crm cc on cc.customer_id=o.customer_id
  where
    o.exhibition_id = v_exhibition
    and (not (p_filters ? 'firm') or o.firm = any(select jsonb_array_elements_text(p_filters->'firm')))
    and (not (p_filters ? 'state') or coalesce(nullif(btrim(c.state),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'state')))
    and (not (p_filters ? 'city') or coalesce(nullif(btrim(c.city),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'city')))
    and (not (p_filters ? 'agent') or coalesce(nullif(btrim(c.agent),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'agent')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'category')))
    and (not (p_filters ? 'style') or coalesce(nullif(btrim(i.style_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'style')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'fabric')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters->'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters->'companyName')))
    and (not (p_filters ? 'status') or o.status = any(select jsonb_array_elements_text(p_filters->'status')))
    and (not (p_filters ? 'source') or coalesce(nullif(btrim(i.last_modified_by_type),''),'unknown') = any(select jsonb_array_elements_text(p_filters->'source')))
    and (not (p_filters ? 'checkedIn') or (case when c.checked_in_at is null then 'No' else 'Yes' end) = any(select jsonb_array_elements_text(p_filters->'checkedIn')))
    and (not (p_filters ? 'dateFrom') or o.updated_at >= ((p_filters->'dateFrom'->>0)::date)::timestamptz)
    and (not (p_filters ? 'dateTo') or o.updated_at < (((p_filters->'dateTo'->>0)::date + 1))::timestamptz)
    and (
      btrim(coalesce(p_search,''))='' or c.company_name ilike v_search or c.contact_name ilike v_search
      or c.phone_e164 ilike v_search or i.design_no ilike v_search
    );
  select jsonb_build_object(
    'totalCustomers',(select count(*) from public.customers where exhibition_id = v_exhibition),
    'checkedInCustomers',(select count(*) from public.customers where checked_in_at is not null and exhibition_id = v_exhibition),
    'customersWithOrders',count(distinct customer_id),
    'totalOrders',count(distinct order_id),
    'totalSets',coalesce(sum(sets),0),
    'totalPieces',coalesce(sum(pieces),0),
    'uniqueDesigns',count(distinct design_no),
    'averagePiecesPerBuyer',case when count(distinct customer_id)=0 then 0 else round(coalesce(sum(pieces),0)::numeric/count(distinct customer_id),1) end,
    'activeBookings',(select count(*) from public.bookings b join public.customers c on c.id=b.customer_id where b.status='Booked' and c.exhibition_id = v_exhibition)
  ) into v_summary from _dash_facts;
  select jsonb_build_object(
    'firm', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select firm label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers from _dash_facts group by firm order by sum(pieces) desc limit 100)x),
    'statePieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select state label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers from _dash_facts group by state order by sum(pieces) desc limit 100)x),
    'stateCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select state label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by state order by count(distinct customer_id) desc limit 100)x),
    'cityPieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select city label,sum(pieces)::int value,count(distinct customer_id)::int customers from _dash_facts group by city order by sum(pieces) desc limit 100)x),
    'cityCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select city label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by city order by count(distinct customer_id) desc limit 100)x),
    'agentPieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select agent label,sum(pieces)::int value,count(distinct customer_id)::int customers from _dash_facts group by agent order by sum(pieces) desc limit 100)x),
    'agentCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select agent label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by agent order by count(distinct customer_id) desc limit 100)x),
    'category', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select category label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by category order by sum(pieces) desc limit 100)x),
    'style', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select style label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by style order by sum(pieces) desc limit 100)x),
    'fabric', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select fabric label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by fabric order by sum(pieces) desc limit 100)x),
    'designs', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select design_no label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers,min(category) category,min(style) style,min(fabric) fabric from _dash_facts group by design_no order by sum(pieces) desc limit 100)x),
    'customers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select customer_id::text id,company_name label,sum(pieces)::int value,sum(sets)::int sets,count(distinct design_no)::int designs,count(distinct order_id)::int orders,min(city) city,min(state) state,min(agent) agent,min(tier) tier from _dash_facts group by customer_id,company_name order by sum(pieces) desc limit 100)x),
    'source', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select source label,sum(pieces)::int value from _dash_facts group by source order by sum(pieces) desc limit 100)x)
  ) into v_charts;
  select count(*) into v_total_orders from (select distinct order_id from _dash_facts) q;
  select coalesce(jsonb_agg(x order by x."updatedAt" desc),'[]'::jsonb) into v_orders from (
    select order_id::text "orderId",customer_id::text "customerId",min(company_name) "companyName",min(contact_name) "contactName",
      min(phone_e164) phone,min(city) city,min(state) state,min(agent) agent,min(firm) firm,min(status) status,min(tier) tier,
      count(distinct design_no)::int designs,sum(sets)::int sets,sum(pieces)::int pieces,max(updated_at) "updatedAt"
    from _dash_facts group by order_id,customer_id order by max(updated_at) desc
    limit greatest(1,least(200,coalesce(p_limit,100))) offset greatest(0,coalesce(p_offset,0))
  ) x;
  select jsonb_build_object(
    'firm',jsonb_build_array('Maitri','Niharika'),
    'state',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(state),''),'Not specified') v from public.customers where exhibition_id = v_exhibition)s),
    'city',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(city),''),'Not specified') v from public.customers where exhibition_id = v_exhibition)s),
    'agent',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(agent),''),'Not specified') v from public.customers where exhibition_id = v_exhibition)s),
    'category',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(category),''),'Not specified') v from public.designs)s),
    'style',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(style),''),'Not specified') v from public.designs)s),
    'fabric',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(fabric),''),'Not specified') v from public.designs)s),
    'status',jsonb_build_array('Draft','Saved','Locked'),
    'source',jsonb_build_array('customer','staff','unknown'),
    'checkedIn',jsonb_build_array('Yes','No')
  ) into v_options;
  return jsonb_build_object('summary',v_summary,'charts',v_charts,'orders',v_orders,'totalOrders',v_total_orders,'options',v_options,'generatedAt',now());
end;
$$;

-- ── 8. admin_dashboard_drill_v1 — add tier to customerDetails ───────────────
create or replace function public.admin_dashboard_drill_v1(p_dimension text, p_value text, p_filters jsonb default '{}'::jsonb, p_search text default ''::text, p_exhibition_id uuid default null::uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'auth' as $$
declare
  v_search text := '%' || btrim(coalesce(p_search, '')) || '%';
  v_exhibition uuid := coalesce(p_exhibition_id, public.current_exhibition_id());
  v_summary jsonb; v_customers jsonb; v_designs jsonb;
begin
  if not public.staff_has_permission(auth.uid(), 'dashboard.view') then raise exception 'PERMISSION_DENIED'; end if;
  if p_dimension not in ('designNo','companyName','firm','state','city','agent','category','style','fabric','source') then
    raise exception 'INVALID_DASHBOARD_DIMENSION';
  end if;
  drop table if exists pg_temp._dashboard_drill_facts;
  create temporary table _dashboard_drill_facts on commit drop as
  select
    o.id as order_id, o.customer_id, o.firm, o.status, o.updated_at,
    i.design_no, i.qty as sets, i.qty * i.pcs_per_set_snapshot as pieces,
    coalesce(nullif(btrim(i.category_snapshot), ''),'Not specified') as category,
    coalesce(nullif(btrim(i.style_snapshot), ''),'Not specified') as style,
    coalesce(nullif(btrim(i.fabric_snapshot), ''),'Not specified') as fabric,
    coalesce(nullif(btrim(i.last_modified_by_type), ''),'unknown') as source,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.city), ''),'Not specified') as city,
    coalesce(nullif(btrim(c.state), ''),'Not specified') as state,
    coalesce(nullif(btrim(c.agent), ''),'Not specified') as agent,
    c.checked_in_at, cc.tier
  from public.order_items i
  join public.orders o on o.id = i.order_id
  join public.customers c on c.id = o.customer_id
  left join public.customer_crm cc on cc.customer_id = o.customer_id
  where
    o.exhibition_id = v_exhibition
    and (not (p_filters ? 'firm') or o.firm = any(select jsonb_array_elements_text(p_filters -> 'firm')))
    and (not (p_filters ? 'state') or coalesce(nullif(btrim(c.state), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'state')))
    and (not (p_filters ? 'city') or coalesce(nullif(btrim(c.city), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'city')))
    and (not (p_filters ? 'agent') or coalesce(nullif(btrim(c.agent), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'agent')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'category')))
    and (not (p_filters ? 'style') or coalesce(nullif(btrim(i.style_snapshot), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'style')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot), ''),'Not specified') = any(select jsonb_array_elements_text(p_filters -> 'fabric')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters -> 'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters -> 'companyName')))
    and (not (p_filters ? 'status') or o.status = any(select jsonb_array_elements_text(p_filters -> 'status')))
    and (not (p_filters ? 'source') or coalesce(nullif(btrim(i.last_modified_by_type), ''),'unknown') = any(select jsonb_array_elements_text(p_filters -> 'source')))
    and (not (p_filters ? 'checkedIn') or (case when c.checked_in_at is null then 'No' else 'Yes' end) = any(select jsonb_array_elements_text(p_filters -> 'checkedIn')))
    and (not (p_filters ? 'dateFrom') or o.updated_at >= ((p_filters -> 'dateFrom' ->> 0)::date)::timestamptz)
    and (not (p_filters ? 'dateTo') or o.updated_at < (((p_filters -> 'dateTo' ->> 0)::date + 1))::timestamptz)
    and (btrim(coalesce(p_search, '')) = '' or c.company_name ilike v_search or c.contact_name ilike v_search or c.phone_e164 ilike v_search or i.design_no ilike v_search)
    and (
      case p_dimension
        when 'designNo' then i.design_no = p_value
        when 'companyName' then c.company_name = p_value
        when 'firm' then o.firm = p_value
        when 'state' then coalesce(nullif(btrim(c.state), ''),'Not specified') = p_value
        when 'city' then coalesce(nullif(btrim(c.city), ''),'Not specified') = p_value
        when 'agent' then coalesce(nullif(btrim(c.agent), ''),'Not specified') = p_value
        when 'category' then coalesce(nullif(btrim(i.category_snapshot), ''),'Not specified') = p_value
        when 'style' then coalesce(nullif(btrim(i.style_snapshot), ''),'Not specified') = p_value
        when 'fabric' then coalesce(nullif(btrim(i.fabric_snapshot), ''),'Not specified') = p_value
        when 'source' then coalesce(nullif(btrim(i.last_modified_by_type), ''),'unknown') = p_value
        else false
      end
    );
  select jsonb_build_object(
    'pieces', coalesce(sum(pieces), 0)::integer, 'sets', coalesce(sum(sets), 0)::integer,
    'customers', count(distinct customer_id)::integer, 'designs', count(distinct design_no)::integer,
    'orders', count(distinct order_id)::integer
  ) into v_summary from _dashboard_drill_facts;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pieces desc, x."companyName"),'[]'::jsonb)
  into v_customers
  from (
    select customer_id::text as "customerId", company_name as "companyName",
      min(contact_name) as "contactName", min(phone_e164) as phone,
      min(city) as city, min(state) as state, min(agent) as agent, min(tier) as tier,
      sum(sets)::integer as sets, sum(pieces)::integer as pieces,
      count(distinct design_no)::integer as designs, count(distinct order_id)::integer as orders
    from _dashboard_drill_facts group by customer_id, company_name
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pieces desc, x."designNo"),'[]'::jsonb)
  into v_designs
  from (
    select design_no as "designNo", min(firm) as firm, min(category) as category,
      min(style) as style, min(fabric) as fabric,
      sum(sets)::integer as sets, sum(pieces)::integer as pieces,
      count(distinct customer_id)::integer as customers, count(distinct order_id)::integer as orders
    from _dashboard_drill_facts group by design_no
  ) x;
  return jsonb_build_object('dimension', p_dimension, 'label', p_value, 'summary', v_summary, 'customerDetails', v_customers, 'designDetails', v_designs);
end;
$$;

-- ── 9. Grants ────────────────────────────────────────────────────────────────
-- New setters + the re-created CRM/dispatch/directory readers: service-role only.
revoke all on function public.crm_set_tier(uuid, text, uuid)          from public, anon, authenticated;
grant  execute on function public.crm_set_tier(uuid, text, uuid)      to service_role;
revoke all on function public.crm_bulk_set_tier(uuid[], text, uuid)   from public, anon, authenticated;
grant  execute on function public.crm_bulk_set_tier(uuid[], text, uuid) to service_role;
revoke all on function public.crm_list_customers(jsonb)               from public, anon, authenticated;
grant  execute on function public.crm_list_customers(jsonb)           to service_role;
revoke all on function public.crm_customer_detail(uuid)               from public, anon, authenticated;
grant  execute on function public.crm_customer_detail(uuid)           to service_role;
revoke all on function public.admin_directory(text, integer, uuid)    from public, anon, authenticated;
grant  execute on function public.admin_directory(text, integer, uuid) to service_role;
revoke all on function public.admin_dispatch_detail(uuid)             from public, anon, authenticated;
grant  execute on function public.admin_dispatch_detail(uuid)         to service_role;
-- The two dashboard readers stay granted to `authenticated` (guarded internally by
-- staff_has_permission); create-or-replace preserves their grants, so re-assert to
-- keep the intent explicit and unchanged.
grant execute on function public.admin_dashboard_v2(jsonb, text, integer, integer, uuid) to authenticated, service_role;
grant execute on function public.admin_dashboard_drill_v1(text, text, jsonb, text, uuid) to authenticated, service_role;

commit;
