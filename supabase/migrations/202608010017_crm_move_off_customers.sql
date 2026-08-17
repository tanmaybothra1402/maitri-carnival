-- 202608010017_crm_move_off_customers.sql
--
-- Durable fix for the CRM-on-customers fragility. 015 put 8 CRM columns on the
-- customer-readable public.customers table; 016 had to hide them with column-level
-- SELECT/UPDATE grants, which made select=* fail wholesale (the hotfix in
-- bd208b5). Column-grant privacy is fragile: any future select=* re-breaks it.
--
-- This moves the 8 CRM fields into a 1:1 public.customer_crm table (RLS on, no
-- policies, no grants to authenticated/anon — structurally unreachable), then
-- restores a NORMAL table-wide SELECT on customers so select=* is safe again.
--
-- UPDATE is deliberately NOT restored table-wide: that would let any logged-in
-- buyer write active / checked_in_at / edit_deadline / exhibition_id on their own
-- row (bypass the edit window, move between exhibitions). UPDATE stays column-
-- scoped to the 6 profile fields, permanently.
--
-- Atomic: everything runs in one transaction. The backfill count is asserted to
-- equal the customer count BEFORE the irreversible column drop — a mismatch
-- raises and rolls the whole migration back, so no data is lost.

begin;

-- ── 1. customer_crm (1:1, RLS on, no policies → service-role only) ──────────
create table if not exists public.customer_crm (
  customer_id    uuid primary key references public.customers(id) on delete cascade,
  buyer_type     text null,
  crm_status     text not null default 'pending',
  assigned_to    uuid null references auth.users(id) on delete set null,
  has_reference  boolean not null default false,
  token_agreed   boolean not null default false,
  token_amount   numeric(12,2) null,
  crm_updated_at timestamptz null,
  crm_updated_by uuid null references auth.users(id) on delete set null,
  constraint customer_crm_buyer_type_check check (buyer_type is null or buyer_type in ('new','old')),
  constraint customer_crm_status_check check (crm_status in ('pending','on_hold','agreed','rejected'))
);
create index if not exists customer_crm_status_idx on public.customer_crm(crm_status);
create index if not exists customer_crm_assigned_idx on public.customer_crm(assigned_to);

alter table public.customer_crm enable row level security;
-- No policies: customers must never read CRM data. Service role only.
revoke all on public.customer_crm from anon, authenticated;

-- ── 2. Backfill one row per existing customer (loss-free copy) ───────────────
insert into public.customer_crm(
  customer_id, buyer_type, crm_status, assigned_to, has_reference,
  token_agreed, token_amount, crm_updated_at, crm_updated_by)
select id, buyer_type, crm_status, assigned_to, has_reference,
       token_agreed, token_amount, crm_updated_at, crm_updated_by
from public.customers
on conflict (customer_id) do nothing;

-- ── 3. Verify the backfill BEFORE the irreversible drop. Abort if short. ────
do $$
declare v_customers integer; v_crm integer;
begin
  select count(*) into v_customers from public.customers;
  select count(*) into v_crm from public.customer_crm;
  if v_crm <> v_customers then
    raise exception 'BACKFILL_COUNT_MISMATCH: customers=% customer_crm=%', v_customers, v_crm;
  end if;
end $$;

-- ── 4. Rewrite the CRM RPCs + admin_directory to use customer_crm ───────────
-- Reads LEFT JOIN and coalesce(crm_status,'pending'); writes upsert so a missing
-- row (a customer registered after this migration) is created lazily.

