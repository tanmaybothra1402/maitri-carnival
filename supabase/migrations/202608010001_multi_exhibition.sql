-- 202608010001_multi_exhibition.sql
-- Multi-exhibition Phase 1 (schema + functions). Additive, ordered so nothing
-- breaks mid-way. See docs/MULTI_EXHIBITION_BLUEPRINT.md and docs/SETUP.md.
--
-- Ships together with Phase 2 (admin-api). The only server-side signature that
-- changes is admin_directory; the two dashboard functions gain a DEFAULTED
-- p_exhibition_id so the existing admin HTML keeps working until Phase 3.
--
-- DECISION TO CONFIRM BEFORE APPLY: the exhibition `slug` (below) is baked into
-- Phase 4 customer login emails (c<phone>.<slug>@...). The live event is
-- "Maitri × Niharika Office Exhibition"; the blueprint used 'carnival-2026'.

begin;

-- 1. exhibitions ------------------------------------------------------------
create table if not exists public.exhibitions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  start_date date not null,
  end_date date not null,
  registration_enabled boolean not null default true,
  registration_access_code_hash text,
  customer_email_domain text not null,
  edit_window_hours integer not null default 24 check (edit_window_hours between 1 and 240),
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Exactly one current exhibition. Enforced, not hoped for.
create unique index if not exists exhibitions_one_current
  on public.exhibitions(is_current) where is_current;

-- Service-role only (RLS also auto-enabled by the rls_auto_enable event trigger).
-- Customers/staff never read this table directly; they go through
-- current_exhibition_id() and the definer functions below.
alter table public.exhibitions enable row level security;

drop trigger if exists exhibitions_set_updated_at on public.exhibitions;
create trigger exhibitions_set_updated_at
  before update on public.exhibitions
  for each row execute function public.set_updated_at();

-- 2. Seed the current exhibition from the existing system_settings singleton.
--    system_settings stays in place, unused, for one release (rollback safety).
insert into public.exhibitions
  (slug, name, start_date, end_date, registration_enabled,
   registration_access_code_hash, customer_email_domain, edit_window_hours, is_current)
select
  'carnival-2026',                 -- slug: baked into Phase 4 login emails, confirmed
  'Maitri Carnival 2026',          -- system_settings.event_name is a stale template default; use the real event name
  s.event_start_date,
  s.event_end_date,
  s.registration_enabled,
  s.registration_access_code_hash,
  s.customer_email_domain,
  s.edit_window_hours,
  true
from public.system_settings s
where s.singleton = true
on conflict (slug) do nothing;

-- 3. exhibition_id columns, nullable first ----------------------------------
alter table public.customers        add column if not exists exhibition_id uuid;
alter table public.slots            add column if not exists exhibition_id uuid;
alter table public.barcode_mappings add column if not exists exhibition_id uuid;
alter table public.orders           add column if not exists exhibition_id uuid;

-- 4. Backfill every existing row to the seeded current exhibition -----------
update public.customers
  set exhibition_id = (select id from public.exhibitions where is_current)
  where exhibition_id is null;

update public.slots
  set exhibition_id = (select id from public.exhibitions where is_current)
  where exhibition_id is null;

update public.barcode_mappings
  set exhibition_id = (select id from public.exhibitions where is_current)
  where exhibition_id is null;

-- orders.exhibition_id is denormalised FROM THE CUSTOMER, per the blueprint.
update public.orders o
  set exhibition_id = c.exhibition_id
  from public.customers c
  where o.customer_id = c.id and o.exhibition_id is null;

-- 5. Enforce NOT NULL + FKs + indexes.
--    SET NOT NULL fails loudly here if the backfill missed any row — that is
--    the intended behaviour (see blueprint §7 risk table). Do not soften it.
alter table public.customers        alter column exhibition_id set not null;
alter table public.slots            alter column exhibition_id set not null;
alter table public.barcode_mappings alter column exhibition_id set not null;
alter table public.orders           alter column exhibition_id set not null;

alter table public.customers        drop constraint if exists customers_exhibition_id_fkey;
alter table public.customers        add  constraint customers_exhibition_id_fkey
  foreign key (exhibition_id) references public.exhibitions(id) on delete restrict;
alter table public.slots            drop constraint if exists slots_exhibition_id_fkey;
alter table public.slots            add  constraint slots_exhibition_id_fkey
  foreign key (exhibition_id) references public.exhibitions(id) on delete restrict;
alter table public.barcode_mappings drop constraint if exists barcode_mappings_exhibition_id_fkey;
alter table public.barcode_mappings add  constraint barcode_mappings_exhibition_id_fkey
  foreign key (exhibition_id) references public.exhibitions(id) on delete restrict;
