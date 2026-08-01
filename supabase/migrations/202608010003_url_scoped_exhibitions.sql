-- 202608010003_url_scoped_exhibitions.sql
-- Brief 3.5 (Phase 4): customer-facing functions resolve their exhibition from
-- the caller, not from is_current. See docs/MULTI_EXHIBITION_BLUEPRINT.md §5
-- (revised — "URL-scoped exhibitions").
--
-- Resolution model:
--   * Logged-in customer RPCs  -> the caller's OWN row (customers.exhibition_id
--     where id = auth.uid()); tamper-proof, a doctored URL cannot move them.
--   * lookup_barcode           -> customer-row FIRST, then p_exhibition_id (for
--     admin, which has no customers row), then current_exhibition_id(). The
--     customer-row-first order makes an authenticated customer's p_exhibition_id
--     INERT — it is granted to authenticated, so param-first would let a buyer
--     resolve another exhibition's stickers.
--   * Registration             -> the slug the registration was made against
--     (raw_user_meta_data.exhibition_slug), with a CONDITIONAL fallback.
--
-- is_current semantics are UNCHANGED: it remains the bare-URL / single-event
-- fallback via current_exhibition_id().
--
-- ============================ RECORDED / MUST DO ============================
-- admin_map_barcode and admin_deactivate_barcode STILL scope to
-- current_exhibition_id(). They are deliberately NOT changed here (admin path,
-- out of this brief). Consequence, stated plainly: until they take an explicit
-- exhibition id, admin barcode mapping/deactivation SILENTLY targets whichever
-- exhibition is is_current, regardless of any admin exhibition selector. They
-- MUST be scoped to a passed exhibition id BEFORE a second exhibition goes live,
-- or stickers will be mapped into the wrong event. Track with the admin-api brief.
-- ===========================================================================

begin;

-- 1. lookup_barcode: + p_exhibition_id (customer-row wins, then param, then
--    current). Return-type/signature change -> drop first. Re-grant.
drop function if exists public.lookup_barcode(text);
create or replace function public.lookup_barcode(p_barcode text, p_exhibition_id uuid default null)
 returns TABLE(barcode text, design_no text, firm text, category text, style text, fabric text, pcs_per_set integer, description text, color text)
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select
    bm.barcode, d.design_no, d.firm, d.category, d.style, d.fabric,
    d.pcs_per_set, d.description, d.color
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.exhibition_id = coalesce(
      (select c.exhibition_id from public.customers c where c.id = auth.uid()),
      p_exhibition_id,
      public.current_exhibition_id()
    )
    and bm.active = true
    and d.active = true
  limit 1;
$fn$;
revoke all on function public.lookup_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text, uuid) to authenticated, service_role;

-- 2. list_slots: the caller's own exhibition (fallback current for a bare call).
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
    and s.exhibition_id = coalesce(
      (select c.exhibition_id from public.customers c where c.id = auth.uid()),
      public.current_exhibition_id()
    );
$fn$;
revoke all on function public.list_slots() from public, anon, authenticated;
grant execute on function public.list_slots() to authenticated, service_role;

-- 3. book_slot: refuse a slot outside the caller's own exhibition.
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
    and exhibition_id = coalesce(
      (select c.exhibition_id from public.customers c where c.id = auth.uid()),
      public.current_exhibition_id()
    );
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

-- 4. handle_new_auth_user: stamp the exhibition the registration was made
--    against, resolved from raw_user_meta_data.exhibition_slug. HIGHEST-RISK
--    change in this migration — a mistake breaks all registration.
--    Fallback when no slug is CONDITIONAL: exactly one exhibition -> use it
--    silently; two or more -> raise EXHIBITION_SLUG_REQUIRED (loud beats
--    silent misrouting). Registration gate + access code now come from the
--    RESOLVED exhibition, not system_settings.
create or replace function public.handle_new_auth_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'auth', 'extensions'
as $fn$
declare
  v_settings public.system_settings%rowtype;
  v_exhibition public.exhibitions%rowtype;
  v_slug text;
  v_count integer;
  v_phone text;
  v_company text; v_contact text; v_city text; v_state text; v_gstin text; v_agent text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;
  -- Domain gate decides "is this a customer registration at all" — exhibition-
  -- independent, so it stays on the shared customer_email_domain.
  if split_part(lower(coalesce(new.email,'')),'@',2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164',''),'\D','','g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then raise exception 'INVALID_CUSTOMER_PHONE'; end if;

  v_slug := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'exhibition_slug','')), '');
  if v_slug is not null then
    select * into v_exhibition from public.exhibitions where slug = lower(v_slug);
    if not found then raise exception 'UNKNOWN_EXHIBITION_SLUG'; end if;
  else
    select count(*) into v_count from public.exhibitions;
    if v_count = 1 then
      select * into v_exhibition from public.exhibitions limit 1;
    elsif v_count = 0 then
      raise exception 'NO_EXHIBITION';
    else
      raise exception 'EXHIBITION_SLUG_REQUIRED';
    end if;
  end if;

  -- Email local part must be c<phone> (legacy/single-event) or c<phone>.<slug>.
  if split_part(lower(new.email),'@',1) not in ('c' || v_phone, 'c' || v_phone || '.' || lower(v_exhibition.slug)) then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if not v_exhibition.registration_enabled then raise exception 'REGISTRATION_CLOSED'; end if;

  if v_exhibition.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code','');
    if encode(extensions.digest(v_access_code,'sha256'),'hex') <> v_exhibition.registration_access_code_hash then
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
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin, v_agent, v_exhibition.id);

  insert into public.orders(customer_id, firm, status, exhibition_id)
  values (new.id,'Maitri','Draft',v_exhibition.id), (new.id,'Niharika','Draft',v_exhibition.id);

  return new;
end;
$fn$;

-- 5. get_my_carnival_bootstrap: include the customer's exhibition (name/dates/
--    slug) so the app can show which event they are in, post-login.
create or replace function public.get_my_carnival_bootstrap()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'auth'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_profile jsonb;
  v_exhibition jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select to_jsonb(c) into v_profile
  from public.customers c
  where c.id = v_uid;

  if v_profile is null then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  select jsonb_build_object(
    'slug', e.slug, 'name', e.name,
    'startDate', e.start_date, 'endDate', e.end_date
  )
  into v_exhibition
  from public.exhibitions e
  join public.customers c on c.exhibition_id = e.id
  where c.id = v_uid;

  return jsonb_build_object(
    'profile', v_profile,
    'exhibition', v_exhibition,
    'status', public.get_my_status(),
    'slots', public.list_slots(),
    'orders', jsonb_build_object(
      'Maitri', public.get_my_order_state('Maitri'),
      'Niharika', public.get_my_order_state('Niharika')
    )
  );
end;
$fn$;

commit;
