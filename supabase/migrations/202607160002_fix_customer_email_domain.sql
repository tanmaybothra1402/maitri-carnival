update public.system_settings
set
  customer_email_domain = 'customers.maitricarnival.com',
  updated_at = now()
where singleton = true;
