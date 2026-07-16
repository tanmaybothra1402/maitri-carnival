-- Customer provisioning, admin helpers, grants and Row-Level Security.

create or replace function public.is_admin_user(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;

  -- Real-email admin users are intentionally not customer profiles.
  if split_part(lower(coalesce(new.email, '')), '@', 2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164', ''), '\D', '', 'g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  if split_part(lower(new.email), '@', 1) <> v_phone then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code', '');
    if encode(extensions.digest(v_access_code, 'sha256'), 'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin);

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.system_settings enable row level security;
alter table public.customers enable row level security;
alter table public.designs enable row level security;
alter table public.design_assets enable row level security;
alter table public.barcode_mappings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_save_requests enable row level security;
alter table public.barcode_mapping_log enable row level security;
alter table public.product_sync_runs enable row level security;

create policy customers_select_own
on public.customers for select
to authenticated
using (id = auth.uid());

create policy customers_update_own
on public.customers for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy designs_read_active
on public.designs for select
to authenticated
using (active = true);

create policy barcode_mappings_read_active
on public.barcode_mappings for select
to authenticated
using (
  active = true
  and exists (
    select 1 from public.designs d
    where d.design_no = barcode_mappings.design_no
      and d.active = true
  )
);

create policy orders_select_own
on public.orders for select
to authenticated
using (customer_id = auth.uid());

create policy order_items_select_own
on public.order_items for select
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.customer_id = auth.uid()
  )
);

-- Start from least privilege. Customer writes happen only through audited RPCs.
revoke all on public.system_settings from anon, authenticated;
revoke all on public.customers from anon, authenticated;
revoke all on public.designs from anon, authenticated;
revoke all on public.design_assets from anon, authenticated;
revoke all on public.barcode_mappings from anon, authenticated;
revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
revoke all on public.order_save_requests from anon, authenticated;
revoke all on public.barcode_mapping_log from anon, authenticated;
revoke all on public.product_sync_runs from anon, authenticated;

-- RLS still applies to every granted read.
grant select on public.customers to authenticated;
grant update (company_name, contact_name, city, state, gstin) on public.customers to authenticated;
grant select on public.designs to authenticated;
grant select on public.barcode_mappings to authenticated;
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;

revoke all on function public.is_admin_user(uuid) from public, anon, authenticated;
grant execute on function public.is_admin_user(uuid) to authenticated, service_role;