alter table public.orders           drop constraint if exists orders_exhibition_id_fkey;
alter table public.orders           add  constraint orders_exhibition_id_fkey
  foreign key (exhibition_id) references public.exhibitions(id) on delete restrict;

create index if not exists customers_exhibition_id_idx        on public.customers(exhibition_id);
create index if not exists slots_exhibition_id_idx            on public.slots(exhibition_id);
create index if not exists barcode_mappings_exhibition_id_idx on public.barcode_mappings(exhibition_id);
create index if not exists orders_exhibition_id_idx           on public.orders(exhibition_id);

-- 6. Uniqueness / PK re-scoped to the exhibition ----------------------------
-- A returning buyer is a different customer ROW in the new exhibition, so
-- orders unique(customer_id, firm) stays correct untouched.
alter table public.customers drop constraint if exists customers_phone_e164_key;
alter table public.customers drop constraint if exists customers_phone_e164_exhibition_id_key;
alter table public.customers add  constraint customers_phone_e164_exhibition_id_key
  unique (phone_e164, exhibition_id);

alter table public.barcode_mappings drop constraint if exists barcode_mappings_pkey;
alter table public.barcode_mappings add  constraint barcode_mappings_pkey
  primary key (barcode, exhibition_id);

-- 7. Functions --------------------------------------------------------------

-- 7.0a Drop the legacy 5-arg admin_dashboard. It is unused (no client caller,
--      no internal dependent) and it aggregates with NO exhibition filter — if
--      revived it would silently mix exhibitions. Dead code that ignores
--      scoping is a landmine; remove it rather than leave it.
drop function if exists public.admin_dashboard(jsonb, text, text, integer, integer);

-- 7.0 Single source of truth for "which exhibition is live right now".
create or replace function public.current_exhibition_id()
 returns uuid
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select id from public.exhibitions where is_current limit 1;
$fn$;
revoke all on function public.current_exhibition_id() from public, anon, authenticated;
grant execute on function public.current_exhibition_id() to authenticated, service_role;

-- 7.1 Registration trigger: stamp the current exhibition on the customer AND
--     both order rows it creates. Without this, the NOT NULL columns above
--     reject the next registration. (Email-scheme change is Phase 4.)
create or replace function public.handle_new_auth_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'auth', 'extensions'
as $fn$
declare
  v_settings public.system_settings%rowtype;
  v_exhibition uuid;
  v_phone text;
  v_company text; v_contact text; v_city text; v_state text; v_gstin text; v_agent text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;
  if split_part(lower(coalesce(new.email,'')),'@',2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;
  if not v_settings.registration_enabled then raise exception 'REGISTRATION_CLOSED'; end if;

  v_exhibition := public.current_exhibition_id();
  if v_exhibition is null then raise exception 'NO_CURRENT_EXHIBITION'; end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164',''),'\D','','g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then raise exception 'INVALID_CUSTOMER_PHONE'; end if;
  if split_part(lower(new.email),'@',1) <> ('c' || v_phone) then raise exception 'PHONE_EMAIL_MISMATCH'; end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code','');
    if encode(extensions.digest(v_access_code,'sha256'),'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name',''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name',''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city',''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state',''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin','')));
  v_agent := btrim(coalesce(new.raw_user_meta_data ->> 'agent',''));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin, agent, exhibition_id)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin, v_agent, v_exhibition);

  insert into public.orders(customer_id, firm, status, exhibition_id)
  values (new.id,'Maitri','Draft',v_exhibition), (new.id,'Niharika','Draft',v_exhibition);

  return new;
end;
$fn$;

-- 7.2 _write_order: unchanged EXCEPT the edit-window source is now the
--     customer's exhibition, not system_settings. Everything else is byte-for-
--     byte the current definition. (Verified by diff against the live DB.)
create or replace function public._write_order(p_customer_id uuid, p_firm text, p_base_version integer, p_items jsonb, p_request_id uuid, p_is_admin boolean)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_edit_window_hours integer;
  v_customer public.customers%rowtype;
  v_order public.orders%rowtype;
  v_existing public.order_save_requests%rowtype;
  v_item jsonb;
  v_design public.designs%rowtype;
  v_design_no text;
  v_barcode text;
  v_note text;
  v_qty integer;
  v_is_delete boolean;
  v_seen text[] := array[]::text[];
  v_delete_seen text[] := array[]::text[];
  v_normalized jsonb := '[]'::jsonb;
  v_operation_count integer := 0;
  v_design_count integer := 0;
  v_total_sets integer := 0;
  v_total_pieces integer := 0;
  v_new_version integer;
  v_response jsonb;
  v_was_merged boolean := false;
  v_operation_mode boolean := false;
  v_existing_qty integer;
