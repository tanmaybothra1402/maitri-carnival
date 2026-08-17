-- 202608010014_normalise_design_numbers.sql
--
-- Normalise malformed ACTIVE design numbers toward the house convention
-- `XX - NNNN` / `XX - NNNN (B)`. Verified against production 2026-08-17.
--
-- SCOPE NOTE (important): the checkpoint premise was "8 inert collision rows".
-- Production actually has 21 malformed active designs. Only the INERT ones
-- (0 active barcodes, 0 order_items, 0 dispatch_lines) are safe to change here,
-- because design_no renames cascade to order_items + barcode_mappings ONLY
-- (both ON UPDATE CASCADE) and NOT to dispatch_lines (no FK). This migration
-- touches the 9 inert rows and deliberately leaves the 12 non-inert ones for a
-- human decision (they carry live barcodes/orders, one carries a dispatch line,
-- and one canonical target already exists as an inactive row). See the report.
--
-- Idempotent: every statement is guarded (`and active` / `not exists`) and
-- re-runnable. Deactivations only touch rows proven inert; renames only fire
-- when the malformed row is present and the canonical target is free.

begin;

-- (1) DEACTIVATE inert malformed members whose canonical twin already exists and
--     is active (renaming would collide, exactly like the MC-0941 case in ...0013).
--     All four confirmed inert: 0 active barcodes, 0 order_items, 0 dispatch_lines.
update public.designs set active = false where design_no = 'MR - 4281 B'  and active;   -- twin: MR - 4281 (B)
update public.designs set active = false where design_no = 'MR -  4349'   and active;   -- twin: MR - 4349 (double space)
update public.designs set active = false where design_no = 'MR -  4396'   and active;   -- twin: MR - 4396 (double space)
update public.designs set active = false where design_no = 'NRK -8531'    and active;   -- twin: NRK - 8531 (no space)

-- (2) RENAME inert orphans (no canonical twin) to canonical form. Guarded so a
--     re-run is a no-op and so a rename can never overwrite an existing row.
--     Cascades to order_items/barcode_mappings — but all four are fully inert.
update public.designs set design_no = 'MR - 3574 (B)'
  where design_no = 'MR - 3574 B'   and not exists (select 1 from public.designs d2 where d2.design_no = 'MR - 3574 (B)');
update public.designs set design_no = 'MR - 4374 (B)'
  where design_no = 'MR - 4374 ( B )' and not exists (select 1 from public.designs d2 where d2.design_no = 'MR - 4374 (B)');
update public.designs set design_no = 'MU - 0312'
  where design_no = 'MU  - 0312'    and not exists (select 1 from public.designs d2 where d2.design_no = 'MU - 0312');
update public.designs set design_no = 'NRK - 8876'
  where design_no = 'NRK -8876'     and not exists (select 1 from public.designs d2 where d2.design_no = 'NRK - 8876');
update public.designs set design_no = 'NRK - 8890'
  where design_no = 'NRk - 8890'    and not exists (select 1 from public.designs d2 where d2.design_no = 'NRK - 8890');

-- DELIBERATELY NOT TOUCHED (12 non-inert malformed rows — need a human decision):
--   Spaced-bracket `( B )` / `( B)` with live barcodes/orders:
--     BS - 1427 ( B ), KT - 4788 ( B ), KT - 5338 ( B), KT - 5353 ( B),
--     KT - 5766 ( B ), MR - 4388 ( B ), MU - 0406 ( B ), MU - 0545 ( B )
--   MU - 0416 ( B )  -> has a dispatch_line; a rename would ORPHAN it (no cascade).
--   MR -  4378, MR- 4408 -> live barcodes/orders (cascade-safe but out of the
--     inert scope this checkpoint authorised).
--   MR- 4257 -> canonical target `MR - 4257` already exists (inactive); cannot
--     rename (PK collision) and cannot deactivate (it holds the live orders).

commit;