create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')   as q,
      nullif(btrim(coalesce(p_filters ->> 'buyerType','')), '') as buyer_type,
      nullif(btrim(coalesce(p_filters ->> 'status','')), '')   as status,
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 500), 1000)) as lim
  ),
  scoped as (
    select c.id, c.company_name, c.contact_name, c.phone_e164, c.city, c.state, c.created_at, c.checked_in_at,
           cc.buyer_type,
           coalesce(cc.crm_status,'pending')    as crm_status,
           cc.assigned_to,
           coalesce(cc.has_reference,false)      as has_reference,
           coalesce(cc.token_agreed,false)       as token_agreed,
           cc.token_amount,
           regexp_replace(upper(coalesce(c.company_name,'')), '[^A-Z0-9]', '', 'g') as name_key
    from public.customers c
    left join public.customer_crm cc on cc.customer_id = c.id, params p
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
      and (p.q is null
           or s.company_name ilike '%'||p.q||'%'
           or s.contact_name ilike '%'||p.q||'%'
           or s.phone_e164   ilike '%'||p.q||'%'
           or s.city         ilike '%'||p.q||'%')
    order by s.created_at desc
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
      'callCount', (select count(*) from public.customer_calls cl where cl.customer_id = f.id),
      'lastCallAt', (select max(cl.called_at) from public.customer_calls cl where cl.customer_id = f.id),
      'dupName', coalesce((select d.name_n from dupes d where d.id = f.id), 1) > 1,
      'dupPhone', coalesce((select d.phone_n from dupes d where d.id = f.id), 1) > 1
    ) order by f.created_at desc
  ), '[]'::jsonb)
  from filtered f
  left join public.staff_profiles sp on sp.auth_user_id = f.assigned_to;
$$;

create or replace function public.crm_customer_detail(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'companyName', c.company_name, 'contactName', c.contact_name,
    'phone', c.phone_e164, 'city', c.city, 'state', c.state, 'gstin', c.gstin,
    'buyerType', cc.buyer_type,
    'crmStatus', coalesce(cc.crm_status,'pending'),
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
        'outcome', cl.outcome, 'notes', cl.notes, 'statusAfter', cl.status_after
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

create or replace function public.crm_set_buyer_type(p_customer_id uuid, p_buyer_type text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_buyer_type,'')), '');
  if v_new is not null and v_new not in ('new','old') then raise exception 'INVALID_BUYER_TYPE'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select buyer_type into v_old from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, buyer_type, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, now(), p_actor)
    on conflict (customer_id) do update set buyer_type = excluded.buyer_type, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'buyer_type', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_assign(p_customer_id uuid, p_assigned_to uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old uuid;
begin
  if p_assigned_to is not null and not exists (select 1 from public.staff_profiles where auth_user_id = p_assigned_to) then raise exception 'ASSIGNEE_NOT_STAFF'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select assigned_to into v_old from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, assigned_to, crm_updated_at, crm_updated_by)
    values (p_customer_id, p_assigned_to, now(), p_actor)
    on conflict (customer_id) do update set assigned_to = excluded.assigned_to, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from p_assigned_to then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'assigned_to', v_old::text, p_assigned_to::text);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_set_status(p_customer_id uuid, p_status text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_status,'')), '');
  if v_new is null or v_new not in ('pending','on_hold','agreed','rejected') then raise exception 'INVALID_STATUS'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select coalesce(crm_status,'pending') into v_old from public.customer_crm where customer_id = p_customer_id;
  v_old := coalesce(v_old, 'pending');
  insert into public.customer_crm(customer_id, crm_status, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, now(), p_actor)
    on conflict (customer_id) do update set crm_status = excluded.crm_status, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'crm_status', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_log_call(
  p_customer_id uuid, p_outcome text, p_notes text, p_status_after text,
  p_has_reference boolean, p_token_agreed boolean, p_token_amount numeric, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old_status text; v_status text; v_amount numeric(12,2);
begin
  if p_outcome is null or p_outcome not in ('connected','no_answer','busy','wrong_number','callback') then raise exception 'INVALID_OUTCOME'; end if;
  v_status := nullif(btrim(coalesce(p_status_after,'')), '');
  if v_status is not null and v_status not in ('pending','on_hold','agreed','rejected') then raise exception 'INVALID_STATUS'; end if;
  if length(coalesce(p_notes,'')) > 4000 then raise exception 'NOTES_TOO_LONG'; end if;
  v_amount := case when coalesce(p_token_agreed,false) then p_token_amount else null end;
  if v_amount is not null and (v_amount < 0 or v_amount > 99999999.99) then raise exception 'INVALID_TOKEN_AMOUNT'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  select coalesce(crm_status,'pending') into v_old_status from public.customer_crm where customer_id = p_customer_id;
  v_old_status := coalesce(v_old_status, 'pending');

  insert into public.customer_calls(customer_id, called_by, outcome, notes, status_after)
  values (p_customer_id, p_actor, p_outcome, coalesce(btrim(p_notes),''), v_status);

  insert into public.customer_crm(customer_id, has_reference, token_agreed, token_amount, crm_status, crm_updated_at, crm_updated_by)
    values (p_customer_id, coalesce(p_has_reference,false), coalesce(p_token_agreed,false), v_amount, coalesce(v_status,'pending'), now(), p_actor)
    on conflict (customer_id) do update set
      has_reference = coalesce(p_has_reference, customer_crm.has_reference),
      token_agreed  = coalesce(p_token_agreed, customer_crm.token_agreed),
      token_amount  = v_amount,
      crm_status    = coalesce(v_status, customer_crm.crm_status),
      crm_updated_at = now(), crm_updated_by = p_actor;

  if v_status is not null and v_status is distinct from v_old_status then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'crm_status', v_old_status, v_status);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- Reception flag: crm_status now comes from customer_crm.