begin
  if p_customer_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then raise exception 'ITEMS_MUST_BE_AN_ARRAY'; end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 1000 then raise exception 'TOO_MANY_ORDER_OPERATIONS'; end if;

  select exists(
    select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x(value)
    where x.value ? '_op' or x.value ? '_delete' or x.value ? 'delete'
  ) into v_operation_mode;

  select * into v_existing from public.order_save_requests where request_id = p_request_id;
  if found then
    if v_existing.customer_id <> p_customer_id then raise exception 'REQUEST_ID_OWNERSHIP_ERROR'; end if;
    return v_existing.response_json;
  end if;

  select * into v_customer from public.customers where id = p_customer_id;
  if not found or not v_customer.active then raise exception 'CUSTOMER_ACCESS_DISABLED'; end if;

  -- Edit window comes from the customer's exhibition (was: system_settings).
  select edit_window_hours into v_edit_window_hours
  from public.exhibitions where id = v_customer.exhibition_id;

  if not p_is_admin and v_customer.checked_in_at is null then raise exception 'NOT_CHECKED_IN'; end if;

  select * into v_order from public.orders where customer_id = p_customer_id and firm = p_firm for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if not p_is_admin then
    if v_order.status = 'Locked' and not v_order.admin_unlocked then raise exception 'ORDER_LOCKED'; end if;
    if v_customer.edit_deadline is not null and now() > v_customer.edit_deadline and not v_order.admin_unlocked then
      raise exception 'EDIT_WINDOW_CLOSED';
    end if;
    v_was_merged := coalesce(p_base_version, 0) <> v_order.version;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_item ->> 'designNo', v_item ->> 'design_no', ''));
    v_is_delete := lower(btrim(coalesce(v_item ->> '_delete', v_item ->> 'delete', 'false'))) in ('true','1','yes');
    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;

    if v_is_delete then
      if v_design_no = any(v_delete_seen) then continue; end if;
      -- Dispatched lines cannot be removed. Undispatch first.
      if public.is_design_dispatched(v_order.id, v_design_no) then
        raise exception 'DESIGN_DISPATCHED_%', v_design_no;
      end if;
      v_delete_seen := array_append(v_delete_seen, v_design_no);
      v_operation_count := v_operation_count + 1;
      continue;
    end if;

    v_barcode := btrim(coalesce(v_item ->> 'barcode', ''));
    v_note := btrim(coalesce(v_item ->> 'note', v_item ->> 'lineNote', v_item ->> 'line_note', ''));
    if length(v_note) > 500 then raise exception 'NOTE_TOO_LONG_FOR_%', v_design_no; end if;

    begin
      v_qty := (v_item ->> 'qty')::integer;
    exception when others then
      raise exception 'INVALID_QUANTITY_FOR_%', v_design_no;
    end;
    if v_qty < 1 or v_qty > 9999 then raise exception 'INVALID_QUANTITY_FOR_%', v_design_no; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_%', v_design_no; end if;

    -- A dispatched line is frozen. Re-sending it unchanged is tolerated so
    -- that a full-cart save from a stale client does not fail outright.
    if public.is_design_dispatched(v_order.id, v_design_no) then
      select qty into v_existing_qty
      from public.order_items
      where order_id = v_order.id and design_no = v_design_no;
      if coalesce(v_existing_qty, -1) <> v_qty then
        raise exception 'DESIGN_DISPATCHED_%', v_design_no;
      end if;
    end if;

    select * into v_design from public.designs where design_no = v_design_no and active = true;
    if not found then raise exception 'INACTIVE_OR_UNKNOWN_DESIGN_%', v_design_no; end if;
    if v_design.firm not in (p_firm, 'Both') then raise exception 'DESIGN_%_DOES_NOT_BELONG_TO_%', v_design_no, p_firm; end if;

    v_seen := array_append(v_seen, v_design_no);
    v_operation_count := v_operation_count + 1;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'barcode', v_barcode,
      'designNo', v_design.design_no,
      'qty', v_qty,
      'category', v_design.category,
      'style', v_design.style,
      'fabric', v_design.fabric,
      'pcsPerSet', v_design.pcs_per_set,
      'note', v_note,
      'color', v_design.color,
      'description', v_design.description
    ));
  end loop;

  if array_length(v_delete_seen, 1) is not null then
    delete from public.order_items
    where order_id = v_order.id and design_no = any(v_delete_seen);
  end if;

  -- Legacy full-cart replacement. Dispatched designs are excluded so a stale
  -- client that omits them cannot silently delete goods already shipped.
  if not v_operation_mode and (p_is_admin or not v_was_merged) then
    delete from public.order_items
    where order_id = v_order.id
      and not (design_no = any(v_seen))
      and not public.is_design_dispatched(v_order.id, design_no);
  end if;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into public.order_items(
      order_id, barcode, design_no, qty,
      category_snapshot, style_snapshot, fabric_snapshot, pcs_per_set_snapshot,
      line_note, color_snapshot, description_snapshot
    ) values (
      v_order.id,
      coalesce(v_item ->> 'barcode', ''),
      v_item ->> 'designNo',
      (v_item ->> 'qty')::integer,
      coalesce(v_item ->> 'category', ''),
      coalesce(v_item ->> 'style', ''),
      coalesce(v_item ->> 'fabric', ''),
      (v_item ->> 'pcsPerSet')::integer,
      coalesce(v_item ->> 'note', ''),
      coalesce(v_item ->> 'color', ''),
      coalesce(v_item ->> 'description', '')
    )
    on conflict (order_id, design_no) do update set
      barcode = excluded.barcode,
      qty = excluded.qty,
      category_snapshot = excluded.category_snapshot,
      style_snapshot = excluded.style_snapshot,
      fabric_snapshot = excluded.fabric_snapshot,
      pcs_per_set_snapshot = excluded.pcs_per_set_snapshot,
      line_note = excluded.line_note,
      color_snapshot = excluded.color_snapshot,
      description_snapshot = excluded.description_snapshot,
      updated_at = now();
  end loop;

  select count(*)::integer,
         coalesce(sum(qty),0)::integer,
         coalesce(sum(qty * pcs_per_set_snapshot),0)::integer
  into v_design_count, v_total_sets, v_total_pieces
  from public.order_items where order_id = v_order.id;

  if v_operation_count = 0 then
    v_new_version := v_order.version;
  else
    v_new_version := v_order.version + 1;
    update public.orders
    set status = case when v_design_count = 0 then 'Draft' else 'Saved' end,
        total_designs = v_design_count,
        total_sets = v_total_sets,
        total_pieces = v_total_pieces,
        version = v_new_version,
        updated_at = now()
    where id = v_order.id;

    if v_customer.ordering_started_at is null then
      update public.customers
      set ordering_started_at = now(),
          edit_deadline = now() + make_interval(hours => v_edit_window_hours),
          updated_at = now()
      where id = p_customer_id;
    end if;

    perform public.recompute_dispatch_status(v_order.id);
  end if;

  v_response := jsonb_build_object(
    'ok', true,
    'code', case when v_operation_count = 0 then 'NO_CHANGES' when v_was_merged then 'MERGED' else 'SAVED' end,
    'message', case
      when v_operation_count = 0 then 'No order changes to save.'
      when v_was_merged then 'Your changes were merged with the latest order.'
      when p_is_admin then 'Order saved by staff.'
      else 'Order saved.'
    end,
    'order', public.order_state_json(v_order.id)
  );

  insert into public.order_save_requests(
    request_id, order_id, customer_id, previous_version, new_version,
    design_count, total_sets, total_pieces, result, response_json
  ) values (
    p_request_id, v_order.id, p_customer_id, v_order.version, v_new_version,
    v_design_count, v_total_sets, v_total_pieces, 'Success', v_response
  );

  return v_response;
