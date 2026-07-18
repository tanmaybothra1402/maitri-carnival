-- ---------------------------------------------------------------------------
-- Barcode mappings become one-way once active.
--
-- A printed sticker is a physical object. Silently re-pointing it at a
-- different design means every garment already scanned with that sticker is
-- now attributed to the wrong product, with no warning and no audit trail.
--
-- New rule: an ACTIVE mapping cannot be pointed at a different design.
-- To reuse a barcode you must first deactivate it (admin console) or change
-- it through the Sheet, both of which are deliberate acts.
--
-- Still allowed:
--   * mapping a barcode that has never been mapped
--   * re-mapping a barcode whose mapping is inactive
--   * re-sending the same barcode -> same design (no-op)
-- ---------------------------------------------------------------------------

create or replace function public.admin_map_barcode(
  p_barcode text,
  p_design_no text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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

  return jsonb_build_object(
    'ok', true,
    'barcode', v_barcode,
    'designNo', v_design_no,
    'action', v_action
  );
end;
$$;

revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;
