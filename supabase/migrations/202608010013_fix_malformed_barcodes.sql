-- 202608010013_fix_malformed_barcodes.sql
--
-- Four active rows in public.barcode_mappings can never match a printed sticker.
-- Each was verified individually against production on 2026-08-17 (barcode bytes
-- checked in hex — the space in the two malformed rows is a real 0x20):
--
--   'MC- 0941' -> NRK-8900 : a CLEAN 'MC-0941' already exists and is active on the
--        same design (clean mapped 13 Aug, malformed 11 Aug). DEACTIVATE the
--        malformed row. A rename would collide with the existing clean row.
--   'MC- 0954' -> NRK-8899 : no clean 'MC-0954' exists. RENAME the barcode to
--        'MC-0954'.
--   'MC-01'    -> MR-4453  : LEFT UNTOUCHED on purpose. Not a 4-digit sticker
--        number; the intended value is unknown. Do not guess, do not delete.
--   'MC-0837'  -> MR-8842  : target design MR-8842 is INACTIVE, so the mapping
--        cannot function. DEACTIVATE the mapping (reversible).
--
-- Deliberately NOT `update ... set barcode = replace(barcode,' ','')`: that would
-- rewrite 'MC- 0941' to 'MC-0941' and collide with the existing clean row.
--
-- Idempotent: every statement is guarded (`is distinct from` / `not exists`) and
-- re-runnable. Touches only the four named rows. No functions, so no grant changes.
-- The barcode_mappings_updated_at trigger stamps updated_at on each UPDATE.

begin;

-- 1. Deactivate the malformed 'MC- 0941'. The clean 'MC-0941' stays active.
update public.barcode_mappings
   set active = false
 where barcode = 'MC- 0941'
   and active is distinct from false;

-- 2. Rename 'MC- 0954' -> 'MC-0954'. Guarded so a re-run (malformed row already
--    gone) is a no-op, and so it can never overwrite a clean row that exists.
update public.barcode_mappings
   set barcode = 'MC-0954'
 where barcode = 'MC- 0954'
   and not exists (
     select 1 from public.barcode_mappings b2 where b2.barcode = 'MC-0954'
   );

-- 3. 'MC-01' (-> MR-4453) is intentionally left untouched.

-- 4. Deactivate 'MC-0837' (maps to inactive design MR-8842).
update public.barcode_mappings
   set active = false
 where barcode = 'MC-0837'
   and active is distinct from false;

commit;