end;
$fn$;
revoke all on function public._write_order(uuid, text, integer, jsonb, uuid, boolean) from public, anon, authenticated;
grant execute on function public._write_order(uuid, text, integer, jsonb, uuid, boolean) to service_role;

-- 7.3 lookup_barcode: scope to the CURRENT exhibition. A leftover sticker from
--     a past exhibition must not resolve. This is the single most important
--     functional change in the migration.
create or replace function public.lookup_barcode(p_barcode text)
 returns TABLE(barcode text, design_no text, firm text, image_key text, category text, style text, fabric text, pcs_per_set integer, description text, color text)
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.design_no as image_key,
    d.category,
    d.style,
    d.fabric,
    d.pcs_per_set,
    d.description,
    d.color
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.exhibition_id = public.current_exhibition_id()
    and bm.active = true
    and d.active = true
  limit 1;
$fn$;
revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated, service_role;

-- 7.4 list_slots: current exhibition only.
create or replace function public.list_slots()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'startsAt', s.starts_at,
      'endsAt', s.ends_at,
      'label', s.label,
      'capacity', s.capacity,
      'booked', coalesce(b.cnt, 0),
      'full', s.capacity is not null and coalesce(b.cnt, 0) >= s.capacity
    ) order by s.starts_at
  ), '[]'::jsonb)
  from public.slots s
  left join (
    select slot_id, count(*) cnt
    from public.bookings
    where status = 'Booked'
    group by slot_id
  ) b on b.slot_id = s.id
  where s.active = true
    and s.exhibition_id = public.current_exhibition_id();
