-- Safe seed/configuration defaults. No demo customer or order data is inserted.

update public.system_settings
set
  event_name = 'Maitri × Niharika Office Exhibition',
  event_start_date = date '2026-07-19',
  event_end_date = date '2026-07-21',
  registration_enabled = true,
  customer_email_domain = 'customers.maitri.local'
where singleton = true;

-- Optional sample products are deliberately commented out.
-- Add real products through the ProductMaster Google Sheet instead.
-- insert into public.designs(design_no, firm, category, fabric, color, description, active)
-- values ('MT-DEMO-001', 'Maitri', 'Kurta Set', 'Cotton', 'Blue', 'Demo only', true);
