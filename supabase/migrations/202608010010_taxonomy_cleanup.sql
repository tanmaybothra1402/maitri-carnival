-- Catalogue taxonomy cleanup (Maitri Carnival).
--
-- Diagnosis: `style` has always held the FABRIC, and `fabric` has held the
-- garment TYPE (or 'Box Pcs' for unstitched goods). This reassigns each value to
-- the column it belongs in *by value* (not a blind swap — so rows where a fabric
-- already sits in `fabric` are handled correctly), canonicalising spelling/case in
-- the same pass, and deletes the DEMO test product.
--
-- Folded-in resolutions (confirmed): blank-category MR rows -> 'Garment';
-- style='Unstiched' -> style='Box Pcs' (fabric already correct); Burberry +
-- Burberry Silk -> 'Burberry Silk'.
--
-- Image-resolved fabrics: Giraf (Ziraf silk merges in), Salsa, H.O. Fabric.
-- MR-4280 fixed per-row (colour 'Mustard' -> fabric Chinnon, style Plazo).
-- Nothing is held out now — every row is classified.
--
-- NOT in this migration: dropping designs.color. It is read by lookup_barcode and
-- order_state_json (both customer-facing), the dashboard drill, and three admin-api
-- selects; that is a separate coordinated change.
--
-- Idempotent: re-running reassigns canonical values to themselves (no-op).

-- 1) Blank-category rows -> Garment. Verified: all 6 are MR- (Maitri), and every
--    MR- design is Garment. Scoped to the MR prefix so a future non-MR blank is
--    surfaced rather than silently defaulted.
update public.designs
set category = 'Garment', updated_at = now()
where btrim(category) = ''
  and upper(substring(btrim(design_no) from '^[A-Za-z]+')) = 'MR';

-- 2) Reclassify style<->fabric by value + canonicalise (the blank rows just
--    categorised are now eligible).
with vocab(raw, canon, kind) as (values
  -- fabrics -> `fabric`
  ('chinnon','Chinnon','fabric'),
  ('mul chanderi','Mul Chanderi','fabric'),
  ('linen','Linen','fabric'), ('lilen','Linen','fabric'),
  ('tissue','Tissue','fabric'),
  ('muslin','Muslin','fabric'),
  ('russian silk','Russian Silk','fabric'),
  ('cotton','Cotton','fabric'),
  ('crepe','Crepe','fabric'),
  ('jamdani','Jamdani','fabric'),
  ('organza','Organza','fabric'),
  ('butter silk','Butter Silk','fabric'),
  ('crush tissue','Crush Tissue','fabric'),
  ('handloom cotton','Handloom Cotton','fabric'),
  ('kota','Kota','fabric'),
  ('maheshwari','Maheshwari','fabric'),
  ('jamdani lagdi patta','Jamdani Lagdi Patta','fabric'),
  ('organza twill','Organza Twill','fabric'),
  ('linen tissue','Linen Tissue','fabric'),
  ('georgette','Georgette','fabric'),
  ('denim','Denim','fabric'),
  ('jecard','Jacquard','fabric'),
  ('kanjivaram','Kanjivaram','fabric'),
  ('tussar','Tussar','fabric'),
  ('tissue lining','Tissue Lining','fabric'),
  ('glass tissue','Glass Tissue','fabric'),
  ('burberry','Burberry Silk','fabric'), ('burberry silk','Burberry Silk','fabric'),
  ('giraf','Giraf','fabric'), ('ziraf silk','Giraf','fabric'),  -- same fabric; the split was NRK vs MU data entry, not two materials
  ('salsa','Salsa','fabric'),
  ('h.o. fabric','H.O. Fabric','fabric'),  -- a.k.a. "H.O. Silk" elsewhere; only "H.O. Fabric" appears in the data — do NOT add "H.O. Silk" as a separate value
  -- garment types (+ the unstitched marker 'Box Pcs') -> `style`
  ('box pcs','Box Pcs','style'),
  ('unstiched','Box Pcs','style'),   -- style='Unstiched' + a real fabric -> style becomes Box Pcs
  ('co-ord set','Co-ord Set','style'),
  ('kurta pant duppata','Kurta Pant Dupatta','style'),
  ('plazo','Plazo','style'),
  ('sharara set','Sharara Set','style'),
  ('work co-ord set','Work Co-ord Set','style'), ('work co - ord','Work Co-ord Set','style'),
  ('bustier','Bustier','style'),
  ('apreen cord set','Apreen Co-ord Set','style'), ('apreen co-ord set','Apreen Co-ord Set','style'),
  ('farshi set','Farshi Set','style'),
  ('kurta pant','Kurta Pant','style'),
  ('skirt','Skirt','style'),
  ('anarkali','Anarkali','style'),
  ('bell bottom','Bell Bottom','style'),
  ('gown','Gown','style'),
  ('angrakha','Angrakha','style'),
  ('caftan','Caftan','style'),
  ('shirt','Shirt','style'),
  ('blazer sets','Blazer Set','style'),
  ('peplum','Peplum','style')
)
update public.designs d
set fabric = f.canon,
    style  = s.canon,
    updated_at = now()
from vocab f, vocab s
where f.kind = 'fabric' and s.kind = 'style' and f.raw <> s.raw
  -- the row's two cells are exactly {this fabric, this garment type}, in either order
  and lower(btrim(d.style))  in (f.raw, s.raw)
  and lower(btrim(d.fabric)) in (f.raw, s.raw)
  -- hold-outs: skip blank-category rows and the DEMO product
  and btrim(d.category) <> ''
  and d.design_no <> 'DEMO'
  -- only rewrite when something actually changes (keeps updated_at honest)
  and (d.fabric is distinct from f.canon or d.style is distinct from s.canon);

-- 3) Per-row fix: MR-4280 carried the COLOUR "Mustard" in style. Its real fabric
--    is Chinnon and garment type Plazo. One-off correction, not a vocab rule.
update public.designs
set style = 'Plazo', fabric = 'Chinnon', updated_at = now()
where design_no = 'MR - 4280';

-- 4) Remove the DEMO test product (verified: 0 order lines, 0 barcode mappings).
delete from public.designs where design_no = 'DEMO';
