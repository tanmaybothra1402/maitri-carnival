-- 202608010022_tier_first_ordering.sql
--
-- PART A — sort every customer list tier-first: A, then B, then C, then unranked
-- LAST. Tier becomes the PRIMARY ordering key; each list keeps its previous order
-- as the tiebreak. Done in SQL (in the ORDER BY, BEFORE the LIMIT) because every
-- one of these lists is capped — a client-side sort after a limited fetch would
-- silently drop A-tier customers that fall outside the fetched page.
--
-- Rank is explicit (case, not text collation): A=1, B=2, C=3, unranked=4.
--
-- Scope decisions:
--   crm_list_customers  — tier-first DEFAULT; an explicitly chosen sort (Call queue,
--                         Callback date) still wins, with tier kept as a tiebreak.
--   admin_directory     — Reception check-in list + Sale Order customer search.
--                         Tier-first, created_at desc tiebreak.
--   admin_dispatch_orders (NEW) — dispatch by-order list + by-product buyer roll-up.
--                         listDispatch was a PostgREST query with a 300-row cap and
--                         486 dispatchable orders; a nested-tier sort can't be
--                         expressed there and post-limit sorting would drop A-tier.
--                         Moved into this RPC so the tier-first ORDER BY runs before
--                         the cap.
-- Excluded (reported, not silently skipped): the Dashboard tables
-- (admin_dashboard_v2 / admin_dashboard_drill_v1). Every table there is metric-
-- ranked (pieces / order value — "best customers" is the information) or a recency
-- orders feed; reordering them tier-first would destroy that meaning. Tier badges
-- already render on those rows. admin_dispatch_detail is a single-order detail
-- (no list to order).

-- ── crm_list_customers ──────────────────────────────────────────────────────
-- Whole function restated (house style). Only the two ORDER BY clauses change: the
-- old explicit "case when p.sort='tier' then s.tier end" key is replaced by an
-- UNCONDITIONAL tier rank, placed AFTER the queue/callback keys. Net effect:
--   • default 'recent'  → tier rank primary, created_at desc tiebreak
--   • 'queue'/'callback'→ that sort stays primary, tier rank is the tiebreak
--   • explicit 'tier'   → same as default (tier rank primary)
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

-- ── admin_directory ─────────────────────────────────────────────────────────
-- Reception check-in list + Sale Order customer search. No user-chosen sort here,
-- so tier rank is the unconditional primary; created_at desc stays the tiebreak.
create or replace function public.admin_directory(p_query text default ''::text, p_limit integer default 400, p_exhibition_id uuid default null::uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
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
    order by
      case cc.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      c.created_at desc
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
    ) order by
      case m.tier when 'A' then 1 when 'B' then 2 when 'C' then 3 else 4 end,
      m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$function$;

-- ── admin_dispatch_orders (NEW) ─────────────────────────────────────────────
-- Backs listDispatch. Returns the dispatch order rows the Edge already maps, but
-- ordered tier-first (A→B→C→unranked) with updated_at desc as the tiebreak, and
-- the LIMIT applied AFTER that ordering so A-tier orders are never truncated.
-- Filters mirror the old PostgREST query (exhibition, firm, dispatch status,
-- company/contact/phone search) — the search now joins directly in SQL instead of
-- a separate <=300-row customer id lookup, so it is no longer capped.
create or replace function public.admin_dispatch_orders(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with params as (
    select
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      nullif(btrim(coalesce(p_filters ->> 'firm','')), '')           as firm,
      nullif(btrim(coalesce(p_filters ->> 'dispatchStatus','')), '') as dispatch_status,
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')         as q,
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

-- New function: lock down to service_role only (admin-api calls it with the
-- service key). The restated functions keep their existing grants.
revoke all on function public.admin_dispatch_orders(jsonb) from public, anon, authenticated;
grant execute on function public.admin_dispatch_orders(jsonb) to service_role;
