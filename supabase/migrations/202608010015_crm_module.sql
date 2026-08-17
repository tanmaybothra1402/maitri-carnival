-- ---------------------------------------------------------------------------
-- Maitri Carnival 2026 — CRM module (buyer screening before first billing).
--
-- New buyers are assigned to a salesperson who calls them, logs the call,
-- records references, and asks for a token amount. Outcome is on_hold / agreed
-- / rejected. Rejected buyers are FLAGGED for questioning at future
-- exhibitions, never blocked at the gate.
--
-- All new tables are RLS-enabled with NO policies (service-role only). Every RPC
-- is security definer, search_path=public, revoked from public/anon/authenticated
-- and granted to service_role only. Customers are `authenticated` users — token
-- amounts, rejection status and call notes must be unreachable via PostgREST
-- (the designs/master-image leak class, guardrail A1).
-- ---------------------------------------------------------------------------

-- ── 1. CRM columns on customers ────────────────────────────────────────────
-- buyer_type is LIFETIME and set MANUALLY. It is deliberately NOT derived from
-- dispatch_lines: this app is not the source of truth (the ERP is) and the two
-- are not connected. The UI shows a read-only "has dispatch history here" hint
-- beside the control, but the stored value is a human assertion.

alter table public.customers
  add column if not exists buyer_type     text null,
  add column if not exists crm_status     text not null default 'pending',
  add column if not exists assigned_to    uuid null references auth.users(id) on delete set null,
  add column if not exists has_reference  boolean not null default false,
  add column if not exists token_agreed   boolean not null default false,
  add column if not exists token_amount   numeric(12,2) null,
  add column if not exists crm_updated_at timestamptz null,
  add column if not exists crm_updated_by uuid null references auth.users(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'customers_buyer_type_check') then
    alter table public.customers
      add constraint customers_buyer_type_check
      check (buyer_type is null or buyer_type in ('new','old'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_crm_status_check') then
    alter table public.customers
      add constraint customers_crm_status_check
      check (crm_status in ('pending','on_hold','agreed','rejected'));
  end if;
end $$;

create index if not exists customers_crm_status_idx on public.customers(crm_status);
create index if not exists customers_assigned_to_idx on public.customers(assigned_to);

-- ── 2. CRM tables (RLS on, no policies → service-role only) ─────────────────

create table if not exists public.customer_references (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.customers(id) on delete cascade,
  reference_text text not null,
  created_by     uuid null,
  created_at     timestamptz not null default now()
);
create index if not exists customer_references_customer_idx on public.customer_references(customer_id);

create table if not exists public.customer_calls (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers(id) on delete cascade,
  called_by    uuid null,
  called_at    timestamptz not null default now(),
  outcome      text not null check (outcome in ('connected','no_answer','busy','wrong_number','callback')),
  notes        text not null default '',
  status_after text null check (status_after is null or status_after in ('pending','on_hold','agreed','rejected')),
  created_at   timestamptz not null default now()
);
create index if not exists customer_calls_customer_idx on public.customer_calls(customer_id, called_at desc);

create table if not exists public.customer_crm_log (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  actor_id    uuid null,
  field       text not null,
  old_value   text null,
  new_value   text null,
  created_at  timestamptz not null default now()
);
create index if not exists customer_crm_log_customer_idx on public.customer_crm_log(customer_id, created_at desc);

alter table public.customer_references enable row level security;
alter table public.customer_calls      enable row level security;
alter table public.customer_crm_log    enable row level security;
-- No policies on any of the three: customers must never read CRM data. Service
-- role (the admin-api Edge Function) only.

-- ── 3. CRM read RPC ─────────────────────────────────────────────────────────
-- Everyone with crm.view sees ALL customers in the current exhibition. "Mine"
-- is a CLIENT-SIDE filter on assignedTo — no server-side per-user row filtering.
-- Duplicate hints are keyed on canonical company name AND phone; the caller
-- decides, nothing is auto-merged.

create or replace function public.crm_list_customers(p_filters jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      nullif(btrim(coalesce(p_filters ->> 'search','')), '')               as q,
      nullif(btrim(coalesce(p_filters ->> 'buyerType','')), '')            as buyer_type,   -- 'unscreened' | 'new' | 'old'
      nullif(btrim(coalesce(p_filters ->> 'status','')), '')              as status,
      coalesce((p_filters ->> 'exhibitionId')::uuid, public.current_exhibition_id()) as exhibition_id,
      greatest(1, least(coalesce((p_filters ->> 'limit')::int, 500), 1000)) as lim
  ),
  scoped as (
    select c.*,
           regexp_replace(upper(coalesce(c.company_name,'')), '[^A-Z0-9]', '', 'g') as name_key
    from public.customers c, params p
    where c.active
      and c.exhibition_id = p.exhibition_id
  ),
  dupes as (
    select name_key, phone_e164,
           count(*) over (partition by name_key)   as name_n,
           count(*) over (partition by phone_e164)  as phone_n,
           id
    from scoped
  ),
  filtered as (
    select s.*
    from scoped s, params p
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
      'id', f.id,
      'companyName', f.company_name,
      'contactName', f.contact_name,
      'phone', f.phone_e164,
      'city', f.city,
      'state', f.state,
      'buyerType', f.buyer_type,
      'crmStatus', f.crm_status,
      'assignedTo', f.assigned_to,
      'assignedName', sp.staff_name,
      'hasReference', f.has_reference,
      'tokenAgreed', f.token_agreed,
      'tokenAmount', f.token_amount,
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

-- Full detail for one customer: CRM fields + call log (newest first) + references.
create or replace function public.crm_customer_detail(p_customer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', c.id,
    'companyName', c.company_name,
    'contactName', c.contact_name,
    'phone', c.phone_e164,
    'city', c.city,
    'state', c.state,
    'gstin', c.gstin,
    'buyerType', c.buyer_type,
    'crmStatus', c.crm_status,
    'assignedTo', c.assigned_to,
    'assignedName', (select sp.staff_name from public.staff_profiles sp where sp.auth_user_id = c.assigned_to),
    'hasReference', c.has_reference,
    'tokenAgreed', c.token_agreed,
    'tokenAmount', c.token_amount,
    'crmUpdatedAt', c.crm_updated_at,
    -- Read-only hint only; buyer_type is NOT derived from this (ERP is truth).
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
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'text', r.reference_text, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from public.customer_references r where r.customer_id = c.id
    ), '[]'::jsonb)
  )
  from public.customers c
  where c.id = p_customer_id;
$$;

-- ── 4. CRM write RPCs ───────────────────────────────────────────────────────
-- Each logs to customer_crm_log when a TRACKED field (crm_status, buyer_type,
-- assigned_to) actually changes.

create or replace function public.crm_set_buyer_type(p_customer_id uuid, p_buyer_type text, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_buyer_type,'')), '');
  if v_new is not null and v_new not in ('new','old') then raise exception 'INVALID_BUYER_TYPE'; end if;
  select buyer_type into v_old from public.customers where id = p_customer_id for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  update public.customers
    set buyer_type = v_new, crm_updated_at = now(), crm_updated_by = p_actor, updated_at = now()
    where id = p_customer_id;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'buyer_type', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.crm_assign(p_customer_id uuid, p_assigned_to uuid, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_old uuid;
begin
  if p_assigned_to is not null and not exists (select 1 from public.staff_profiles where auth_user_id = p_assigned_to) then
    raise exception 'ASSIGNEE_NOT_STAFF';
  end if;
  select assigned_to into v_old from public.customers where id = p_customer_id for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  update public.customers
    set assigned_to = p_assigned_to, crm_updated_at = now(), crm_updated_by = p_actor, updated_at = now()
    where id = p_customer_id;
  if v_old is distinct from p_assigned_to then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'assigned_to', v_old::text, p_assigned_to::text);
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.crm_set_status(p_customer_id uuid, p_status text, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_status,'')), '');
  if v_new is null or v_new not in ('pending','on_hold','agreed','rejected') then raise exception 'INVALID_STATUS'; end if;
  select crm_status into v_old from public.customers where id = p_customer_id for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  update public.customers
    set crm_status = v_new, crm_updated_at = now(), crm_updated_by = p_actor, updated_at = now()
    where id = p_customer_id;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'crm_status', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- Log a call AND update the customer in one transaction.
