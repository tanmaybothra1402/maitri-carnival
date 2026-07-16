-- Staff identities, granular permissions, action attribution and dashboard v2.

create table if not exists public.staff_profiles (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  staff_id text not null unique check (staff_id ~ '^[a-z0-9][a-z0-9._-]{1,39}$'),
  staff_name text not null check (length(btrim(staff_name)) between 2 and 100),
  preset text not null default 'custom' check (preset in ('sales','reception','products','manager','administrator','custom')),
  permissions jsonb not null default '{}'::jsonb check (jsonb_typeof(permissions) = 'object'),
  default_section text not null default 'sale' check (default_section in ('reception','dashboard','sale','products','admin')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists staff_profiles_updated_at on public.staff_profiles;
create trigger staff_profiles_updated_at
before update on public.staff_profiles
for each row execute function public.set_updated_at();

alter table public.staff_profiles enable row level security;
revoke all on public.staff_profiles from anon, authenticated;

create or replace function public.staff_permission_defaults(p_preset text)
returns jsonb
language sql
immutable
as $$
  select case lower(coalesce(p_preset,''))
    when 'sales' then jsonb_build_object(
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,
      'reception.view',true
    )
    when 'reception' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'admin.bookings',true
    )
    when 'products' then jsonb_build_object(
      'products.view',true,'products.edit',true,'products.mapping',true,'products.lookups',true
    )
    when 'manager' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,'products.lookups',true,
      'admin.slots',true,'admin.bookings',true
    )
    when 'administrator' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,'products.lookups',true,
      'admin.slots',true,'admin.bookings',true,'admin.staff',true,'admin.settings',true
    )
    else '{}'::jsonb
  end;
$$;

