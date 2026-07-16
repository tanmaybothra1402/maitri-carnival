-- Maitri Carnival 2026: simplify team permissions, default new pieces/set to 4,
-- and remove the lookup subsystem. Existing product/order rows are deliberately
-- not backfilled.

alter table public.designs
  alter column pcs_per_set set default 4;

alter table public.order_items
  alter column pcs_per_set_snapshot set default 4;

create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_pcs_text text;
  v_pcs integer;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
  v_has_style boolean;
  v_has_pcs boolean;
  v_has_description boolean;
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    v_has_style := (v_row ? 'Style') or (v_row ? 'style');
    v_has_pcs := (v_row ? 'PcsPerSet') or (v_row ? 'pcs_per_set') or (v_row ? 'Pcs');
    v_has_description := (v_row ? 'Description') or (v_row ? 'description');
    v_pcs_text := btrim(coalesce(v_row ->> 'PcsPerSet', v_row ->> 'pcs_per_set', v_row ->> 'Pcs', ''));
    v_pcs := null;
    if v_has_pcs then
      begin
        v_pcs := v_pcs_text::integer;
      exception when others then
        raise exception 'INVALID_PCS_PER_SET_FOR_%', v_design_no;
      end;
      if v_pcs < 1 or v_pcs > 9999 then raise exception 'INVALID_PCS_PER_SET_FOR_%', v_design_no; end if;
    end if;

    insert into public.designs(
      design_no, firm, image_url, category, style, fabric, pcs_per_set,
      description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', '')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Style', v_row ->> 'style', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      coalesce(v_pcs, 4),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      image_url = excluded.image_url,
      category = excluded.category,
      style = case when v_has_style then excluded.style else public.designs.style end,
      fabric = excluded.fabric,
      pcs_per_set = case when v_has_pcs then excluded.pcs_per_set else public.designs.pcs_per_set end,
      description = case when v_has_description then excluded.description else public.designs.description end,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm,
      public.designs.image_url,
      public.designs.category,
      public.designs.style,
      public.designs.fabric,
      public.designs.pcs_per_set,
      public.designs.description,
      public.designs.active,
      public.designs.source_updated_at
    ) is distinct from (
      excluded.firm,
      excluded.image_url,
      excluded.category,
      case when v_has_style then excluded.style else public.designs.style end,
      excluded.fabric,
      case when v_has_pcs then excluded.pcs_per_set else public.designs.pcs_per_set end,
      case when v_has_description then excluded.description else public.designs.description end,
      excluded.active,
      excluded.source_updated_at
    );

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

drop trigger if exists designs_sync_lookups on public.designs;
drop trigger if exists customers_sync_lookups on public.customers;
drop function if exists public.sync_design_lookups();
drop function if exists public.sync_customer_lookups();
drop function if exists public.list_lookups();
drop table if exists public.lookup_values cascade;