create or replace function public.crm_log_call(
  p_customer_id  uuid,
  p_outcome      text,
  p_notes        text,
  p_status_after text,
  p_has_reference boolean,
  p_token_agreed  boolean,
  p_token_amount  numeric,
  p_actor         uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_status     text;
  v_amount     numeric(12,2);
begin
  if p_outcome is null or p_outcome not in ('connected','no_answer','busy','wrong_number','callback') then
    raise exception 'INVALID_OUTCOME';
  end if;
  v_status := nullif(btrim(coalesce(p_status_after,'')), '');
  if v_status is not null and v_status not in ('pending','on_hold','agreed','rejected') then
    raise exception 'INVALID_STATUS';
  end if;
  if length(coalesce(p_notes,'')) > 4000 then raise exception 'NOTES_TOO_LONG'; end if;
  -- token_amount only meaningful when token_agreed; ignore an amount otherwise.
  v_amount := case when coalesce(p_token_agreed,false) then p_token_amount else null end;
  if v_amount is not null and (v_amount < 0 or v_amount > 99999999.99) then raise exception 'INVALID_TOKEN_AMOUNT'; end if;

  select crm_status into v_old_status from public.customers where id = p_customer_id for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  insert into public.customer_calls(customer_id, called_by, outcome, notes, status_after)
  values (p_customer_id, p_actor, p_outcome, coalesce(btrim(p_notes),''), v_status);

  update public.customers set
    has_reference  = coalesce(p_has_reference, has_reference),
    token_agreed   = coalesce(p_token_agreed, token_agreed),
    token_amount   = v_amount,
    crm_status     = coalesce(v_status, crm_status),
    crm_updated_at = now(),
    crm_updated_by = p_actor,
    updated_at     = now()
  where id = p_customer_id;

  if v_status is not null and v_status is distinct from v_old_status then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    values (p_customer_id, p_actor, 'crm_status', v_old_status, v_status);
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.crm_add_reference(p_customer_id uuid, p_reference_text text, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_text text; v_id uuid;
begin
  v_text := nullif(btrim(coalesce(p_reference_text,'')), '');
  if v_text is null then raise exception 'REFERENCE_TEXT_REQUIRED'; end if;
  if length(v_text) > 2000 then raise exception 'REFERENCE_TOO_LONG'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  insert into public.customer_references(customer_id, reference_text, created_by)
  values (p_customer_id, v_text, p_actor) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.crm_delete_reference(p_reference_id uuid, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.customer_references where id = p_reference_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── 5. Reception check-in flag ──────────────────────────────────────────────
-- admin_directory feeds the reception check-in screen. Add crmStatus so the
-- console can show a red "Flagged" banner. It is a FLAG, NOT A GATE — the
-- check-in button stays enabled (enforced client-side).

create or replace function public.admin_directory(
  p_query text default ''::text,
  p_limit integer default 400,
  p_exhibition_id uuid default null::uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with matched as (
    select
      c.id, c.phone_e164, c.company_name, c.contact_name, c.city, c.state,
      c.gstin, c.agent, c.active, c.checked_in_at, c.ordering_started_at,
      c.edit_deadline, c.created_at, c.crm_status,
      b.id booking_id, b.party_size, b.note booking_note,
      s.id slot_id, s.starts_at, s.ends_at, s.label slot_label
    from public.customers c
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
        'endsAt', m.ends_at, 'label', m.slot_label, 'partySize', m.party_size,
        'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$$;

-- ── 6. Grants — service-role only for every new/changed function ────────────

revoke all on function public.crm_list_customers(jsonb)                       from public, anon, authenticated;
grant  execute on function public.crm_list_customers(jsonb)                   to service_role;
revoke all on function public.crm_customer_detail(uuid)                       from public, anon, authenticated;
grant  execute on function public.crm_customer_detail(uuid)                   to service_role;
revoke all on function public.crm_set_buyer_type(uuid, text, uuid)           from public, anon, authenticated;
grant  execute on function public.crm_set_buyer_type(uuid, text, uuid)       to service_role;
revoke all on function public.crm_assign(uuid, uuid, uuid)                   from public, anon, authenticated;
grant  execute on function public.crm_assign(uuid, uuid, uuid)               to service_role;
revoke all on function public.crm_set_status(uuid, text, uuid)              from public, anon, authenticated;
grant  execute on function public.crm_set_status(uuid, text, uuid)          to service_role;
revoke all on function public.crm_log_call(uuid, text, text, text, boolean, boolean, numeric, uuid) from public, anon, authenticated;
grant  execute on function public.crm_log_call(uuid, text, text, text, boolean, boolean, numeric, uuid) to service_role;
revoke all on function public.crm_add_reference(uuid, text, uuid)           from public, anon, authenticated;
grant  execute on function public.crm_add_reference(uuid, text, uuid)       to service_role;
revoke all on function public.crm_delete_reference(uuid, uuid)              from public, anon, authenticated;
grant  execute on function public.crm_delete_reference(uuid, uuid)          to service_role;
-- admin_directory keeps its existing grant surface (service_role); re-assert it.
revoke all on function public.admin_directory(text, integer, uuid)          from public, anon, authenticated;
grant  execute on function public.admin_directory(text, integer, uuid)      to service_role;

-- ── 7. Permission module 'crm' (guardrail C3: update ALL five places) ───────
-- 1) both CHECK constraints, 2) staff_permission_defaults, 3) backfill.
-- admin-api (nav, TEAM_GROUPS/GROUPS, ACTION_PERMISSIONS, create/updateStaff
-- allowed lists) is the other two places, changed in the same checkpoint.

alter table public.staff_profiles drop constraint if exists staff_profiles_preset_check;
alter table public.staff_profiles
  add constraint staff_profiles_preset_check
  check (preset in ('sales','reception','products','dispatch','manager','administrator','custom','crm'));

alter table public.staff_profiles drop constraint if exists staff_profiles_default_section_check;
alter table public.staff_profiles
  add constraint staff_profiles_default_section_check
  check (default_section in ('reception','dashboard','sale','products','dispatch','admin','crm'));

-- Restate ALL presets. crm.assign is admin-tier (manager/administrator); the
-- 'crm' preset is a caller who screens buyers (view + write, never assign).
create or replace function public.staff_permission_defaults(p_preset text)
returns jsonb
language sql
immutable
as $$
  select case lower(coalesce(p_preset,''))
    when 'sales' then jsonb_build_object(
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,
      'reception.view',true
    )
    when 'reception' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'admin.bookings',true
    )
    when 'products' then jsonb_build_object(
      'products.view',true,'products.edit',true,'products.mapping',true
    )
    when 'dispatch' then jsonb_build_object(
      'dispatch.view',true,'dispatch.write',true,'sale.pdf',true
    )
    when 'crm' then jsonb_build_object(
      'crm.view',true,'crm.write',true
    )
    when 'manager' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'crm.view',true,'crm.write',true,'crm.assign',true,
      'admin.slots',true,'admin.bookings',true
    )
    when 'administrator' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'crm.view',true,'crm.write',true,'crm.assign',true,
      'admin.slots',true,'admin.bookings',true,'admin.staff',true,'admin.settings',true
    )
    else '{}'::jsonb
  end;
$$;

revoke all on function public.staff_permission_defaults(text) from public, anon, authenticated;
grant execute on function public.staff_permission_defaults(text) to service_role;

-- Backfill CRM keys to ADMINISTRATORS ONLY (never preset 'custom'). Everyone
-- else is granted crm.* individually through the existing staff screen — so
-- there is no name list to wait on and this does not block the rollout.
update public.staff_profiles
set permissions = permissions
      || jsonb_build_object('crm.view', true, 'crm.write', true, 'crm.assign', true),
    updated_at = now()
where preset = 'administrator';
