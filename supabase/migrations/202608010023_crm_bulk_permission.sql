-- 202608010023_crm_bulk_permission.sql
--
-- PART B — restrict the three CRM mass-edit actions (bulk assign, bulk set buyer
-- type, bulk set tier) to a new permission key `crm.bulk`, held by exactly two
-- accounts. A stray "select all shown" tap currently rewrites hundreds of records;
-- salespeople should not be able to do that by accident.
--
-- Where the key lives (kept in lock-step; the rest is in admin-api + the admin HTML):
--   • admin-api ALL_PERMISSIONS   — crm.bulk added (so it survives normalizePermissions)
--   • admin-api GROUPS.crm        — crm.bulk deliberately NOT added: the CRM module
--                                   checkbox grants view+write+assign but never bulk
--   • admin-api PRESET_PERMISSIONS— crm.bulk excluded from manager AND administrator
--   • admin-api ACTION_PERMISSIONS— the 3 bulk actions now require crm.bulk (server-side)
--   • admin-api create/updateStaff— a CRM sub-toggle carries crm.bulk on its own boolean
--   • admin HTML                  — CRM module checkbox + a nested "Bulk edits" sub-toggle
--
-- staff_permission_defaults (the bootstrap seed for the FIRST administrator) is
-- deliberately left WITHOUT crm.bulk. Bulk is not a preset capability — not even
-- for administrator — so a newly-seeded admin does not receive it. The only holders
-- are the two accounts backfilled below. No change to that function is required and
-- none is made.

-- Backfill: grant crm.bulk to exactly the two named accounts, by staff_id. Merge the
-- single key into the existing permissions jsonb so nothing else changes. Idempotent.
update public.staff_profiles
set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object('crm.bulk', true)
where staff_id in ('tanmaybothra1402-2fb5', 'ganesh');

-- Guard: this migration must touch exactly the two intended rows and nobody else.
-- Fail loudly if the staff_ids drifted, rather than silently granting to the wrong
-- set or nobody.
do $$
declare
  n_target int;
  n_holders int;
begin
  select count(*) into n_target
  from public.staff_profiles
  where staff_id in ('tanmaybothra1402-2fb5', 'ganesh');
  if n_target <> 2 then
    raise exception 'crm.bulk backfill expected 2 target accounts, found %', n_target;
  end if;

  select count(*) into n_holders
  from public.staff_profiles
  where (permissions ->> 'crm.bulk')::boolean is true;
  if n_holders <> 2 then
    raise exception 'crm.bulk should be held by exactly 2 accounts after backfill, found %', n_holders;
  end if;
end $$;
