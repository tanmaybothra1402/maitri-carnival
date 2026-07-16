-- Service-role-only product master synchronization functions.

create or replace function public.normalize_product_firm(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare v text := lower(btrim(coalesce(p_value, '')));
begin
  if v = 'maitri' then return 'Maitri'; end if;
  if v = 'niharika' then return 'Niharika'; end if;
  if v in ('both', 'maitri/niharika', 'maitri & niharika', 'maitri and niharika') then return 'Both'; end if;
  raise exception 'INVALID_PRODUCT_FIRM_%', p_value;
end;
$$;

create or replace function public.parse_sheet_boolean(p_value text, p_default boolean default true)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when btrim(coalesce(p_value, '')) = '' then p_default
    when lower(btrim(p_value)) in ('true','yes','y','1','active') then true
    when lower(btrim(p_value)) in ('false','no','n','0','inactive') then false
    else p_default
  end;
$$;

create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    insert into public.designs(
      design_no, firm, category, fabric, color, description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      btrim(coalesce(v_row ->> 'Color', v_row ->> 'color', '')),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      category = excluded.category,
      fabric = excluded.fabric,
      color = excluded.color,
      description = excluded.description,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm, public.designs.category, public.designs.fabric,
      public.designs.color, public.designs.description, public.designs.active,
      public.designs.source_updated_at
    ) is distinct from (
      excluded.firm, excluded.category, excluded.fabric, excluded.color,
      excluded.description, excluded.active, excluded.source_updated_at
    );

    insert into public.design_assets(design_no, base_image_url)
    values (
      v_design_no,
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', ''))
    )
    on conflict (design_no) do update set
      base_image_url = excluded.base_image_url,
      updated_at = now()
    where public.design_assets.base_image_url is distinct from excluded.base_image_url;

    v_count := v_count + 1;
  end loop;

  insert into public.product_sync_runs(mode, received_count, upserted_count, status)
  values ('ROWS', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), v_count, 'Success');

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', v_count,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('ROWS', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

create or replace function public.apply_product_snapshot(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_seen text[] := array[]::text[];
  v_row jsonb;
  v_design_no text;
  v_deactivated integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  -- Validate duplicate/blank keys before changing the master.
  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_NO_%', v_design_no; end if;
    v_seen := array_append(v_seen, v_design_no);
  end loop;

  v_result := public.upsert_product_rows(p_rows);

  update public.designs
  set active = false, sync_version = sync_version + 1, updated_at = now()
  where active = true
    and not (design_no = any(v_seen));
  get diagnostics v_deactivated = row_count;

  insert into public.product_sync_runs(mode, received_count, upserted_count, deactivated_count, status)
  values (
    'FULL_SNAPSHOT',
    jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    coalesce((v_result ->> 'upserted')::integer, 0),
    v_deactivated,
    'Success'
  );

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', coalesce((v_result ->> 'upserted')::integer, 0),
    'deactivated', v_deactivated,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('FULL_SNAPSHOT', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

revoke all on function public.normalize_product_firm(text) from public, anon, authenticated;
revoke all on function public.parse_sheet_boolean(text, boolean) from public, anon, authenticated;
revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
revoke all on function public.apply_product_snapshot(jsonb) from public, anon, authenticated;

grant execute on function public.upsert_product_rows(jsonb) to service_role;
grant execute on function public.apply_product_snapshot(jsonb) to service_role;
