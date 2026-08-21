-- 202608010032_agent_canonicalisation.sql
--
-- Canonicalise customers.agent per Tanmay's validated 41-agent mapping (162 variants,
-- 0 unmatched against live data — validated read-only BEFORE this migration was written).
-- Every changed row's original is preserved in agent_remap_log (service-role only) for a
-- clean revert, so this is NOT a hand-run destructive edit. customers.agent stays (the
-- dashboard/directory/agent-charts read it) but is now canonical; public.agents is seeded
-- from the cleaned values and customer_crm.agent_id links to it.
--
-- Rules honoured: unlisted values pass through UNCHANGED as their own canonical agent;
-- the blank list -> '' (customers.agent is NOT NULL; '' is the existing "no agent"
-- convention — 485 rows already hold '' — which the dashboard renders "Not specified").
-- Left SEPARATE deliberately (pending a staff decision, DO NOT
-- MERGE): Ykd/Ykdk/Ykdk agency, R.M.Patel vs Rajesh M. Patel, Vishal-Khatri; also
-- KUSHAL N. SHAH != KANAK N. SHAH and SHIV SHANKAR != SHANKAR. Do NOT "fix" the MRK
-- design here (separate concern).

create table if not exists public.agent_remap_log (
  customer_id uuid not null,
  old_agent   text,
  new_agent   text,
  created_at  timestamptz not null default now()
);
alter table public.agent_remap_log enable row level security;
revoke all on table public.agent_remap_log from public, anon, authenticated;
grant all  on table public.agent_remap_log to service_role;

