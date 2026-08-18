-- 202608010019_buyer_type_regular.sql
--
-- Rename the buyer_type value 'old' -> 'regular' at the database level. Verified
-- 2026-08-17: zero customer_crm rows have buyer_type='old' (zero have any value),
-- so the data update touches nothing today; it becomes a real migration the moment
-- screening starts, which is why it is done now.
--
-- customer_crm_log is append-only audit history and is deliberately NOT rewritten:
-- two historical rows (customer 13371fc5, set by the administrator) record a real
-- 'new'->'old'->null sequence from early testing. Rewriting 'old'->'regular' there
-- would falsify what actually happened. The log has no CHECK on its values, so the
-- stale term is harmless.
--
-- crm_set_buyer_type / crm_bulk_set_buyer_type are restated whole (no signature
-- change) with the new validation, keeping security definer / search_path=public /
-- service-role-only grants.

begin;

-- 1. Constraint: 'new' | 'regular' (was 'new' | 'old').
alter table public.customer_crm drop constraint if exists customer_crm_buyer_type_check;
alter table public.customer_crm
  add constraint customer_crm_buyer_type_check
  check (buyer_type is null or buyer_type in ('new','regular'));

-- 2. Migrate any existing 'old' live values (expected 0 — asserted in verification).
update public.customer_crm set buyer_type = 'regular' where buyer_type = 'old';

-- 3. Setters accept 'regular', reject 'old'.
create or replace function public.crm_set_buyer_type(p_customer_id uuid, p_buyer_type text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  v_new := nullif(btrim(coalesce(p_buyer_type,'')), '');
  if v_new is not null and v_new not in ('new','regular') then raise exception 'INVALID_BUYER_TYPE'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select buyer_type into v_old from public.customer_crm where customer_id = p_customer_id;
  insert into public.customer_crm(customer_id, buyer_type, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_new, now(), p_actor)
    on conflict (customer_id) do update set buyer_type = excluded.buyer_type, crm_updated_at = now(), crm_updated_by = p_actor;
  if v_old is distinct from v_new then
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value) values (p_customer_id, p_actor, 'buyer_type', v_old, v_new);
  end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.crm_bulk_set_buyer_type(p_customer_ids uuid[], p_buyer_type text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_new text; v_count integer;
begin
  v_new := nullif(btrim(coalesce(p_buyer_type,'')), '');
  if v_new is not null and v_new not in ('new','regular') then raise exception 'INVALID_BUYER_TYPE'; end if;
  if p_customer_ids is null or array_length(p_customer_ids,1) is null then raise exception 'NO_CUSTOMERS'; end if;
  if array_length(p_customer_ids,1) > 2000 then raise exception 'TOO_MANY_CUSTOMERS'; end if;

  with ids as (select distinct unnest(p_customer_ids) as customer_id),
  old as (select i.customer_id, cc.buyer_type as old_val from ids i left join public.customer_crm cc on cc.customer_id = i.customer_id),
  up as (
    insert into public.customer_crm(customer_id, buyer_type, crm_updated_at, crm_updated_by)
    select customer_id, v_new, now(), p_actor from ids
    on conflict (customer_id) do update set buyer_type = excluded.buyer_type, crm_updated_at = now(), crm_updated_by = p_actor
    returning customer_id
  ),
  logged as (
    insert into public.customer_crm_log(customer_id, actor_id, field, old_value, new_value)
    select o.customer_id, p_actor, 'buyer_type', o.old_val, v_new
    from old o where o.old_val is distinct from v_new
    returning 1
  )
  select count(*) into v_count from up;
  return jsonb_build_object('ok', true, 'count', v_count);
end; $$;

revoke all on function public.crm_set_buyer_type(uuid, text, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_set_buyer_type(uuid, text, uuid) to service_role;
revoke all on function public.crm_bulk_set_buyer_type(uuid[], text, uuid)     from public, anon, authenticated;
grant  execute on function public.crm_bulk_set_buyer_type(uuid[], text, uuid) to service_role;

commit;
