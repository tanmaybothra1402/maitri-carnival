-- 202608010002_remove_customer_images.sql
-- Brief 3: customers see no product images anywhere. Remove the image_key /
-- imageKey plumbing from the two customer-facing readers, and drop the now-dead
-- design_image_source (its only caller, the design-image Edge Function, is
-- deleted). Admin/dispatch keep full-resolution images via the service-role
-- admin API (listDesigns) — untouched here.

begin;

-- 1. order_state_json: drop the 'imageKey' field. Same signature, so grants are
--    preserved. Everything else is byte-identical to the current definition.
create or replace function public.order_state_json(p_order_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'id', o.id,
    'firm', o.firm,
    'status', o.status,
    'version', o.version,
    'adminUnlocked', o.admin_unlocked,
    'dispatchStatus', o.dispatch_status,
    'totalDesigns', o.total_designs,
    'totalSets', o.total_sets,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'qty', i.qty,
          'category', i.category_snapshot,
          'style', i.style_snapshot,
          'fabric', i.fabric_snapshot,
          'pcsPerSet', i.pcs_per_set_snapshot,
          'totalPieces', i.qty * i.pcs_per_set_snapshot,
          'note', i.line_note,
          'color', i.color_snapshot,
          'description', i.description_snapshot,
          'locked', coalesce(dl.dispatched_sets, 0) > 0
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      left join public.dispatch_lines dl
        on dl.order_id = i.order_id and dl.design_no = i.design_no
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$fn$;

-- 2. lookup_barcode: drop the image_key column. Return type changes, so drop
--    first. Keeps the current-exhibition scoping from 202608010001.
drop function if exists public.lookup_barcode(text);
create or replace function public.lookup_barcode(p_barcode text)
 returns TABLE(barcode text, design_no text, firm text, category text, style text, fabric text, pcs_per_set integer, description text, color text)
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select
    bm.barcode,
    d.design_no,
    d.firm,
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

-- 3. Drop the dead master-URL resolver. Its only consumer (the design-image
--    Edge Function) is removed; leaving a definer function that returns
--    designs.image_url is a landmine, so remove it.
drop function if exists public.design_image_source(text);

commit;
