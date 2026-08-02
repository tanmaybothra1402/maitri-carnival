-- Barcode mappings revert to GLOBAL (undo the Brief 3.6 per-exhibition scoping).
--
-- WHY (do not re-scope — see maitri-architecture / maitri-sheet-sync):
-- The physical stickers were discarded; there is now ONE sticker run used across
-- every exhibition. Designs are global, so a barcode that identifies a design is
-- global too. Per-exhibition mappings only ever existed to allow reprinting a
-- per-event sticker set, which no longer happens. The one-way BARCODE_ALREADY_
-- MAPPED guard stays and becomes genuinely global: a barcode maps to one design
-- forever unless it is deactivated first.
--
-- Ships together with: admin-api (drops exhibitionId on map/mapBatch/deactivate/
-- lookup + drops the barcode-scoping half of the createExhibition guard),
-- user.html + admin console (lookup_barcode no longer takes p_exhibition_id, the
-- Mapping tab is no longer labelled per exhibition), data-sync + DataSync.gs.
--
-- Nothing FKs to barcode_mappings, so the delete is unblocked. barcode_mapping_log
-- (no FK, no exhibition column) stays as history.

-- 1) Clear all mappings — the fresh global sticker run replaces them.
delete from public.barcode_mappings;

-- 2) Schema back to global: PK (barcode), drop the exhibition_id column + its FK/index.
alter table public.barcode_mappings drop constraint barcode_mappings_pkey;
alter table public.barcode_mappings add  constraint barcode_mappings_pkey primary key (barcode);
alter table public.barcode_mappings drop constraint if exists barcode_mappings_exhibition_id_fkey;
drop index if exists public.barcode_mappings_exhibition_id_idx;
alter table public.barcode_mappings drop column if exists exhibition_id;

-- 3) lookup_barcode: unscoped (customer + admin). Signature drops p_exhibition_id.
drop function if exists public.lookup_barcode(text, uuid);
create or replace function public.lookup_barcode(p_barcode text)
 returns TABLE(barcode text, design_no text, firm text, category text, style text, fabric text, pcs_per_set integer, description text, color text)
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  select bm.barcode, d.design_no, d.firm, d.category, d.style, d.fabric,
         d.pcs_per_set, d.description, d.color
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$fn$;
revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated, service_role;

-- 4) admin_map_barcode: unscoped, one-way guard kept (now genuinely global).
drop function if exists public.admin_map_barcode(text, text, uuid, uuid);
drop function if exists public.admin_map_barcode(text, text, uuid);
create or replace function public.admin_map_barcode(p_barcode text, p_design_no text, p_admin_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_barcode text := btrim(coalesce(p_barcode, ''));
  v_design_no text := btrim(coalesce(p_design_no, ''));
  v_existing public.barcode_mappings%rowtype;
  v_action text;
begin
  if v_barcode = '' then raise exception 'BARCODE_REQUIRED'; end if;
  if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
  if not exists (select 1 from public.designs where design_no = v_design_no and active = true) then
    raise exception 'ACTIVE_DESIGN_NOT_FOUND';
  end if;

  select * into v_existing from public.barcode_mappings where barcode = v_barcode for update;

  if found then
    -- Blocked: a live barcode is one design forever unless deactivated first.
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
      where barcode = v_barcode;
    end if;
  else
    v_action := 'Created';
    insert into public.barcode_mappings(barcode, design_no, mapped_by)
    values (v_barcode, v_design_no, p_admin_user_id);
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

  return jsonb_build_object('ok', true, 'barcode', v_barcode, 'designNo', v_design_no, 'action', v_action);
end;
$fn$;
revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;

-- 5) admin_deactivate_barcode: unscoped.
drop function if exists public.admin_deactivate_barcode(text, uuid, uuid);
drop function if exists public.admin_deactivate_barcode(text, uuid);
create or replace function public.admin_deactivate_barcode(p_barcode text, p_admin_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_row public.barcode_mappings%rowtype;
begin
  select * into v_row from public.barcode_mappings where barcode = btrim(p_barcode) for update;
  if not found then raise exception 'BARCODE_NOT_FOUND'; end if;

  update public.barcode_mappings set active = false, mapped_by = p_admin_user_id, updated_at = now()
  where barcode = v_row.barcode;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (v_row.barcode, v_row.design_no, v_row.design_no, 'Deactivated', p_admin_user_id);

  return jsonb_build_object('barcode', v_row.barcode, 'designNo', v_row.design_no, 'active', false);
end;
$fn$;
revoke all on function public.admin_deactivate_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.admin_deactivate_barcode(text, uuid) to service_role;

-- 6) The createExhibition guard's barcode-scoping check is now permanently false
--    (the functions no longer carry p_exhibition_id). Drop the introspection RPC;
--    admin-api removes that half of the guard in the same shipment and keeps the
--    customer-auth authContract check.
drop function if exists public.barcode_functions_exhibition_scoped();

-- 7) Re-comment lookup_barcode: no exhibition resolution any more.
comment on function public.lookup_barcode(text) is
  'Global barcode -> design lookup (customer + admin). Mappings are global: one sticker run across every exhibition. Do not re-scope by exhibition — see maitri-architecture.';
