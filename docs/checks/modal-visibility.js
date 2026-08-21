// Real-browser modal/sheet visibility assertion — run at a 390x844 mobile viewport.
//
// WHY THIS EXISTS: jsdom (the automated suite) has no layout engine, so it happily
// passes a modal that "opens" (class toggles) but renders OFF-SCREEN. That is exactly
// how the Dispatch "Filters does nothing" bug shipped: #dispatch-filter-sheet lived
// inside <main id="page-dispatch">, whose .page enter-animation leaves a PERSISTENT
// transform, making the page the containing block for the position:fixed sheet — so
// with a tall/scrolled list the sheet's panel landed ~19,000px down. A class-toggle
// assertion could never catch it; only a real browser measuring geometry can.
//
// HOW TO RUN: open the admin console in a real browser (or the Claude Browser tool),
// DevTools > device toolbar > 390x844, paste this whole file into the console. It
// forces each page active, populates + deep-scrolls a list, taps the real Filters
// button (hit-tested, so an intercepting overlay fails it too), and asserts the sheet
// PANEL is actually within the viewport and topmost. Expect: all PASS.
//
// INVARIANT: every .modal must be a child of <body>, never nested inside a .page —
// a page's transform traps a fixed child. If you add a sheet, add it in <body> (or it
// is reparented at init; see admin html "reparent these two to match").
(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (id) => document.getElementById(id);
  let pass = 0, fail = 0;
  const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? "  ok  " : " FAIL ") + m); };

  // 1. structural invariant: no modal trapped by a transformed/filtered ancestor
  const trapProp = (el) => { const cs = getComputedStyle(el); return (cs.transform !== "none") || (cs.filter !== "none") || (cs.perspective !== "none"); };
  document.querySelectorAll("main.page").forEach((p) => p.classList.remove("active"));
  [...document.querySelectorAll(".modal")].forEach((m) => {
    let el = m.parentElement, trapped = false;
    while (el && el !== document.documentElement) { if (trapProp(el)) { trapped = true; break; } el = el.parentElement; }
    ok(!trapped, `modal #${m.id} is not trapped by a transformed ancestor (parent=${m.parentElement.tagName})`);
  });

  // 2. behavioural: each in-page Filters sheet is VISIBLE after a real tap, list scrolled
  const testSheet = async (pageId, listId, openBtnId, sheetId) => {
    document.querySelectorAll("main.page").forEach((p) => p.classList.remove("active"));
    $(pageId).classList.add("active");
    if ($(listId)) $(listId).innerHTML = Array.from({ length: 300 }, (_, i) => `<button class="dispatch-card" data-order="o${i}"><b>Row ${i}</b></button>`).join("");
    await wait(700); window.scrollTo(0, 5000); await wait(50);
    const sheet = $(sheetId); sheet.classList.remove("open");
    const btn = $(openBtnId), b = btn.getBoundingClientRect();
    const hit = document.elementFromPoint(Math.round(b.left + b.width / 2), Math.round(b.top + b.height / 2));
    ok(!!(hit && (hit === btn || btn.contains(hit))), `${sheetId}: a real tap reaches the Filters button (no overlay)`);
    if (hit) hit.click(); await wait(30);
    const panel = sheet.querySelector(".sheet"), pr = panel.getBoundingClientRect(), cs = getComputedStyle(sheet);
    const visible = pr.top < innerHeight && pr.bottom > 0 && pr.height > 0 && cs.visibility !== "hidden" && +cs.opacity > 0.01;
    ok(sheet.classList.contains("open"), `${sheetId}: openModal set the .open class`);
    ok(visible, `${sheetId}: panel is ACTUALLY visible in the viewport after the tap (rect top=${Math.round(pr.top)} h=${Math.round(pr.height)})`);
    const t = visible && document.elementFromPoint(Math.round(pr.left + pr.width / 2), Math.round(pr.top + 20));
    ok(!!(t && (t === panel || panel.contains(t))), `${sheetId}: panel is topmost (nothing intercepts taps on it)`);
    sheet.classList.remove("open");
  };
  await testSheet("page-dispatch", "dispatch-list", "dispatch-filter-open", "dispatch-filter-sheet");
  await testSheet("page-products", "product-list", "product-options-open", "product-options-sheet");

  console.log(`\nmodal-visibility: ${pass} passed, ${fail} failed`);
})();