create or replace function public.admin_directory(
  p_query text default ''::text, p_limit integer default 400, p_exhibition_id uuid default null::uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  with matched as (
    select
      c.id, c.phone_e164, c.company_name, c.contact_name, c.city, c.state,
      c.gstin, c.agent, c.active, c.checked_in_at, c.ordering_started_at,
      c.edit_deadline, c.created_at, coalesce(cc.crm_status,'pending') as crm_status,
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
      'booking', case when m.booking_id is null then null else jsonb_build_object(
        'id', m.booking_id, 'slotId', m.slot_id, 'startsAt', m.starts_at,
        'endsAt', m.ends_at, 'label', m.slot_label, 'partySize', m.party_size, 'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$$;

-- Re-assert grants on every (re)created function: service-role only.
revoke all on function public.crm_list_customers(jsonb)                 from public, anon, authenticated;
grant  execute on function public.crm_list_customers(jsonb)             to service_role;
revoke all on function public.crm_customer_detail(uuid)                 from public, anon, authenticated;
grant  execute on function public.crm_customer_detail(uuid)             to service_role;
revoke all on function public.crm_set_buyer_type(uuid, text, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_set_buyer_type(uuid, text, uuid) to service_role;
revoke all on function public.crm_assign(uuid, uuid, uuid)             from public, anon, authenticated;
grant  execute on function public.crm_assign(uuid, uuid, uuid)         to service_role;
revoke all on function public.crm_set_status(uuid, text, uuid)        from public, anon, authenticated;
grant  execute on function public.crm_set_status(uuid, text, uuid)    to service_role;
revoke all on function public.crm_log_call(uuid, text, text, text, boolean, boolean, numeric, uuid) from public, anon, authenticated;
grant  execute on function public.crm_log_call(uuid, text, text, text, boolean, boolean, numeric, uuid) to service_role;
revoke all on function public.admin_directory(text, integer, uuid)    from public, anon, authenticated;
grant  execute on function public.admin_directory(text, integer, uuid) to service_role;

-- ── 5. Drop the 8 CRM columns from customers (irreversible; after backfill+RPCs) ─
-- Dependent check constraints / indexes / FKs drop automatically with the columns.
alter table public.customers
  drop column if exists buyer_type,
  drop column if exists crm_status,
  drop column if exists assigned_to,
  drop column if exists has_reference,
  drop column if exists token_agreed,
  drop column if exists token_amount,
  drop column if exists crm_updated_at,
  drop column if exists crm_updated_by;

-- ── 6. Restore a NORMAL table-wide SELECT on customers (CRM columns are gone). ──
-- select=* is safe again — the fragility class is eliminated. UPDATE is NOT
-- restored table-wide: it stays column-scoped to the 6 profile fields from 016,
-- so a buyer can never write active / checked_in_at / edit_deadline / exhibition_id.
revoke select on public.customers from authenticated;
grant  select on public.customers to authenticated;

commit;