$fn$;
revoke all on function public.list_slots() from public, anon, authenticated;
grant execute on function public.list_slots() to authenticated, service_role;

-- 7.5 book_slot: refuse to book a slot outside the current exhibition.
create or replace function public.book_slot(p_slot_id uuid, p_party_size integer, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_slot public.slots%rowtype;
  v_count integer;
  v_party integer := greatest(1, least(99, coalesce(p_party_size, 1)));
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_slot from public.slots
  where id = p_slot_id and active = true
    and exhibition_id = public.current_exhibition_id();
  if not found then raise exception 'SLOT_NOT_FOUND'; end if;

  if v_slot.capacity is not null then
    select count(*) into v_count
    from public.bookings
    where slot_id = p_slot_id and status = 'Booked' and customer_id <> auth.uid();
    if v_count >= v_slot.capacity then raise exception 'SLOT_FULL'; end if;
  end if;

  insert into public.bookings(customer_id, slot_id, party_size, note, status)
  values (auth.uid(), p_slot_id, v_party, btrim(coalesce(p_note, '')), 'Booked')
  on conflict (customer_id) do update
    set slot_id = excluded.slot_id,
        party_size = excluded.party_size,
        note = excluded.note,
        status = 'Booked',
        updated_at = now();

  return jsonb_build_object('ok', true, 'slotId', p_slot_id, 'partySize', v_party);
end;
$fn$;
revoke all on function public.book_slot(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.book_slot(uuid, integer, text) to authenticated, service_role;

-- 7.6 admin_map_barcode: mappings are scoped by (barcode, exhibition_id). Map
--     within the current exhibition; the ALREADY_MAPPED guard is now per-event.
create or replace function public.admin_map_barcode(p_barcode text, p_design_no text, p_admin_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_barcode text := btrim(coalesce(p_barcode, ''));
  v_design_no text := btrim(coalesce(p_design_no, ''));
  v_exhibition uuid := public.current_exhibition_id();
  v_existing public.barcode_mappings%rowtype;
  v_action text;
begin
  if v_barcode = '' then raise exception 'BARCODE_REQUIRED'; end if;
  if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
  if v_exhibition is null then raise exception 'NO_CURRENT_EXHIBITION'; end if;
  if not exists (select 1 from public.designs where design_no = v_design_no and active = true) then
    raise exception 'ACTIVE_DESIGN_NOT_FOUND';
  end if;

  select * into v_existing from public.barcode_mappings
  where barcode = v_barcode and exhibition_id = v_exhibition for update;

  if found then
    -- Blocked: live mapping pointing somewhere else.
    if v_existing.active and v_existing.design_no <> v_design_no then
      raise exception 'BARCODE_ALREADY_MAPPED|%|%', v_barcode, v_existing.design_no;
    end if;

    if v_existing.active and v_existing.design_no = v_design_no then
      v_action := 'Unchanged';
    elsif not v_existing.active and v_existing.design_no = v_design_no then
      v_action := 'Reactivated';
    else
      v_action := 'Remapped';
    end if;

    if v_action <> 'Unchanged' then
      update public.barcode_mappings
      set design_no = v_design_no, active = true, mapped_by = p_admin_user_id, updated_at = now()
      where barcode = v_barcode and exhibition_id = v_exhibition;
    end if;
  else
    v_action := 'Created';
    insert into public.barcode_mappings(barcode, design_no, mapped_by, exhibition_id)
    values (v_barcode, v_design_no, p_admin_user_id, v_exhibition);
  end if;

  if v_action <> 'Unchanged' then
    insert into public.barcode_mapping_log(
      barcode, previous_design_no, new_design_no, action, admin_user_id
    ) values (
      v_barcode,
      case when v_existing.barcode is null then null else v_existing.design_no end,
      v_design_no,
      v_action,
      p_admin_user_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'barcode', v_barcode,
    'designNo', v_design_no,
    'action', v_action
  );
end;
$fn$;
revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;

-- 7.7 admin_deactivate_barcode: scoped to the current exhibition's mapping.
create or replace function public.admin_deactivate_barcode(p_barcode text, p_admin_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_exhibition uuid := public.current_exhibition_id();
  v_row public.barcode_mappings%rowtype;
begin
  select * into v_row from public.barcode_mappings
  where barcode = btrim(p_barcode) and exhibition_id = v_exhibition for update;
  if not found then raise exception 'BARCODE_NOT_FOUND'; end if;

  update public.barcode_mappings set active = false, mapped_by = p_admin_user_id, updated_at = now()
  where barcode = v_row.barcode and exhibition_id = v_row.exhibition_id;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (v_row.barcode, v_row.design_no, v_row.design_no, 'Deactivated', p_admin_user_id);

  return jsonb_build_object('barcode', v_row.barcode, 'designNo', v_row.design_no, 'active', false);
end;
$fn$;
revoke all on function public.admin_deactivate_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.admin_deactivate_barcode(text, uuid) to service_role;

-- 7.8 admin_directory: + p_exhibition_id (defaults to current). SIGNATURE
--     CHANGE — drop the 2-arg version first. Caller: admin-api (Phase 2).
drop function if exists public.admin_directory(text, integer);
create or replace function public.admin_directory(p_query text default ''::text, p_limit integer default 400, p_exhibition_id uuid default null)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  with matched as (
    select
      c.id,
      c.phone_e164,
      c.company_name,
      c.contact_name,
      c.city,
      c.state,
      c.gstin,
      c.agent,
      c.active,
      c.checked_in_at,
      c.ordering_started_at,
      c.edit_deadline,
      c.created_at,
      b.id booking_id,
      b.party_size,
      b.note booking_note,
      s.id slot_id,
      s.starts_at,
      s.ends_at,
      s.label slot_label
    from public.customers c
    left join lateral (
      select bx.*
      from public.bookings bx
      where bx.customer_id = c.id and bx.status = 'Booked'
      order by bx.updated_at desc
      limit 1
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
      'id', m.id,
      'phone', m.phone_e164,
      'companyName', m.company_name,
      'contactName', m.contact_name,
      'city', m.city,
      'state', m.state,
      'gstin', m.gstin,
      'agent', m.agent,
      'active', m.active,
      'checkedInAt', m.checked_in_at,
      'orderingStartedAt', m.ordering_started_at,
      'editDeadline', m.edit_deadline,
      'booking', case when m.booking_id is null then null else jsonb_build_object(
        'id', m.booking_id,
        'slotId', m.slot_id,
        'startsAt', m.starts_at,
        'endsAt', m.ends_at,
        'label', m.slot_label,
        'partySize', m.party_size,
        'note', m.booking_note
      ) end
    ) order by m.created_at desc
  ), '[]'::jsonb)
  from matched m;
$fn$;
revoke all on function public.admin_directory(text, integer, uuid) from public, anon, authenticated;
grant execute on function public.admin_directory(text, integer, uuid) to service_role;

-- 7.9 admin_dashboard_v2: + p_exhibition_id (defaults to current). SIGNATURE
--     CHANGE. Callers are the admin HTML (Phase 3); the default keeps them
--     working now. Facts AND the global customer/booking counts are scoped.
drop function if exists public.admin_dashboard_v2(jsonb, text, integer, integer);
create or replace function public.admin_dashboard_v2(p_filters jsonb default '{}'::jsonb, p_search text default ''::text, p_limit integer default 100, p_offset integer default 0, p_exhibition_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'auth'
as $fn$
declare
  v_search text := '%' || btrim(coalesce(p_search,'')) || '%';
  v_exhibition uuid := coalesce(p_exhibition_id, public.current_exhibition_id());
  v_summary jsonb;
  v_charts jsonb;
  v_orders jsonb;
  v_total_orders integer;
  v_options jsonb;
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
    c.checked_in_at
  from public.order_items i
  join public.orders o on o.id=i.order_id
  join public.customers c on c.id=o.customer_id
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
    'customers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select customer_id::text id,company_name label,sum(pieces)::int value,sum(sets)::int sets,count(distinct design_no)::int designs,count(distinct order_id)::int orders,min(city) city,min(state) state,min(agent) agent from _dash_facts group by customer_id,company_name order by sum(pieces) desc limit 100)x),
    'source', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select source label,sum(pieces)::int value from _dash_facts group by source order by sum(pieces) desc limit 100)x)
  ) into v_charts;

  select count(*) into v_total_orders from (select distinct order_id from _dash_facts) q;
  select coalesce(jsonb_agg(x order by x."updatedAt" desc),'[]'::jsonb) into v_orders from (
    select order_id::text "orderId",customer_id::text "customerId",min(company_name) "companyName",min(contact_name) "contactName",
      min(phone_e164) phone,min(city) city,min(state) state,min(agent) agent,min(firm) firm,min(status) status,
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
$fn$;
revoke all on function public.admin_dashboard_v2(jsonb, text, integer, integer, uuid) from public, anon, authenticated;
grant execute on function public.admin_dashboard_v2(jsonb, text, integer, integer, uuid) to authenticated, service_role;

-- 7.10 admin_dashboard_drill_v1: + p_exhibition_id (defaults to current).
--      SIGNATURE CHANGE. Facts scoped by o.exhibition_id.
drop function if exists public.admin_dashboard_drill_v1(text, text, jsonb, text);
create or replace function public.admin_dashboard_drill_v1(p_dimension text, p_value text, p_filters jsonb default '{}'::jsonb, p_search text default ''::text, p_exhibition_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'auth'
as $fn$
declare
  v_search text := '%' || btrim(coalesce(p_search, '')) || '%';
  v_exhibition uuid := coalesce(p_exhibition_id, public.current_exhibition_id());
  v_summary jsonb;
  v_customers jsonb;
  v_designs jsonb;
begin
  if not public.staff_has_permission(auth.uid(), 'dashboard.view') then
    raise exception 'PERMISSION_DENIED';
  end if;

  if p_dimension not in (
    'designNo',
    'companyName',
    'firm',
    'state',
    'city',
    'agent',
    'category',
    'style',
    'fabric',
    'source'
  ) then
    raise exception 'INVALID_DASHBOARD_DIMENSION';
  end if;

  drop table if exists pg_temp._dashboard_drill_facts;

  create temporary table _dashboard_drill_facts
  on commit drop
  as
  select
    o.id as order_id,
    o.customer_id,
    o.firm,
    o.status,
    o.updated_at,

    i.design_no,
    i.qty as sets,
    i.qty * i.pcs_per_set_snapshot as pieces,

    coalesce(
      nullif(btrim(i.category_snapshot), ''),
      'Not specified'
    ) as category,

    coalesce(
      nullif(btrim(i.style_snapshot), ''),
      'Not specified'
    ) as style,

    coalesce(
      nullif(btrim(i.fabric_snapshot), ''),
      'Not specified'
    ) as fabric,

    coalesce(
      nullif(btrim(i.last_modified_by_type), ''),
      'unknown'
    ) as source,

    c.company_name,
    c.contact_name,
    c.phone_e164,

    coalesce(
      nullif(btrim(c.city), ''),
      'Not specified'
    ) as city,

    coalesce(
      nullif(btrim(c.state), ''),
      'Not specified'
    ) as state,

    coalesce(
      nullif(btrim(c.agent), ''),
      'Not specified'
    ) as agent,

    c.checked_in_at

  from public.order_items i
  join public.orders o
    on o.id = i.order_id
  join public.customers c
    on c.id = o.customer_id

  where
    o.exhibition_id = v_exhibition

    and (
      not (p_filters ? 'firm')
      or o.firm = any(
        select jsonb_array_elements_text(p_filters -> 'firm')
      )
    )

    and (
      not (p_filters ? 'state')
      or coalesce(
        nullif(btrim(c.state), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'state')
      )
    )

    and (
      not (p_filters ? 'city')
      or coalesce(
        nullif(btrim(c.city), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'city')
      )
    )

    and (
      not (p_filters ? 'agent')
      or coalesce(
        nullif(btrim(c.agent), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'agent')
      )
    )

    and (
      not (p_filters ? 'category')
      or coalesce(
        nullif(btrim(i.category_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'category')
      )
    )

    and (
      not (p_filters ? 'style')
      or coalesce(
        nullif(btrim(i.style_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'style')
      )
    )

    and (
      not (p_filters ? 'fabric')
      or coalesce(
        nullif(btrim(i.fabric_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'fabric')
      )
    )

    and (
      not (p_filters ? 'designNo')
      or i.design_no = any(
        select jsonb_array_elements_text(p_filters -> 'designNo')
      )
    )

    and (
      not (p_filters ? 'companyName')
      or c.company_name = any(
        select jsonb_array_elements_text(
          p_filters -> 'companyName'
        )
      )
    )

    and (
      not (p_filters ? 'status')
      or o.status = any(
        select jsonb_array_elements_text(p_filters -> 'status')
      )
    )

    and (
      not (p_filters ? 'source')
      or coalesce(
        nullif(btrim(i.last_modified_by_type), ''),
        'unknown'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'source')
      )
    )

    and (
      not (p_filters ? 'checkedIn')
      or (
        case
          when c.checked_in_at is null then 'No'
          else 'Yes'
        end
      ) = any(
        select jsonb_array_elements_text(
          p_filters -> 'checkedIn'
        )
      )
    )

    and (
      not (p_filters ? 'dateFrom')
      or o.updated_at >=
        ((p_filters -> 'dateFrom' ->> 0)::date)::timestamptz
    )

    and (
      not (p_filters ? 'dateTo')
      or o.updated_at <
        (
          ((p_filters -> 'dateTo' ->> 0)::date + 1)
        )::timestamptz
    )

    and (
      btrim(coalesce(p_search, '')) = ''
      or c.company_name ilike v_search
      or c.contact_name ilike v_search
      or c.phone_e164 ilike v_search
      or i.design_no ilike v_search
    )

    and (
      case p_dimension
        when 'designNo' then
          i.design_no = p_value

        when 'companyName' then
          c.company_name = p_value

        when 'firm' then
          o.firm = p_value

        when 'state' then
          coalesce(
            nullif(btrim(c.state), ''),
            'Not specified'
          ) = p_value

        when 'city' then
          coalesce(
            nullif(btrim(c.city), ''),
            'Not specified'
          ) = p_value

        when 'agent' then
          coalesce(
            nullif(btrim(c.agent), ''),
            'Not specified'
          ) = p_value

        when 'category' then
          coalesce(
            nullif(btrim(i.category_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'style' then
          coalesce(
            nullif(btrim(i.style_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'fabric' then
          coalesce(
            nullif(btrim(i.fabric_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'source' then
          coalesce(
            nullif(btrim(i.last_modified_by_type), ''),
            'unknown'
          ) = p_value

        else false
      end
    );

  select jsonb_build_object(
    'pieces',
      coalesce(sum(pieces), 0)::integer,

    'sets',
      coalesce(sum(sets), 0)::integer,

    'customers',
      count(distinct customer_id)::integer,

    'designs',
      count(distinct design_no)::integer,

    'orders',
      count(distinct order_id)::integer
  )
  into v_summary
  from _dashboard_drill_facts;

  select coalesce(
    jsonb_agg(
      to_jsonb(x)
      order by x.pieces desc, x."companyName"
    ),
    '[]'::jsonb
  )
  into v_customers
  from (
    select
      customer_id::text as "customerId",
      company_name as "companyName",
      min(contact_name) as "contactName",
      min(phone_e164) as phone,
      min(city) as city,
      min(state) as state,
      min(agent) as agent,
      sum(sets)::integer as sets,
      sum(pieces)::integer as pieces,
      count(distinct design_no)::integer as designs,
      count(distinct order_id)::integer as orders
    from _dashboard_drill_facts
    group by customer_id, company_name
  ) x;

  select coalesce(
    jsonb_agg(
      to_jsonb(x)
      order by x.pieces desc, x."designNo"
    ),
    '[]'::jsonb
  )
  into v_designs
  from (
    select
      design_no as "designNo",
      min(firm) as firm,
      min(category) as category,
      min(style) as style,
      min(fabric) as fabric,
      sum(sets)::integer as sets,
      sum(pieces)::integer as pieces,
      count(distinct customer_id)::integer as customers,
      count(distinct order_id)::integer as orders
    from _dashboard_drill_facts
    group by design_no
  ) x;

  return jsonb_build_object(
    'dimension', p_dimension,
    'label', p_value,
    'summary', v_summary,
    'customerDetails', v_customers,
    'designDetails', v_designs
  );
end;
$fn$;
revoke all on function public.admin_dashboard_drill_v1(text, text, jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_dashboard_drill_v1(text, text, jsonb, text, uuid) to authenticated, service_role;

-- 7.11 Lock the slug once an exhibition has customers. The slug is baked
--      permanently into customer login emails (c<phone>.<slug>@...); renaming it
--      later would orphan every login. Block it at the database, not in the UI.
create or replace function public.guard_exhibition_slug()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
begin
  if new.slug is distinct from old.slug
     and exists (select 1 from public.customers where exhibition_id = old.id) then
    raise exception
      'EXHIBITION_SLUG_LOCKED: exhibition % has customers; its slug is baked into login emails and cannot be changed',
      old.slug;
  end if;
  return new;
end;
$fn$;
revoke all on function public.guard_exhibition_slug() from public, anon, authenticated;

drop trigger if exists exhibitions_guard_slug on public.exhibitions;
create trigger exhibitions_guard_slug
  before update on public.exhibitions
  for each row execute function public.guard_exhibition_slug();

commit;
