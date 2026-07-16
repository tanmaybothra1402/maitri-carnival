-- Shared lookup values (dropdowns with add-new) + customer agent field.

-- ---------------------------------------------------------------------------
-- Lookup values: category / fabric / color / city / agent
-- ---------------------------------------------------------------------------
create table if not exists public.lookup_values (
  kind text not null check (kind in ('category','fabric','color','city','agent')),
  value text not null check (length(btrim(value)) between 1 and 120),
  created_at timestamptz not null default now(),
  primary key (kind, value)
);

alter table public.lookup_values enable row level security;

-- Reference data: readable by anyone (registration form needs city/agent before login).
drop policy if exists lookup_values_read on public.lookup_values;
create policy lookup_values_read on public.lookup_values for select to anon, authenticated using (true);
revoke all on public.lookup_values from anon, authenticated;
grant select on public.lookup_values to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Customer agent
-- ---------------------------------------------------------------------------
alter table public.customers add column if not exists agent text not null default '';
grant update (company_name, contact_name, city, state, gstin, agent) on public.customers to authenticated;

-- ---------------------------------------------------------------------------
-- Auto-maintain lookup_values from live data (no manual upkeep, no dupes)
-- ---------------------------------------------------------------------------
create or replace function public.sync_customer_lookups()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(new.city,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('city', btrim(new.city)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.agent,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('agent', btrim(new.agent)) on conflict do nothing;
  end if;
  return new;
end;$$;

drop trigger if exists customers_sync_lookups on public.customers;
create trigger customers_sync_lookups
after insert or update of city, agent on public.customers
for each row execute function public.sync_customer_lookups();

create or replace function public.sync_design_lookups()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(new.category,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('category', btrim(new.category)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.fabric,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('fabric', btrim(new.fabric)) on conflict do nothing;
  end if;
  if btrim(coalesce(new.color,'')) <> '' then
    insert into public.lookup_values(kind,value) values ('color', btrim(new.color)) on conflict do nothing;
  end if;
  return new;
end;$$;

drop trigger if exists designs_sync_lookups on public.designs;
create trigger designs_sync_lookups
after insert or update of category, fabric, color on public.designs
for each row execute function public.sync_design_lookups();

-- Seed from existing data.
insert into public.lookup_values(kind,value)
select 'category', btrim(category) from public.designs where btrim(coalesce(category,'')) <> ''
union select 'fabric', btrim(fabric) from public.designs where btrim(coalesce(fabric,'')) <> ''
union select 'color', btrim(color) from public.designs where btrim(coalesce(color,'')) <> ''
union select 'city', btrim(city) from public.customers where btrim(coalesce(city,'')) <> ''
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- list_lookups(): all dropdown values grouped by kind (anon + authenticated)
-- ---------------------------------------------------------------------------
create or replace function public.list_lookups()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(kind, vals), '{}'::jsonb)
  from (
    select kind, jsonb_agg(value order by value) as vals
    from public.lookup_values group by kind
  ) t;
$$;

revoke all on function public.list_lookups() from public;
grant execute on function public.list_lookups() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Provision agent on registration (extend the auth trigger)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text; v_contact text; v_city text; v_state text; v_gstin text; v_agent text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;
  if split_part(lower(coalesce(new.email,'')),'@',2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;
  if not v_settings.registration_enabled then raise exception 'REGISTRATION_CLOSED'; end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164',''),'\D','','g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then raise exception 'INVALID_CUSTOMER_PHONE'; end if;
  if split_part(lower(new.email),'@',1) <> ('c' || v_phone) then raise exception 'PHONE_EMAIL_MISMATCH'; end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code','');
    if encode(extensions.digest(v_access_code,'sha256'),'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name',''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name',''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city',''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state',''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin','')));
  v_agent := btrim(coalesce(new.raw_user_meta_data ->> 'agent',''));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin, agent)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin, v_agent);

  insert into public.orders(customer_id, firm, status)
  values (new.id,'Maitri','Draft'), (new.id,'Niharika','Draft');

  return new;
end;
$$;
