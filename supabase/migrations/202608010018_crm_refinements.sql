-- 202608010018_crm_refinements.sql
--
-- CRM refinements: token/reference become standalone customer attributes (off the
-- call), rejection reasons, callback follow-up dates, bulk assign/buyer-type,
-- call-queue metadata, and a default "has orders" filter.
--
-- All functions: security definer, search_path=public, revoked from
-- public/anon/authenticated, granted to service_role only. Signature changes use
-- drop-then-recreate (house style).

begin;

-- ── 1. Schema ───────────────────────────────────────────────────────────────
alter table public.customer_crm  add column if not exists status_reason text null;
alter table public.customer_calls add column if not exists followup_at   timestamptz null;
create index if not exists customer_calls_followup_idx on public.customer_calls(followup_at) where followup_at is not null;

-- ── 2. Standalone customer-attribute setters (token + reference off the call) ─
create or replace function public.crm_set_reference_flag(p_customer_id uuid, p_has_reference boolean, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old boolean; v_new boolean;
begin
  v_new := coalesce(p_has_reference, false);
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select has_reference into v_old from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, has_reference, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, now(), p_actor)
    on conflict (customer_id) do update set has_reference = excluded.has_reference, crm_updated_at = now(), crm_updated_by = p_actor;
  if coalesce(v_old,false) is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'has_reference', coalesce(v_old,false)::text, v_new::text);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_set_token(p_customer_id uuid, p_token_agreed boolean, p_token_amount numeric, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old_agreed boolean; v_old_amt numeric(12,2); v_agreed boolean; v_amt numeric(12,2);
begin
  v_agreed := coalesce(p_token_agreed, false);
  -- Amount is meaningful only when agreed. Technical bound only (non-negative,
  -- within numeric(12,2)); the business ceiling + required-when-agreed rule is a
  -- separate proposal (brief item a), deliberately not enforced here yet.
  v_amt := case when v_agreed then p_token_amount else null end;
  if v_amt is not null and (v_amt < 0 or v_amt > 99999999.99) then raise exception 'INVALID_TOKEN_AMOUNT'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select token_agreed, token_amount into v_old_agreed, v_old_amt from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, token_agreed, token_amount, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_agreed, v_amt, now(), p_actor)
    on conflict (customer_id) do update set token_agreed = excluded.token_agreed, token_amount = excluded.token_amount, crm_updated_at = now(), crm_updated_by = p_actor;
  if coalesce(v_old_agreed,false) is distinct from v_agreed then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'token_agreed', coalesce(v_old_agreed,false)::text, v_agreed::text);
  end if;
  if v_old_amt is distinct from v_amt then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'token_amount', v_old_amt::text, v_amt::text);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- ── 3. crm_set_status gains a reason (signature change → drop first) ─────────
drop function if exists public.crm_set_status(uuid, text, uuid);
create or replace function public.crm_set_status(p_customer_id uuid, p_status text, p_reason text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text; v_reason text; v_old_reason text;
begin
  v_new := nullif(btrim(coalesce(p_status,'')), '');
  if v_new is null or v_new not in ('pending','on_hold','agreed','rejected') then raise exception 'INVALID_STATUS'; end if;
  v_reason := nullif(btrim(coalesce(p_reason,'')), '');
  -- Reason is REQUIRED when rejecting; optional otherwise.
  if v_new = 'rejected' and v_reason is null then raise exception 'REJECTION_REASON_REQUIRED'; end if;
  if length(coalesce(v_reason,'')) > 2000 then raise exception 'REASON_TOO_LONG'; end if;
  -- A reason only belongs to a rejection; clear it for any other status.
  if v_new <> 'rejected' then v_reason := null; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select coalesce(crm_status,'pending'), status_reason into v_old, v_old_reason from public.customer_crm where customer_id = p_customer_id;
  v_old := coalesce(v_old, 'pending');
  insert into public.customer_crm(customer_id, crm_status, status_reason, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, v_reason, now(), p_actor)
    on conflict (customer_id) do update set crm_status = excluded.crm_status, status_reason = excluded.status_reason, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'crm_status', v_old, v_new);
  end if;
  if v_old_reason is distinct from v_reason then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'status_reason', v_old_reason, v_reason);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- ── 4. crm_log_call: token/reference removed, follow-up date added (drop first) ─
