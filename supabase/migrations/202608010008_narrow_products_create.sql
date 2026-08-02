-- Narrow products.create to admin-tier staff only.
--
-- 202608010007 backfilled products.create onto every product-editor (14 staff).
-- That is too broad: creating a product can overwrite catalogue data, so it should
-- sit with the admin-settings tier, not with everyone who can edit a product.
--
-- This revokes the key from anyone who does not hold admin.settings. The matching
-- admin-api change moves products.create out of GROUPS.products and into
-- GROUPS.admin (and out of the products/manager presets), so it now tracks
-- admin.settings everywhere — and a later staff edit (which recomputes permissions
-- from the group checkboxes) will not silently re-grant it.
--
-- Idempotent: only touches rows that currently have the key without admin.settings.

update public.staff_profiles
set permissions = permissions - 'products.create',
    updated_at = now()
where coalesce(permissions->>'admin.settings', '') <> 'true'
  and (permissions ? 'products.create');
