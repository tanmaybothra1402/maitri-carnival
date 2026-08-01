-- 202608010004_scope_admin_barcode_functions.sql
-- Brief 3.6 piece 1: admin_map_barcode and admin_deactivate_barcode no longer
-- silently target current_exhibition_id(). They take an explicit p_exhibition_id
-- and resolve it loudly:
--   * p_exhibition_id given  -> use it (must exist)
--   * none, one exhibition   -> current_exhibition_id() (single-event convenience)
--   * none, two or more      -> raise EXHIBITION_ID_REQUIRED
-- This is the same conditional-fallback shape as handle_new_auth_user: a silent
-- "whatever is current" is the footgun; an explicit demand once it is ambiguous
-- is the fix. This closes the last known admin cross-exhibition footgun.
--
-- Signature change on both (new trailing p_exhibition_id) -> drop first, then
-- recreate and re-grant. admin-api passes the selected exhibition through in
-- piece 2 (shipping together).

begin;

-- admin_map_barcode -----------------------------------------------------------
drop function if exists public.admin_map_barcode(text, text, uuid);
create or replace function public.admin_map_barcode(p_barcode text, p_design_no text, p_admin_user_id uuid, p_exhibition_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_barcode text := btrim(coalesce(p_barcode, ''));
  v_design_no text := btrim(coalesce(p_design_no, ''));
  v_exhibition uuid;
  v_count integer;
  v_existing public.barcode_mappings%rowtype;
  v_action text;
begin
  if v_barcode = '' then raise exception 'BARCODE_REQUIRED'; end if;
  if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

  -- Resolve the target exhibition explicitly.
  if p_exhibition_id is not null then
    v_exhibition := p_exhibition_id;
    if not exists (select 1 from public.exhibitions where id = v_exhibition) then
      raise exception 'UNKNOWN_EXHIBITION';
    end if;
  else
    select count(*) into v_count from public.exhibitions;
    if v_count = 1 then
      v_exhibition := public.current_exhibition_id();
    else
      raise exception 'EXHIBITION_ID_REQUIRED';
    end if;
  end if;
  if v_exhibition is null then raise exception 'NO_EXHIBITION'; end if;

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
revoke all on function public.admin_map_barcode(text, text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid, uuid) to service_role;

-- admin_deactivate_barcode ----------------------------------------------------
drop function if exists public.admin_deactivate_barcode(text, uuid);
create or replace function public.admin_deactivate_barcode(p_barcode text, p_admin_user_id uuid, p_exhibition_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  v_exhibition uuid;
  v_count integer;
  v_row public.barcode_mappings%rowtype;
begin
  -- Resolve the target exhibition explicitly (same rule as admin_map_barcode).
  if p_exhibition_id is not null then
    v_exhibition := p_exhibition_id;
    if not exists (select 1 from public.exhibitions where id = v_exhibition) then
      raise exception 'UNKNOWN_EXHIBITION';
    end if;
  else
    select count(*) into v_count from public.exhibitions;
    if v_count = 1 then
      v_exhibition := public.current_exhibition_id();
    else
      raise exception 'EXHIBITION_ID_REQUIRED';
    end if;
  end if;
  if v_exhibition is null then raise exception 'NO_EXHIBITION'; end if;

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
revoke all on function public.admin_deactivate_barcode(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_deactivate_barcode(text, uuid, uuid) to service_role;

commit;