drop function if exists public.crm_log_call(uuid, text, text, text, boolean, boolean, numeric, uuid);
create or replace function public.crm_log_call(
  p_customer_id uuid, p_outcome text, p_notes text, p_status_after text, p_followup_at timestamptz, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old_status text; v_status text;
begin
  if p_outcome is null or p_outcome not in ('connected','no_answer','busy','wrong_number','callback') then raise exception 'INVALID_OUTCOME'; end if;
  -- A callback with no date is a lost callback.
  if p_outcome = 'callback' and p_followup_at is null then raise exception 'FOLLOWUP_DATE_REQUIRED'; end if;
  v_status := nullif(btrim(coalesce(p_status_after,'')), '');
  if v_status is not null and v_status not in ('pending','on_hold','agreed','rejected') then raise exception 'INVALID_STATUS'; end if;
  if length(coalesce(p_notes,'')) > 4000 then raise exception 'NOTES_TOO_LONG'; end if;
  -- Status can no longer be set to 'rejected' from a call (a rejection needs a
  -- reason; use crm_set_status). Guard rather than silently drop it.
  if v_status = 'rejected' then raise exception 'REJECT_VIA_STATUS_NOT_CALL'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  insert into public.customer_calls(customer_id, called_by, outcome, notes, status_after, followup_at)
  values (p_customer_id, p_actor, p_outcome, coalesce(btrim(p_notes),''), v_status, p_followup_at);

  if v_status is not null then
    select coalesce(crm_status,'pending') into v_old_status from public.customer_crm where customer_id = p_customer_id;
    v_old_status := coalesce(v_old_status, 'pending');
    insert into public.customer_crm(customer_id, crm_status, crm_updated_at, crm_updated_by)
      values (p_customer_id, v_status, now(), p_actor)
      on conflict (customer_id) do update set crm_status = excluded.crm_status, crm_updated_at = now(), crm_updated_by = p_actor;
    if v_status is distinct from v_old_status then
      insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'crm_status', v_old_status, v_status);
    end if;
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- ── 5. Bulk operations — one round trip, one transaction, one log row/customer ─
create or replace function public.crm_bulk_assign(p_customer_ids uuid[], p_assigned_to uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  if p_customer_ids is null or array_length(p_customer_ids,1) is null then raise exception 'NO_CUSTOMERS'; end if;
  if array_length(p_customer_ids,1) > 2000 then raise exception 'TOO_MANY_CUSTOMERS'; end if;
  if p_assigned_to is not null and not exists (select 1 from public.staff_profiles where auth_user_id = p_assigned_to) then raise exception 'ASSIGNEE_NOT_STAFF'; end if;

  with ids as (select distinct unnest(p_customer_ids) as customer_id),
  old as (select i.customer_id, cc.assigned_to as old_val from ids i left join public.customer_crm cc on cc.customer_id = i.customer_id),
  up as (
    insert into public.customer_crm(customer_id, assigned_to, crm_updated_at, crm_updated_by)
    select customer_id, p_assigned_to, now(), p_actor from ids
    on conflict (customer_id) do update set assigned_to = excluded.assigned_to, crm_updated_at = now(), crm_updated_by = p_actor
    returning customer_id
  ),
  logged as (
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    select o.customer_id, p_actor, 'assigned_to', o.old_val::text, p_assigned_to::text
    from old o where o.old_val is distinct from p_assigned_to
    returning 1
  )
  select count(*) into v_count from up;
  return jsonb_build_object('ok', true, 'count', v_count);
end; $$;

create or replace function public.crm_bulk_set_buyer_type(p_customer_ids uuid[], p_buyer_type text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_new text; v_count integer;
begin
  v_new := nullif(btrim(coalesce(p_buyer_type,'')), '');
  if v_new is not null and v_new not in ('new','old') then raise exception 'INVALID_BUYER_TYPE'; end if;
  if p_customer_ids is null or array_length(p_customer_ids,1) is null then raise exception 'NO_CUSTOMERS'; end if;
  if array_length(p_customer_ids,1) > 2000 then raise exception 'TOO_MANY_CUSTOMERS'; end if;

  with ids as (select distinct unnest(p_customer_ids) as customer_id),
  old as (select i.customer_id, cc.buyer_type as old_val from ids i left join public.customer_crm cc on cc.customer_id = i.customer_id),
  up as (
    insert into public.customer_crm(customer_id, buyer_type, crm_updated_at, crm_updated_by)
    select customer_id, v_new, now(), p_actor from ids
    on conflict (customer_id) do update set buyer_type = excluded.buyer_type, crm_updated_at = now(), crm_updated_by = p_actor
    returning customer_id
  ),
  logged as (
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    select o.customer_id, p_actor, 'buyer_type', o.old_val, v_new
    from old o where o.old_val is distinct from v_new
    returning 1
  )
  select count(*) into v_count from up;
  return jsonb_build_object('ok', true, 'count', v_count);
end; $$;

-- ── 6. crm_list_customers: call metadata, order-line count, callbacks-due, sort ─
create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')   as q,
      nullif(btrim(coalesce(p_filters ->> 'buyerType','')), '') as buyer_type,
      nullif(btrim(coalesce(p_filters ->> 'status','')), '')   as status,
      coalesce((p_filters ->> 'withOrders')::boolean, false)    as with_orders,
      coalesce((p_filters ->> 'callbacksDue')::boolean, false)  as callbacks_due,
      coalesce(nullif(btrim(coalesce(p_filters ->> 'sort','')), ''), 'recent') as sort,
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 500), 2000)) as lim
  ),
  scoped as (
    select c.id, c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.created_at, c.checked_in_at,
           cc.buyer_type,
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
           or (p.buyer_type in ('new','old') and s.buyer_type = p.buyer_type))
      and (p.status is null or s.crm_status = p.status)
      and (not p.with_orders or s.order_line_count > 0)
      and (not p.callbacks_due or s.followup_due)
      and (p.q is null
           or s.company_name ilike '%'||p.q||'%'
           or s.contact_name ilike '%'||p.q||'%'
           or s.phone_e164   ilike '%'||p.q||'%'
           or s.city         ilike '%'||p.q||'%')
    -- queue: never-called first, then oldest call first. callback: oldest due
    -- first. recent (default): newest registration first.
    order by
      case when p.sort = 'queue'    then (s.last_call_at is not null) end asc,
      case when p.sort = 'queue'    then s.last_call_at end asc nulls first,
      case when p.sort = 'callback' then s.followup_at end asc nulls last,
      s.created_at desc
    limit (select lim from params)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', f.id, 'companyName', f.company_name, 'contactName', f.contact_name,
      'phone', f.phone_e164, 'city', f.city, 'state', f.state,
      'buyerType', f.buyer_type, 'crmStatus', f.crm_status,
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
      f.created_at desc
  ), '[]'::jsonb)
  from filtered f
  left join public.staff_profiles sp on sp.auth_user_id = f.assigned_to, params p;
