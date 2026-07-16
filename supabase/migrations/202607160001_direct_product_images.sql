-- Direct product image delivery.
-- ProductMaster.ImageURL is stored on public.designs and is intentionally
-- readable by authenticated exhibition users together with the design record.

alter table public.designs
  add column if not exists image_url text not null default '';

-- Preserve any URLs already synchronized by the previous private-asset model.
update public.designs d
set image_url = da.base_image_url,
    updated_at = now()
from public.design_assets da
where da.design_no = d.design_no
  and btrim(coalesce(da.base_image_url, '')) <> ''
  and d.image_url is distinct from da.base_image_url;

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
      design_no, firm, image_url, category, fabric, color, description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', '')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      btrim(coalesce(v_row ->> 'Color', v_row ->> 'color', '')),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      image_url = excluded.image_url,
      category = excluded.category,
      fabric = excluded.fabric,
      color = excluded.color,
      description = excluded.description,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm, public.designs.image_url, public.designs.category,
      public.designs.fabric, public.designs.color, public.designs.description,
      public.designs.active, public.designs.source_updated_at
    ) is distinct from (
      excluded.firm, excluded.image_url, excluded.category, excluded.fabric,
      excluded.color, excluded.description, excluded.active, excluded.source_updated_at
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

-- Return the image URL directly with a successful barcode lookup.
drop function if exists public.lookup_barcode(text);

create function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  image_url text,
  category text,
  fabric text,
  color text,
  description text
)
language sql
stable
set search_path = public
as $$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.image_url,
    d.category,
    d.fabric,
    d.color,
    d.description
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$$;

create or replace function public.order_state_json(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', o.id,
    'firm', o.firm,
    'status', o.status,
    'version', o.version,
    'totalDesigns', o.total_designs,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'imageUrl', d.image_url,
          'qty', i.qty,
          'category', i.category_snapshot,
          'fabric', i.fabric_snapshot,
          'color', i.color_snapshot,
          'description', i.description_snapshot
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      join public.designs d on d.design_no = i.design_no
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$$;

revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_product_rows(jsonb) to service_role;

revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
grant execute on function public.lookup_barcode(text) to authenticated;

revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
grant execute on function public.order_state_json(uuid) to service_role;

-- The separate private asset table and proxy are no longer part of this build.
drop table if exists public.design_assets;