create or replace function public.staff_has_permission(
  p_user_id uuid,
  p_permission text
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce((
    select case
      when coalesce(u.raw_app_meta_data ->> 'role','') = 'admin' then true
      when coalesce(u.raw_app_meta_data ->> 'role','') = 'staff' then
        coalesce(sp.active,false)
        and coalesce((sp.permissions ->> p_permission)::boolean,false)
      else false
    end
    from auth.users u
    left join public.staff_profiles sp on sp.auth_user_id = u.id
    where u.id = p_user_id
  ), false);
$$;

create or replace function public.is_admin_user(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users u
    left join public.staff_profiles sp on sp.auth_user_id = u.id
    where u.id = p_user_id
      and (
        coalesce(u.raw_app_meta_data ->> 'role','') = 'admin'
        or (coalesce(u.raw_app_meta_data ->> 'role','') = 'staff' and coalesce(sp.active,false))
      )
  );
$$;

-- Give existing real-email administrators an editable staff profile without changing their login.
insert into public.staff_profiles(auth_user_id,staff_id,staff_name,preset,permissions,default_section,active)
select
  u.id,
  coalesce(nullif(lower(regexp_replace(split_part(u.email,'@',1),'[^a-z0-9._-]+','','g')),''),'admin') || '-' || substr(u.id::text,1,4),
  coalesce(nullif(btrim(u.raw_user_meta_data ->> 'name'),''), split_part(u.email,'@',1), 'Administrator'),
  'administrator', public.staff_permission_defaults('administrator'), 'dashboard', true
from auth.users u
where coalesce(u.raw_app_meta_data ->> 'role','') = 'admin'
on conflict (auth_user_id) do nothing;

alter table public.order_items add column if not exists created_by_user_id uuid;
alter table public.order_items add column if not exists created_by_type text not null default 'unknown';
alter table public.order_items add column if not exists last_modified_by_user_id uuid;
alter table public.order_items add column if not exists last_modified_by_type text not null default 'unknown';

alter table public.order_items drop constraint if exists order_items_created_by_type_check;
alter table public.order_items add constraint order_items_created_by_type_check
  check (created_by_type in ('customer','staff','unknown'));
alter table public.order_items drop constraint if exists order_items_last_modified_by_type_check;
alter table public.order_items add constraint order_items_last_modified_by_type_check
  check (last_modified_by_type in ('customer','staff','unknown'));

create or replace function public.capture_customer_order_actor()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is not null and exists(select 1 from public.customers c where c.id = v_uid) then
    if tg_op = 'INSERT' then
      new.created_by_user_id := v_uid;
      new.created_by_type := 'customer';
    end if;
    new.last_modified_by_user_id := v_uid;
    new.last_modified_by_type := 'customer';
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_capture_actor on public.order_items;
create trigger order_items_capture_actor
before insert or update on public.order_items
for each row execute function public.capture_customer_order_actor();

-- Dashboard V2. Pie datasets return up to 100 ranked rows; the client displays
-- the first 50 and groups the balance into Others.
create or replace function public.admin_dashboard_v2(
  p_filters jsonb default '{}'::jsonb,
  p_search text default '',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
  v_search text := '%' || btrim(coalesce(p_search,'')) || '%';
  v_summary jsonb;
  v_charts jsonb;
  v_orders jsonb;
  v_total_orders integer;
  v_options jsonb;
begin
  if not public.staff_has_permission(auth.uid(),'dashboard.view') then raise exception 'PERMISSION_DENIED'; end if;

  drop table if exists _dash_facts;
  create temporary table _dash_facts on commit drop as
  select
    o.id order_id, o.customer_id, o.firm, o.status, o.updated_at,
    i.design_no, i.qty sets, (i.qty * i.pcs_per_set_snapshot) pieces,
    coalesce(nullif(btrim(i.category_snapshot),''),'Not specified') category,
    coalesce(nullif(btrim(i.style_snapshot),''),'Not specified') style,
    coalesce(nullif(btrim(i.fabric_snapshot),''),'Not specified') fabric,
    coalesce(nullif(btrim(i.last_modified_by_type),''),'unknown') source,
    c.company_name, c.contact_name, c.phone_e164,
    coalesce(nullif(btrim(c.city),''),'Not specified') city,
    coalesce(nullif(btrim(c.state),''),'Not specified') state,
    coalesce(nullif(btrim(c.agent),''),'Not specified') agent,
    c.checked_in_at
  from public.order_items i
  join public.orders o on o.id=i.order_id
  join public.customers c on c.id=o.customer_id
  where
    (not (p_filters ? 'firm') or o.firm = any(select jsonb_array_elements_text(p_filters->'firm')))
    and (not (p_filters ? 'state') or coalesce(nullif(btrim(c.state),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'state')))
    and (not (p_filters ? 'city') or coalesce(nullif(btrim(c.city),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'city')))
    and (not (p_filters ? 'agent') or coalesce(nullif(btrim(c.agent),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'agent')))
    and (not (p_filters ? 'category') or coalesce(nullif(btrim(i.category_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'category')))
    and (not (p_filters ? 'style') or coalesce(nullif(btrim(i.style_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'style')))
    and (not (p_filters ? 'fabric') or coalesce(nullif(btrim(i.fabric_snapshot),''),'Not specified') = any(select jsonb_array_elements_text(p_filters->'fabric')))
    and (not (p_filters ? 'designNo') or i.design_no = any(select jsonb_array_elements_text(p_filters->'designNo')))
    and (not (p_filters ? 'companyName') or c.company_name = any(select jsonb_array_elements_text(p_filters->'companyName')))
    and (not (p_filters ? 'status') or o.status = any(select jsonb_array_elements_text(p_filters->'status')))
    and (not (p_filters ? 'source') or coalesce(nullif(btrim(i.last_modified_by_type),''),'unknown') = any(select jsonb_array_elements_text(p_filters->'source')))
    and (not (p_filters ? 'checkedIn') or (case when c.checked_in_at is null then 'No' else 'Yes' end) = any(select jsonb_array_elements_text(p_filters->'checkedIn')))
    and (not (p_filters ? 'dateFrom') or o.updated_at >= ((p_filters->'dateFrom'->>0)::date)::timestamptz)
    and (not (p_filters ? 'dateTo') or o.updated_at < (((p_filters->'dateTo'->>0)::date + 1))::timestamptz)
    and (
      btrim(coalesce(p_search,''))='' or c.company_name ilike v_search or c.contact_name ilike v_search
      or c.phone_e164 ilike v_search or i.design_no ilike v_search
    );

  select jsonb_build_object(
    'totalCustomers',(select count(*) from public.customers),
    'checkedInCustomers',(select count(*) from public.customers where checked_in_at is not null),
    'customersWithOrders',count(distinct customer_id),
    'totalOrders',count(distinct order_id),
    'totalSets',coalesce(sum(sets),0),
    'totalPieces',coalesce(sum(pieces),0),
    'uniqueDesigns',count(distinct design_no),
    'averagePiecesPerBuyer',case when count(distinct customer_id)=0 then 0 else round(coalesce(sum(pieces),0)::numeric/count(distinct customer_id),1) end,
    'activeBookings',(select count(*) from public.bookings where status='Booked')
  ) into v_summary from _dash_facts;

  select jsonb_build_object(
    'firm', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select firm label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers from _dash_facts group by firm order by sum(pieces) desc limit 100)x),
    'statePieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select state label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers from _dash_facts group by state order by sum(pieces) desc limit 100)x),
    'stateCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select state label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by state order by count(distinct customer_id) desc limit 100)x),
    'cityPieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select city label,sum(pieces)::int value,count(distinct customer_id)::int customers from _dash_facts group by city order by sum(pieces) desc limit 100)x),
    'cityCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select city label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by city order by count(distinct customer_id) desc limit 100)x),
    'agentPieces', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select agent label,sum(pieces)::int value,count(distinct customer_id)::int customers from _dash_facts group by agent order by sum(pieces) desc limit 100)x),
    'agentCustomers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select agent label,count(distinct customer_id)::int value,sum(pieces)::int pieces from _dash_facts group by agent order by count(distinct customer_id) desc limit 100)x),
    'category', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select category label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by category order by sum(pieces) desc limit 100)x),
    'style', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select style label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by style order by sum(pieces) desc limit 100)x),
    'fabric', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select fabric label,sum(pieces)::int value,count(distinct design_no)::int designs from _dash_facts group by fabric order by sum(pieces) desc limit 100)x),
    'designs', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select design_no label,sum(pieces)::int value,sum(sets)::int sets,count(distinct customer_id)::int customers,min(category) category,min(style) style,min(fabric) fabric from _dash_facts group by design_no order by sum(pieces) desc limit 100)x),
    'customers', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select customer_id::text id,company_name label,sum(pieces)::int value,sum(sets)::int sets,count(distinct design_no)::int designs,count(distinct order_id)::int orders,min(city) city,min(state) state,min(agent) agent from _dash_facts group by customer_id,company_name order by sum(pieces) desc limit 100)x),
    'source', (select coalesce(jsonb_agg(x order by x.value desc),'[]'::jsonb) from (select source label,sum(pieces)::int value from _dash_facts group by source order by sum(pieces) desc limit 100)x)
  ) into v_charts;

  select count(*) into v_total_orders from (select distinct order_id from _dash_facts) q;
  select coalesce(jsonb_agg(x order by x."updatedAt" desc),'[]'::jsonb) into v_orders from (
    select order_id::text "orderId",customer_id::text "customerId",min(company_name) "companyName",min(contact_name) "contactName",
      min(phone_e164) phone,min(city) city,min(state) state,min(agent) agent,min(firm) firm,min(status) status,
      count(distinct design_no)::int designs,sum(sets)::int sets,sum(pieces)::int pieces,max(updated_at) "updatedAt"
    from _dash_facts group by order_id,customer_id order by max(updated_at) desc
    limit greatest(1,least(200,coalesce(p_limit,100))) offset greatest(0,coalesce(p_offset,0))
  ) x;

  select jsonb_build_object(
    'firm',jsonb_build_array('Maitri','Niharika'),
    'state',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(state),''),'Not specified') v from public.customers)s),
    'city',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(city),''),'Not specified') v from public.customers)s),
    'agent',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(agent),''),'Not specified') v from public.customers)s),
    'category',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(category),''),'Not specified') v from public.designs)s),
    'style',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(style),''),'Not specified') v from public.designs)s),
    'fabric',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select distinct coalesce(nullif(btrim(fabric),''),'Not specified') v from public.designs)s),
    'status',jsonb_build_array('Draft','Saved','Locked'),
    'source',jsonb_build_array('customer','staff','unknown'),
    'checkedIn',jsonb_build_array('Yes','No')
  ) into v_options;

  return jsonb_build_object('summary',v_summary,'charts',v_charts,'orders',v_orders,'totalOrders',v_total_orders,'options',v_options,'generatedAt',now());
end;
$$;

revoke all on function public.staff_permission_defaults(text) from public, anon, authenticated;
grant execute on function public.staff_permission_defaults(text) to service_role;
revoke all on function public.staff_has_permission(uuid,text) from public, anon;
grant execute on function public.staff_has_permission(uuid,text) to authenticated, service_role;
revoke all on function public.admin_dashboard(jsonb,text,text,integer,integer) from authenticated;
revoke all on function public.admin_dashboard_v2(jsonb,text,integer,integer) from public, anon;
grant execute on function public.admin_dashboard_v2(jsonb,text,integer,integer) to authenticated;