$$;

-- crm_customer_detail: expose status_reason (customer section shows/edits it).
create or replace function public.crm_customer_detail(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'companyName', c.company_name, 'contactName', c.contact_name,
    'phone', c.phone_e164, 'city', c.city, 'state', c.state, 'gstin', c.gstin,
    'buyerType', cc.buyer_type,
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

-- ── 7. Reception banner: reason + who + when ────────────────────────────────
create or replace function public.admin_directory(
  p_query text default ''::text, p_limit integer default 400, p_exhibition_id uuid default null::uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  with matched as (
    select
      c.id, c.phone_e164, c.company_name, c.contact_name, c.city, c.state,
      c.gstin, c.agent, c.active, c.checked_in_at, c.ordering_started_at,
      c.edit_deadline, c.created_at,
      coalesce(cc.crm_status,'pending') as crm_status, cc.status_reason, cc.crm_updated_at,
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
      'editDeadline', m.edit_deadline, 'crmStatus', m.crm_status,
      'crmStatusReason', m.status_reason, 'crmUpdatedAt', m.crm_updated_at, 'crmUpdatedByName', m.crm_updated_by_name,
      'booking', case when m.booking_id is null then null else jsonb_build_object(
        'id', m.booking_id, 'slotId', m.slot_id, 'startsAt', m.starts_at,
        'endsAt', m.ends_at, 'label', m.slot_label, 'partySize', m.party_size, 'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$$;

-- ── 8. Grants — service-role only, every new/recreated function ──────────────
revoke all on function public.crm_set_reference_flag(uuid, boolean, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_set_reference_flag(uuid, boolean, uuid) to service_role;
revoke all on function public.crm_set_token(uuid, boolean, numeric, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_set_token(uuid, boolean, numeric, uuid) to service_role;
revoke all on function public.crm_set_status(uuid, text, text, uuid)          from public, anon, authenticated;
grant  execute on function public.crm_set_status(uuid, text, text, uuid)      to service_role;
revoke all on function public.crm_log_call(uuid, text, text, text, timestamptz, uuid) from public, anon, authenticated;
grant  execute on function public.crm_log_call(uuid, text, text, text, timestamptz, uuid) to service_role;
revoke all on function public.crm_bulk_assign(uuid[], uuid, uuid)             from public, anon, authenticated;
grant  execute on function public.crm_bulk_assign(uuid[], uuid, uuid)         to service_role;
revoke all on function public.crm_bulk_set_buyer_type(uuid[], text, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_bulk_set_buyer_type(uuid[], text, uuid) to service_role;
revoke all on function public.crm_list_customers(jsonb)                       from public, anon, authenticated;
grant  execute on function public.crm_list_customers(jsonb)                   to service_role;
revoke all on function public.crm_customer_detail(uuid)                       from public, anon, authenticated;
grant  execute on function public.crm_customer_detail(uuid)                   to service_role;
revoke all on function public.admin_directory(text, integer, uuid)            from public, anon, authenticated;
grant  execute on function public.admin_directory(text, integer, uuid)        to service_role;

commit;
