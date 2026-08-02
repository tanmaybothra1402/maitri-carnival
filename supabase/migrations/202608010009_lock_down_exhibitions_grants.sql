-- Lock down the exhibitions table: service-role only.
--
-- exhibitions was created in 202608010001 and picked up the public-schema default
-- privileges, so `authenticated` (which includes every customer) currently holds
-- SELECT/INSERT/UPDATE/DELETE/TRUNCATE on it. It is masked today only because RLS
-- is enabled with zero policies (deny-all) — but that is a landmine: a single
-- permissive policy added later would expose exhibition config to customers.
--
-- The table is only ever read/written through service-role Edge Functions
-- (admin-api, customer-auth), which bypass RLS and these grants. So revoking all
-- caller privileges has no functional impact and removes the landmine.

revoke all on public.exhibitions from anon, authenticated;

-- Belt and braces: RLS stays on with no policy, so even the (now revoked) grants
-- could not be used. Leave RLS enabled.
alter table public.exhibitions enable row level security;
