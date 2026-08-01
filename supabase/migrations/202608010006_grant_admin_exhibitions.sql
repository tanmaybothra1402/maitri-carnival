-- Grant the new admin.exhibitions permission to existing full admins.
--
-- Piece 3 of the multi-exhibition work adds an "Exhibitions" admin sub-tab and an
-- app-bar exhibition switcher to the console, both gated on the admin.exhibitions
-- permission key. admin-api already knows the key (it is in ALL_PERMISSIONS,
-- GROUPS.admin and the administrator/manager presets from migration-less TS
-- changes), so every NEW admin created from here forward receives it.
--
-- But permissions are a JSONB map stored per row on staff_profiles, and bootstrap
-- returns the STORED map (normalizePermissions only fills absent keys as false, it
-- never grants). So existing admins have admin.exhibitions = absent/false and would
-- never see the new controls until their account was recreated. This backfills it.
--
-- Scope: anyone who already holds admin.settings — the top admin tier, where
-- system configuration already lives. Exhibition management is a peer of it.
--
-- Not needed here, and deliberately omitted:
--   * No CHECK-constraint change: admin.exhibitions is a permissions map key, not a
--     preset value or a default_section value.
--   * No staff_permission_defaults() change: that DB function seeds the very first
--     administrator only; live staff creation computes permissions in admin-api,
--     which was already updated. Touching it would change nothing at runtime.
--
-- Idempotent: the WHERE guard skips rows that already have it, so re-running is a
-- no-op.

update public.staff_profiles
set permissions = permissions || jsonb_build_object('admin.exhibitions', true),
    updated_at = now()
where coalesce(permissions->>'admin.settings', '') = 'true'
  and coalesce(permissions->>'admin.exhibitions', '') <> 'true';
