update public.system_settings
set
  customer_email_domain = 'accounts.maitricarnival.app',
  updated_at = now()
where singleton = true;

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
  select *
  into v_settings
  from public.system_settings
  where singleton = true;

  -- Admin users use real email addresses and must not become customers.
  if split_part(lower(coalesce(new.email, '')), '@', 2)
     <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  v_phone :=
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'phone_e164', ''),
      '\D',
      '',
      'g'
    );

  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  if split_part(lower(new.email), '@', 1) <> ('c' || v_phone) then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code :=
      coalesce(new.raw_user_meta_data ->> 'access_code', '');

    if encode(extensions.digest(v_access_code, 'sha256'), 'hex')
       <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company :=
    btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));

  v_contact :=
    btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));

  v_city :=
    btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));

  v_state :=
    btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));

  v_gstin :=
    upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;

  if length(v_contact) < 2 then
    raise exception 'CONTACT_NAME_REQUIRED';
  end if;

  insert into public.customers(
    id,
    phone_e164,
    company_name,
    contact_name,
    city,
    state,
    gstin
  )
  values (
    new.id,
    v_phone,
    v_company,
    v_contact,
    v_city,
    v_state,
    v_gstin
  );

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;
