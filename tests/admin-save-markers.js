// Regression backstop for maitri-guardrails §B5.
//
// _write_order treats a marker-less ADMIN order payload as a full-cart replace and
// deletes every line not in it (verified empirically 2 Aug 2026: a 1-item
// marker-less admin payload against a 3-line order left 1 row). The admin console
// is safe only because every order write goes through the single choke point
// sendAdminSave(), which stamps a missing _op so nothing marker-less can leave the
// client.
//
// This test fails — instead of the floor failing — if someone adds a new admin
// save path that calls assistedSaveOrder directly, or a payload builder that omits
// _op. Run:  node tests/admin-save-markers.js   (needs devDependency jsdom)
const fs = require("fs");
const path = require("path");
const { JSDOM, VirtualConsole } = require("jsdom");

const webDir = path.join(__dirname, "..", "web");
const adminFile = fs.readdirSync(webDir).find((f) => /^admin-.*\.html$/.test(f));
if (!adminFile) { console.error("admin console HTML not found in web/"); process.exit(1); }
const html = fs.readFileSync(path.join(webDir, adminFile), "utf8");

let pass = 0, fail = 0;
const ok = (c, m) => { (c ? pass++ : fail++); console.log((c ? "  ok  " : " FAIL ") + m); };

// ---------- STATIC: one choke point, no direct call sites ----------
const directCalls = (html.match(/admin\(\s*["']assistedSaveOrder["']/g) || []).length;
ok(directCalls === 1, `exactly one admin("assistedSaveOrder") call in the file (found ${directCalls})`);
ok(/async function sendAdminSave\s*\(/.test(html), "sendAdminSave choke point is defined");
ok(html.includes("const d = await sendAdminSave(st.sale.customer.id"), "single-customer save routes through sendAdminSave");
ok(html.includes("await sendAdminSave(job.customer.id"), "multi save routes through sendAdminSave");
const fnStart = html.indexOf("async function sendAdminSave");
const callIdx = html.search(/admin\(\s*["']assistedSaveOrder["']/);
const between = html.slice(fnStart, callIdx);
ok(fnStart >= 0 && callIdx > fnStart && !/\n(?:async )?function /.test(between.slice(30)), "the direct call sits inside sendAdminSave");

// ---------- RUNTIME: stamping + payload shape ----------
const STUB = `<script>
window.__fetch=[];
window.supabase={createClient:()=>({
  auth:{getSession:async()=>({data:{session:{access_token:'t',expires_at:Math.floor(Date.now()/1000)+3600}}}),
    refreshSession:async()=>({data:{session:null}}), signInWithPassword:async()=>({error:null}), signOut:async()=>{},
    onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},
  rpc:async()=>({data:[],error:null})})};
window.Chart=function(){return{destroy(){}}};
window.fetch=async(url,opts)=>{const body=JSON.parse(opts.body);window.__fetch.push(body);
  let data={}; if(body.action==='assistedSaveOrder')data={order:{items:[]}};
  return{ok:true,json:async()=>({ok:true,data})};};
</script>`;
let h = html.replace("<body>", "<body>" + STUB);
h = h.replace("</body>", `<script>window.__t={st,sendAdminSave,saleAdd,saleCart};</script></body>`);

const vc = new VirtualConsole();
const errs = [];
vc.on("jsdomError", (e) => errs.push(e.message));
const dom = new JSDOM(h, { runScripts: "dangerously", virtualConsole: vc, url: "https://x/" });
const w = dom.window;

setTimeout(async () => {
  if (errs.length) { console.log("JSDOM ERRORS:\n" + errs.join("\n")); process.exit(1); }
  const t = w.__t, $ = (id) => w.document.getElementById(id);

  const lastSave = () => w.__fetch.filter((b) => b.action === "assistedSaveOrder").at(-1);
  const everyItemMarked = (b) => Array.isArray(b.items) && b.items.length > 0 && b.items.every((i) => i._op === "upsert" || i._op === "delete");

  w.__fetch = [];
  await t.sendAdminSave("c1", "Maitri", [{ barcode: "", designNo: "A", qty: 1 }]);
  ok(lastSave().items[0]._op === "upsert", "missing marker on a qty item is stamped _op:upsert");
  ok(everyItemMarked(lastSave()), "payload A: every item carries _op");
  ok(!("requestId" in lastSave()), "no requestId when caller omits it (server generates)");

  w.__fetch = [];
  await t.sendAdminSave("c1", "Maitri", [{ designNo: "B", _delete: true }]);
  ok(lastSave().items[0]._op === "delete", "_delete item without marker is stamped _op:delete");

  w.__fetch = [];
  await t.sendAdminSave("c1", "Maitri", [{ _op: "upsert", designNo: "C", qty: 2 }], "req-123");
  ok(lastSave().items[0]._op === "upsert", "existing _op preserved");
  ok(lastSave().requestId === "req-123", "requestId forwarded when provided");

  w.__fetch = [];
  await t.sendAdminSave("c1", "Maitri", [{ designNo: "A", qty: 1 }, { _op: "delete", designNo: "B", _delete: true }, { designNo: "C", _delete: true }]);
  ok(everyItemMarked(lastSave()), "mixed payload: every item ends up marked");

  // End-to-end: the real single-customer save routes through the helper marked.
  t.st.designs = [{ designNo: "MU - 0322", firm: "Maitri", category: "K", style: "S", fabric: "C", pcsPerSet: 2, description: "", imageUrl: "", active: true }];
  t.st.cache = t.st.cache || {}; t.st.cache.designsAt = Date.now();
  t.st.sale = { customer: { id: "c9", companyName: "Co" }, firm: "Maitri", carts: { Maitri: [], Niharika: [] }, deleted: { Maitri: new w.Set(), Niharika: new w.Set() } };
  await t.saleAdd("MU - 0322");
  w.__fetch = [];
  await $("sale-save").onclick();
  ok(everyItemMarked(lastSave()), "real single-customer save emits _op on every item");

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}, 250);
