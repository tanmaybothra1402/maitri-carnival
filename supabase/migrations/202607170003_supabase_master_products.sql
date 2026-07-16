-- Supabase is the authoritative product master. The Google Sheet is an
-- import/mirror only and must never deactivate designs that live in Supabase.
-- This redefines apply_product_snapshot to upsert without deactivating.

create or replace function public.apply_product_snapshot(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  v_result := public.upsert_product_rows(p_rows);

  insert into public.product_sync_runs(mode, received_count, upserted_count, deactivated_count, status)
  values (
    'FULL_SNAPSHOT',
    jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    coalesce((v_result ->> 'upserted')::integer, 0),
    0,
    'Success'
  );

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', coalesce((v_result ->> 'upserted')::integer, 0),
    'deactivated', 0,
    'note', 'Supabase is master; sheet sync no longer deactivates designs.',
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('FULL_SNAPSHOT', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

revoke all on function public.apply_product_snapshot(jsonb) from public, anon, authenticated;
grant execute on function public.apply_product_snapshot(jsonb) to service_role;
