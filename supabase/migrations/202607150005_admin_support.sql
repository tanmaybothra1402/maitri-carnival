-- Server-side helpers used by admin-api. Browser customers receive no grants.

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
    v_action := case
      when v_existing.design_no <> v_design_no then 'Remapped'
      when not v_existing.active then 'Reactivated'
      else 'Remapped'
    end;

    update public.barcode_mappings
    set design_no = v_design_no, active = true, mapped_by = p_admin_user_id, updated_at = now()
    where barcode = v_barcode;
  else
    v_action := 'Created';
    insert into public.barcode_mappings(barcode, design_no, mapped_by)
    values (v_barcode, v_design_no, p_admin_user_id);
  end if;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (
    v_barcode,
    case when v_existing.barcode is null then null else v_existing.design_no end,
    v_design_no,
    v_action,
    p_admin_user_id
  );

  return jsonb_build_object('barcode', v_barcode, 'designNo', v_design_no, 'action', v_action);
end;
$$;

create or replace function public.admin_deactivate_barcode(
  p_barcode text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.barcode_mappings%rowtype;
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
$$;

revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
revoke all on function public.admin_deactivate_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;
grant execute on function public.admin_deactivate_barcode(text, uuid) to service_role;
