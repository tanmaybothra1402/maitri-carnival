-- 202608010021_crm_assign_moves_with_module.sql
--
-- Permission-coherence fix. crm.assign was granted by the admin group / rode
-- separately from crm.view+crm.write, which let editing an UNRELATED module
-- (Admin) toggle it and produced an incoherent "assign but can't see" state.
--
-- The three CRM keys now move together. admin-api GROUPS.crm and PRESET_PERMISSIONS
-- .crm and the HTML CRM module checkbox are updated in the same change; this
-- migration is the SQL seed side: staff_permission_defaults('crm') must also carry
-- crm.assign so every place that maps the CRM role agrees.
--
-- Seed-only: staff_permission_defaults is used to seed the FIRST administrator at
-- bootstrap. It does NOT touch any existing staff row — no backfill, no live
-- permission change. (All 23 active staff already hold view+write+assign, restored
-- by the operator; this migration must not alter them.)
--
-- Whole function restated (house style). manager/administrator already carried all
-- three; only the 'crm' preset branch gains crm.assign.

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
      'products.view',true,'products.edit',true,'products.mapping',true
    )
    when 'dispatch' then jsonb_build_object(
      'dispatch.view',true,'dispatch.write',true,'sale.pdf',true
    )
    when 'crm' then jsonb_build_object(
      'crm.view',true,'crm.write',true,'crm.assign',true
    )
    when 'manager' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'crm.view',true,'crm.write',true,'crm.assign',true,
      'admin.slots',true,'admin.bookings',true
    )
    when 'administrator' then jsonb_build_object(
      'reception.view',true,'reception.checkin',true,'reception.register',true,
      'reception.password_reset',true,'reception.customer_control',true,
      'dashboard.view',true,'dashboard.export',true,
      'sale.view',true,'sale.write',true,'sale.previous',true,'sale.pdf',true,'sale.lock',true,
      'products.view',true,'products.edit',true,'products.mapping',true,
      'dispatch.view',true,'dispatch.write',true,
      'crm.view',true,'crm.write',true,'crm.assign',true,
      'admin.slots',true,'admin.bookings',true,'admin.staff',true,'admin.settings',true
    )
    else '{}'::jsonb
  end;
$$;

revoke all on function public.staff_permission_defaults(text) from public, anon, authenticated;
grant execute on function public.staff_permission_defaults(text) to service_role;
