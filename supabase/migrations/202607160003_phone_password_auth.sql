-- Use Supabase's native phone + password identity.
-- Email-only users are admins and are not provisioned as customers.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_metadata_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  -- Admin users authenticate with a real email and have no phone identity.
  if nullif(btrim(coalesce(new.phone, '')), '') is null then
    return new;
  end if;

  select *
  into v_settings
  from public.system_settings
  where singleton = true;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  -- Supabase stores the phone in E.164 form, such as +919876543210.
  v_phone := regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');

  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  -- Confirm that browser metadata matches the authenticated phone.
  v_metadata_phone :=
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'phone_e164', ''),
      '\D',
      '',
      'g'
    );

  if v_metadata_phone <> '' and v_metadata_phone <> v_phone then
    raise exception 'PHONE_METADATA_MISMATCH';
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
