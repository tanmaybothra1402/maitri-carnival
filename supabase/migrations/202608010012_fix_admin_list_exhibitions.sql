-- Fix admin_list_exhibitions after barcode_mappings went global (202608010011).
--
-- 202608010011 dropped barcode_mappings.exhibition_id. admin_list_exhibitions still
-- counted mappings with "where b.exhibition_id = e.id", so every call raised
--   42703  column b.exhibition_id does not exist
-- The admin exhibition switcher and the Exhibitions tab were dead in production
-- until this landed.
--
-- Why the compile check missed it: a SQL-language function body is validated for
-- the columns it names only at CREATE time, against the schema AS IT WAS THEN. The
-- column drop happened in a *later* migration, so the now-stale reference shipped
-- silently. Lesson (see maitri-guardrails): after dropping a column, CALL every
-- function that reads that table — a compile check cannot catch this.
--
-- 'mappings' is now a GLOBAL active count — identical on every exhibition row —
-- because barcode mappings are global (one sticker run across all exhibitions).
--
-- This function was applied to prod directly via MCP; this file records it so the
-- repo matches. It is idempotent (create or replace); do not re-apply by hand.

create or replace function public.admin_list_exhibitions()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'slug', e.slug, 'name', e.name,
    'startDate', e.start_date, 'endDate', e.end_date,
    'editWindowHours', e.edit_window_hours,
    'registrationEnabled', e.registration_enabled,
    'isCurrent', e.is_current,
    'customers', (select count(*) from public.customers c where c.exhibition_id = e.id),
    'orders',    (select count(*) from public.orders o where o.exhibition_id = e.id),
    'mappings',  (select count(*) from public.barcode_mappings b where b.active)
  ) order by e.is_current desc, e.start_date desc), '[]'::jsonb)
  from public.exhibitions e;
$function$;

revoke all on function public.admin_list_exhibitions() from public;
revoke all on function public.admin_list_exhibitions() from anon;
revoke all on function public.admin_list_exhibitions() from authenticated;
grant execute on function public.admin_list_exhibitions() to service_role;