-- validated mapping, materialised once for the log + the remap
drop table if exists public._agent_map;
create table public._agent_map (variant text primary key, canonical text);
insert into public._agent_map (variant, canonical) values
 ('RAGHANI TRADELINK PVT. LTD. - ADI','RAGHANI TRADELINK'),('Raghani','RAGHANI TRADELINK'),('Ragani','RAGHANI TRADELINK'),('raghani','RAGHANI TRADELINK'),('Rangani','RAGHANI TRADELINK'),('RAGHANI TRADELINK PVT. LTD','RAGHANI TRADELINK'),('RAGHANI TRADELINK SERVICES - AHMEDABAD','RAGHANI TRADELINK'),('Ragani agency','RAGHANI TRADELINK'),('Raghani agency','RAGHANI TRADELINK'),('Raghani tradlink','RAGHANI TRADELINK'),('RAGHANI TRADLINK AHMD','RAGHANI TRADELINK'),('Ragini','RAGHANI TRADELINK'),('Rajani','RAGHANI TRADELINK'),('Rajhani','RAGHANI TRADELINK'),('Abhishek (Raghani)','RAGHANI TRADELINK'),
 ('V. MANESH TEXTILES - ADI','V. MANESH TEXTILES'),('V. MANESH TEXTILE - ADI','V. MANESH TEXTILES'),('V. Manesh','V. MANESH TEXTILES'),('V manesh','V. MANESH TEXTILES'),('V MANESH TEXTILE','V. MANESH TEXTILES'),('V Manesh textiles','V. MANESH TEXTILES'),('V maniesh','V. MANESH TEXTILES'),('V manish','V. MANESH TEXTILES'),('V Manish','V. MANESH TEXTILES'),('V. MANESH ADI','V. MANESH TEXTILES'),('V. MANESH AHMD','V. MANESH TEXTILES'),('V. MANISH - ADI','V. MANESH TEXTILES'),('V. MANISH AHMD','V. MANESH TEXTILES'),
 ('DIRECT','DIRECT'),('Direct','DIRECT'),('direct','DIRECT'),('Dirct','DIRECT'),('Dairect','DIRECT'),('Director','DIRECT'),('Self','DIRECT'),('My self','DIRECT'),
 ('S. GOKULCHAND - ADI','S. GOKULCHAND'),('GOKUL CHAND','S. GOKULCHAND'),('S Gokul','S. GOKULCHAND'),('S gokul chand','S. GOKULCHAND'),('S Gokul Chand','S. GOKULCHAND'),('S Gokulchand','S. GOKULCHAND'),('s hokul chand','S. GOKULCHAND'),('S. Gokulchand','S. GOKULCHAND'),
 ('G.N.G. TRADELINK - AHMEDABAD','G.N.G. TRADELINK'),('GNG Tradelink','G.N.G. TRADELINK'),('G. N. G TRADELINK AHMEDABAD','G.N.G. TRADELINK'),('G.N.G. TRADLINK AHMD','G.N.G. TRADELINK'),('Gng','G.N.G. TRADELINK'),('GNG','G.N.G. TRADELINK'),('GNG tradelink','G.N.G. TRADELINK'),
 ('KANAK N. SHAH - ADI','KANAK N. SHAH'),('Kanak n shah','KANAK N. SHAH'),('Kanak N shah','KANAK N. SHAH'),('Kanak nshah','KANAK N. SHAH'),('Kanak K shah','KANAK N. SHAH'),('Kanak and sah','KANAK N. SHAH'),
 ('Y. D. TEXTILES - AMBALA CITY','Y. D. TEXTILES'),('YD AGENCY','Y. D. TEXTILES'),('Yd','Y. D. TEXTILES'),('YD','Y. D. TEXTILES'),('Da yd','Y. D. TEXTILES'),('DA YD','Y. D. TEXTILES'),
 ('KISHANCHAND & CO. - ADI','KISHANCHAND & CO.'),('Kishan chand','KISHANCHAND & CO.'),('Kishan Chand and company','KISHANCHAND & CO.'),('Kishanchand and co','KISHANCHAND & CO.'),
 ('DAKHXESH KHATRI GLOBAL SOURCING PVT. LTD. - AHMEDABAD','DAKHXESH KHATRI'),('Dakshesh khatri','DAKHXESH KHATRI'),('Dakhxesh Khatri','DAKHXESH KHATRI'),('Dakhxesh khatri Ahmedabad','DAKHXESH KHATRI'),('DAKSHESH KHATRI','DAKHXESH KHATRI'),
 ('Gopani','GOPANI AGENCY'),('GOPANI AGENGY','GOPANI AGENCY'),('Gopani agency','GOPANI AGENCY'),('Gopani Agency','GOPANI AGENCY'),
 ('SHANKAR AGENCY - ADI','SHANKAR AGENCY'),('Shankar agent','SHANKAR AGENCY'),('Shankar agency','SHANKAR AGENCY'),('Shanker agency','SHANKAR AGENCY'),
 ('SHIV SHANKAR AGENCY - MUMBAI','SHIV SHANKAR AGENCY'),('Shiv shankar agency','SHIV SHANKAR AGENCY'),
 ('SHAILESH SAVLA - MUMBAI','SHAILESH SAVLA'),('Shailesh savla','SHAILESH SAVLA'),('Shailesh sawla','SHAILESH SAVLA'),('Sailesh salva','SHAILESH SAVLA'),('Shailesh','SHAILESH SAVLA'),
 ('NAITIK SAVLA - MUMBAI','NAITIK SAVLA'),('Naitik Savla','NAITIK SAVLA'),
 ('SAINATH TEXTILE AGENCY - ADI','SAINATH TEXTILE AGENCY'),('Sainath textile agency','SAINATH TEXTILE AGENCY'),('Sai Nath textile agnecy','SAINATH TEXTILE AGENCY'),('Shree nath textile agency','SAINATH TEXTILE AGENCY'),
 ('SHRI RADHA KRISHNA TEXTILE AGENCY - ADI','SHRI RADHA KRISHNA TEXTILE AGENCY'),('Radha Krishna agency','SHRI RADHA KRISHNA TEXTILE AGENCY'),('Radhakrishna agencies','SHRI RADHA KRISHNA TEXTILE AGENCY'),('Shree radhe Krishna agency Ahmedabad','SHRI RADHA KRISHNA TEXTILE AGENCY'),
 ('PRANSHI FASHION','PRANSHI FASHION'),('PRANSHI FASHION AHMD','PRANSHI FASHION'),('Pranshi fashion ahmedabad','PRANSHI FASHION'),('PRANSHI FASHION AHMEDABAD','PRANSHI FASHION'),
 ('Aditya','ADITYA GROUP'),('Aditya group','ADITYA GROUP'),('Aditya agency','ADITYA GROUP'),('Aditya Group','ADITYA GROUP'),
 ('RASIKLAL SONS INTERMEDIARIES LLP - MUMBAI','RASIKLAL SONS INTERMEDIARIES LLP'),('RASIKLAL SONS INTERMEDIARIES LLP - BBY','RASIKLAL SONS INTERMEDIARIES LLP'),('Rasik lal','RASIKLAL SONS INTERMEDIARIES LLP'),
 ('KAMYAA AGENCY - AHMEDABAD','KAMYAA AGENCY'),('Kamya agency','KAMYAA AGENCY'),
 ('GAYATRI AGENCY - AHMEDABAD','GAYATRI AGENCY'),('Gaytari Agency','GAYATRI AGENCY'),
 ('AHUJA AGENCY - AHMEDABAD','AHUJA AGENCY'),('Ahuja agency','AHUJA AGENCY'),
 ('ARJUN TEXTILE AGENCY - ADI','ARJUN TEXTILE AGENCY'),('Arjun textile agency','ARJUN TEXTILE AGENCY'),
 ('BHOLESHWAR AGENCY - AHMEDABAD','BHOLESHWAR AGENCY'),('Bholeshwar','BHOLESHWAR AGENCY'),
 ('CHANCHAL CREATION - ADI','CHANCHAL CREATION'),('Chanchal agency','CHANCHAL CREATION'),
 ('JKV AGENCY - AHMEDABAD','JKV AGENCY'),('Jkv agency','JKV AGENCY'),
 ('Mahalaxmi agencies','MAHALAXMI AGENCIES'),('Mahalaxmi Agencies','MAHALAXMI AGENCIES'),
 ('Rm dubey','RM DUBEY'),('RM dubey','RM DUBEY'),
 ('RK agency','RK AGENCY'),('Rk agency','RK AGENCY'),
 ('Krr agencies','KRR AGENCY'),('Krr agency','KRR AGENCY'),
 ('brs','BRS'),('Brs','BRS'),
 ('M k jain','M K JAIN'),('MK JAIN','M K JAIN'),
 ('Kp','KP AGENCY'),('Kp agency','KP AGENCY'),
 ('SIDHARTH SHAH','SIDHARTH SHAH'),('Siddharth sha','SIDHARTH SHAH'),
 ('SHUBHAM PRAKASH JAIN - AHMEDABAD','SHUBHAM PRAKASH JAIN'),('Shubham prakash','SHUBHAM PRAKASH JAIN'),
 ('GH TEXTILE','GH TEXTILE'),('GH','GH TEXTILE'),
 ('DNK FASHION - AHMD','DNK FASHION'),('Dnk','DNK FASHION'),
 ('Pragnesh','PRAGNESH'),('Pragnesh bhai','PRAGNESH'),
 ('MAHESH K. JAISINGH - MUMBAI','MAHESH K. JAISINGH'),('Mahesh jaisingh','MAHESH K. JAISINGH'),
 ('KISHORE H. NATHANI - VADODARA','KISHORE H. NATHANI'),('Kishor nathani','KISHORE H. NATHANI'),
 ('KUSHAL N. SHAH - AHMEDABAD','KUSHAL N. SHAH'),('Kushal shah','KUSHAL N. SHAH'),
 ('NA','__BLANK__'),('Nil','__BLANK__'),('No','__BLANK__'),('No agent','__BLANK__'),('Xxx','__BLANK__'),('NEW','__BLANK__'),('NEW PARTY','__BLANK__'),('Agency','__BLANK__'),('+977-9827492058','__BLANK__'),('0477190772','__BLANK__');

-- preserve every row that will change
insert into public.agent_remap_log (customer_id, old_agent, new_agent)
  select c.id, c.agent, case when m.canonical = '__BLANK__' then '' else m.canonical end
  from public.customers c
  join public._agent_map m on btrim(c.agent) = m.variant;

-- canonicalise
update public.customers c
  set agent = case when m.canonical = '__BLANK__' then '' else m.canonical end,
      updated_at = now()
  from public._agent_map m
  where btrim(c.agent) = m.variant;

drop table public._agent_map;

-- seed agents from the cleaned values (41 canonical + every pass-through)
insert into public.agents (name)
  select distinct btrim(agent) from public.customers
  where agent is not null and btrim(agent) <> ''
  on conflict (name_key) do nothing;

-- link customer_crm.agent_id to the seeded agents
insert into public.customer_crm (customer_id, agent_id)
  select c.id, a.id
  from public.customers c
  join public.agents a on a.name_key = regexp_replace(upper(btrim(c.agent)), '[^A-Z0-9]', '', 'g')
  where c.agent is not null and btrim(c.agent) <> ''
  on conflict (customer_id) do update set agent_id = excluded.agent_id;
