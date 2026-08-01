-- 202608010005_admin_exhibition_rpcs.sql
-- Brief 3.6 piece 2 support: RPCs the admin-api exhibition actions need, plus a
-- durable note on lookup_barcode's staff-vs-customer assumption.

begin;

-- admin_list_exhibitions: every exhibition with per-exhibition counts, current
-- first. Read-only; used by the Admin -> Exhibitions screen.
create or replace function public.admin_list_exhibitions()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'slug', e.slug,
    'name', e.name,
    'startDate', e.start_date,
    'endDate', e.end_date,
    'editWindowHours', e.edit_window_hours,
    'registrationEnabled', e.registration_enabled,
    'isCurrent', e.is_current,
    'customers', (select count(*) from public.customers c where c.exhibition_id = e.id),
    'orders',    (select count(*) from public.orders o where o.exhibition_id = e.id),
    'mappings',  (select count(*) from public.barcode_mappings b where b.exhibition_id = e.id)
  ) order by e.is_current desc, e.start_date desc), '[]'::jsonb)
  from public.exhibitions e;
$fn$;
revoke all on function public.admin_list_exhibitions() from public, anon, authenticated;
grant execute on function public.admin_list_exhibitions() to service_role;

-- admin_set_current_exhibition: flip which exhibition is live, ATOMICALLY.
-- The partial unique index exhibitions_one_current forbids two current rows, so
-- the old current is cleared BEFORE the new one is set, both inside this single
-- function transaction. Setting the new one first, or using two separate
-- transactions, would violate the index the first time it matters.
create or replace function public.admin_set_current_exhibition(p_exhibition_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
begin
  if not exists (select 1 from public.exhibitions where id = p_exhibition_id) then
    raise exception 'UNKNOWN_EXHIBITION';
  end if;
  update public.exhibitions set is_current = false, updated_at = now() where is_current = true;
  update public.exhibitions set is_current = true,  updated_at = now() where id = p_exhibition_id;
  return jsonb_build_object('ok', true, 'currentId', p_exhibition_id);
end;
$fn$;
revoke all on function public.admin_set_current_exhibition(uuid) from public, anon, authenticated;
grant execute on function public.admin_set_current_exhibition(uuid) to service_role;

-- Guard support: are the barcode functions exhibition-scoped? Checks by
-- PARAMETER NAME (p_exhibition_id), not arg count or trailing type — both
-- functions already ended in a trailing uuid (p_admin_user_id), so a count/type
-- check would false-pass against the old signatures. Used by the createExhibition
-- guard, fail-closed.
create or replace function public.barcode_functions_exhibition_scoped()
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_catalog'
as $fn$
  select
    exists(select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname = 'admin_map_barcode'
             and 'p_exhibition_id' = any(coalesce(proargnames, array[]::text[])))
    and
    exists(select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname = 'admin_deactivate_barcode'
             and 'p_exhibition_id' = any(coalesce(proargnames, array[]::text[])));
$fn$;
revoke all on function public.barcode_functions_exhibition_scoped() from public, anon, authenticated;
grant execute on function public.barcode_functions_exhibition_scoped() to service_role;

-- Durable assumption note (attached without recreating the function): the admin
-- scan path passes p_exhibition_id, and it is honoured ONLY because staff auth
-- users have no public.customers row (the coalesce is customer-row-first). Give
-- a staff member a customer account and admin scanning would silently resolve to
-- that customer's exhibition instead. Do not do that.
comment on function public.lookup_barcode(text, uuid) is
  'Exhibition resolution is coalesce(caller customer row, p_exhibition_id, current). Admin scan relies on staff having NO customers row so p_exhibition_id wins. Never give staff a customer account or admin scanning breaks silently.';

commit;
