-- 202608010016_crm_customer_column_privacy.sql
--
-- 202608010015 added CRM columns (crm_status, token_amount, token_agreed,
-- has_reference, buyer_type, assigned_to, crm_updated_at/by) to public.customers.
-- That table grants SELECT and UPDATE to `authenticated`, and customers ARE
-- authenticated users with own-row RLS policies (customers_select_own /
-- customers_update_own). So without this migration:
--   * a customer could GET /rest/v1/customers?select=crm_status,token_amount for
--     their OWN row and read their rejection status and token amount, and
--   * a customer could PATCH /rest/v1/customers with crm_status=agreed or
--     token_agreed=true — a privilege escalation.
-- This is the exact designs/master-image leak class (guardrail A1), one step worse
-- because UPDATE is also exposed.
--
-- Fix: replace the table-wide SELECT/UPDATE grants to `authenticated` with
-- COLUMN-LEVEL grants that cover only the pre-existing, customer-owned fields.
-- The 8 CRM columns are granted to NEITHER select nor update, so PostgREST
-- returns 401/403 on them for any customer/anon session. The service role
-- (admin-api) bypasses grants and keeps full access via the CRM RPCs.
--
-- web/user.html reads its profile with .select() and updates exactly
-- {company_name, contact_name, city, state, agent, gstin}; both keep working.
-- Idempotent: grant/revoke are declarative and re-runnable.

revoke select, update on public.customers from authenticated;

-- SELECT: every pre-existing column (parity with the old table-wide grant), minus
-- the 8 CRM columns.
grant select (
  id, phone_e164, company_name, contact_name, city, state, gstin, active,
  created_at, updated_at, checked_in_at, checked_in_by, ordering_started_at,
  edit_deadline, agent, exhibition_id
) on public.customers to authenticated;

-- UPDATE: only the six fields the customer account screen edits. Narrower than
-- the old table-wide UPDATE grant — closes crm_status/token self-service.
grant update (
  company_name, contact_name, city, state, agent, gstin
) on public.customers to authenticated;

-- The three CRM tables were created with RLS on and no policies (row-deny), but
-- Supabase's default privileges still hand `authenticated`/`anon` a table-level
-- grant — which turns a blocked read into a silent 200 [] instead of a hard
-- 401/403. Revoke it so CRM data is a permission error, not an empty list
-- (mirrors the designs / barcode_mappings revokes in 202607170011).
revoke all on public.customer_references from anon, authenticated;
revoke all on public.customer_calls      from anon, authenticated;
revoke all on public.customer_crm_log    from anon, authenticated;
