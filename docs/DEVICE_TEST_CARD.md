# Device test card — one pass, before the floor

Everything below shipped and has met **only jsdom**. Run it once on real devices.
Each line is **do → expect**; an unexpected result is a bug, not ambiguity.

Order is deliberate: the **combined order-entry screen (Section A) is the largest
untested exposure** — it is the path *every* order takes and a wrong firm-routing
or a dropped per-firm save is *silent*, unlike a scanner miss which is visible at
the counter. **Do Section A first.**

Distribute/open: `admin-a106dc80eeabd658.html?v=269ae0e`

---

## A. Combined order entry — Sale Order (do this FIRST)

Use a throwaway test customer. Open **Sale Order** and pick that customer.

1. **Layout** → there is **one** scan/type box and **no** Maitri/Niharika toggle above it.
2. **Maitri-only order** → add 2–3 Maitri designs, set quantities, **Save**. Then Recent orders → **View** the order and **Download PDF** → all designs present, in the Maitri document, sets/pcs correct.
3. **Niharika-only order** → repeat with Niharika designs → admin view + PDF correct, Niharika document.
4. **Mixed order, one sitting** → add some Maitri **and** some Niharika designs to the same customer. Check the header shows **two subtotals (Maitri / Niharika) + a combined total**, all correct. **Save** → **two** orders exist (one per firm); the admin view shows both; **each firm's PDF is separate and correct**.
5. **Mixed order, one firm's save fails** → add Maitri + Niharika designs; **turn wifi off just after tapping Save** (or airplane mode). → one firm shows saved, the other shows **"failed — retry"** (never a silent partial). Turn wifi back on, **Save** again → the failed firm now saves, **and** the already-saved firm's quantities are **unchanged, not doubled** (this is the request-id reuse / no-double-write path).
6. **Per-row M/N move** → add a **"Both"** design (its badge is an **M/N** toggle), tap **N** before saving, **Save** → the design lands under **Niharika** (verify in the admin view / Niharika PDF), not Maitri.
7. **Downstream** → after #4, open **Dispatch** for that customer and the **Dashboard** → both firms' orders read correctly, per firm (nothing merged, nothing missing).
8. **Manual line in the PDF** → any design added by typing (no barcode) → the order PDF renders it with a **blank barcode** column — no `undefined`/`null`/broken column.

---

## B. Scanner — needs a real **iPhone** and a real **Android**

> If the physical **MC-** stickers are **not printed yet**, run 1–9 against a QR shown
> on another screen: that validates the modal, lens pick, focus distance and torch,
> but a screen-QR **cannot settle the symbology question**, so the **Wide barcode**
> toggle (line 10) stays untested and the physical-run/format question stays open.

1. iPhone: Sale → tap camera → modal fills the screen, **square** target box, sharp focus on a sticker ~10 cm away.
2. iPhone: hold a sticker **touching** the lens, then pull back → won't decode touching; decodes by ~8–12 cm (confirms the **main lens**, not the ultra-wide).
3. iPhone: scan at **~25 cm** → decodes within ~1 s.
4. Android: same three distances → decodes; should feel faster (BarcodeDetector path).
5. iPhone: look for the torch button → **not shown** (unsupported) — not a dead button.
6. Android: toggle torch on/off in a shadowed stall → light toggles; a glare-hidden sticker now decodes.
7. Both: **bright hall light** vs **shadowed stall** → decodes in both; note any glare distance that fails.
8. Both: **10 consecutive** different stickers, single mode, **stopwatch 2nd→10th** → steady cadence, no reopen hangs.
9. Both: a **creased/damaged** sticker → decodes in a couple seconds, or fails cleanly (no freeze).
10. If any sticker won't scan as QR → tap **Wide barcode** → it should then decode (means the run is 1D — tell me and I'll confirm the format).
11. Both: after a scan in **single (One-shot)** mode → modal **closes**.
12. Both: leave Sale / background the phone with the modal open → camera light **off** (no lingering stream).

