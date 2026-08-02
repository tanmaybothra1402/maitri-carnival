-- Grant products.create to existing product-managing staff.
--
-- Brief 5 adds in-app product creation (take a photo, fill details, save), gated
-- on a new products.create permission key. admin-api already grants it to new
-- staff who get the Products module (GROUPS.products) and to the products / manager
-- / administrator presets. This backfills the key for EXISTING staff who already
-- manage products — anyone holding products.edit — so the new control surfaces for
-- them without recreating their accounts. (bootstrap returns the stored permission
-- map; normalizePermissions only fills absent keys as false, it never grants.)
--
-- Not needed here, and deliberately omitted:
--   * No CHECK-constraint change: products.create is a permissions-map key, not a
--     preset value or a default_section value.
--   * No staff_permission_defaults() change: that function seeds the first admin
--     only; live staff creation computes permissions in admin-api, already updated.
--
-- Idempotent: the WHERE guard skips rows that already have it.

update public.staff_profiles
set permissions = permissions || jsonb_build_object('products.create', true),
    updated_at = now()
where coalesce(permissions->>'products.edit', '') = 'true'
  and coalesce(permissions->>'products.create', '') <> 'true';