### B2. Stay-open batch scanning
13. **Batch** mode, scan **10 different** stickers without touching the screen → all 10 land, camera **never reopens**, count climbs.
14. **Batch single sale**, scan the **same** design twice (>2.5 s apart) → quantity **increments** (no duplicate line, no error).
15. Hold **one sticker in frame** in batch → it adds **once**, not repeatedly (the ~2.5 s same-code lockout).
16. **Batch multi-customer** (3 customers), scan a design, then **scan it again** → the second scan is a **no-op** with *"already added for all 3 — set quantities in the matrix"*; the matrix is unchanged.
17. **Undo** in batch after a scan → the last line is removed / decremented.
18. **Popup** mode, scan → the qty sheet opens and the camera **freezes**; close via **Done**, then again via **✕**, then via **tap-outside** → the camera **resumes** every time (no frozen "dead scanner").
19. **Toggle the mode**, close and reopen the scanner → the mode is **remembered** (persisted).
20. Leave a **batch** scanner open ~**90 s** untouched → *"Scanner paused — tap to resume"*; tap → resumes.

---

## C. Manual entry + stale catalogue

21. Type `mu0322` in the scan box (no barcode) → resolves to **MU - 0322**.
22. Type `MU-0322`, `MU 0322`, `mu 0322` → **all** resolve identically.
23. Type a Niharika design (combined screen just routes it to Niharika; on the *multi* screen while on the Maitri tab) → the friendly firm message, never `DESIGN_..._DOES_NOT_BELONG_TO_...`.
24. Have Products **create a design**, then type it on a sale tablet **open since before it existed** → *"Checking catalogue…"* then it resolves (refresh-on-miss at real latency).
25. Type a genuinely **unknown** number **twice within 15 s** → refused both times, no refetch storm.

---

## D. Multi-customer — per-row remove & notes

26. Multi mode, **3 customers**, add a design to all three, then **Remove line** on one, Save → that one loses it, the other two keep theirs, matrix + totals correct.
27. Remove a customer's **last line**, Save → the order reads **Draft/empty cleanly** ("saved · removed"), not a disappearance.
28. **Two devices, same customer**: device A adds a design; device B (stale) tries to **Remove line** on it; B saves → amber **"still on the order — reopen and check"**, NOT a green confirm.
29. **Per-customer note**: in the popup, a design shows a **thumbnail**; type a note for one customer (counter shows /500), Save. Reopen the popup → the note is **pre-filled**; press **Done untouched**, Save → the note **survives** (not wiped). Then edit the note only (leave qty), Save → the new note is stored.

---

## E. Bulk product grid — **desktop** (Products → Bulk add; `products.create` users only)

30. At **1280 px** and **1440 px**: the grid is usable, Tab moves across cells, **Enter** starts a new row, a blank row is always at the bottom.
31. Type a new design (design no, firm, category from the 4-value dropdown, pcs defaults to **2**), **Save** → it appears in **Product Master**; the row's Barcode cell reads **"new · no barcode"** (next free sticker is MC-0644 — not auto-assigned).
32. Type a design number that differs from an existing one **only by spacing/case** (e.g. `MR-4349` when `MR - 4349` exists) → **blocked** on Save with *"differs from … / ambiguous — pick one"*, both named; nothing saved.
33. **Drag one image** onto a row (design no filled) → thumbnail appears. **Drop several image files** onto the grid at once → each **auto-matches by filename**; a report shows matched vs unmatched (unmatched are named, never silently guessed).
34. A phone opens the same URL all day → the console still works normally on a phone with the grid present (the Bulk-add tab is hidden for non-`create` users; other sections unaffected).

---

## F. One cheap number that decides the floor

35. Pick **five designs at random** from the catalogue and add each to a test order by whatever works → **record how many needed manual typing vs a scan.** With 543/593 unmapped, expect ~**4 of 5**. This is the number that decides whether the floor runs on scanning or on typing.
