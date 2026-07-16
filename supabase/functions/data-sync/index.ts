
// Generic two-way data mirror for the Google Sheet workbook.
// Secret-gated (x-sheet-sync-secret). Pull = read a table; Push = guarded
// upsert/update. Destructive deletes are blocked for every mirrored table.

import { optionsResponse } from "../_shared/cors.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { secureEqual } from "../_shared/secure.ts";
import { serviceClient } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type TableCfg = {
  pk: string | string[];
  cols: string[];        // columns returned on pull
  write: string[];       // columns that may be changed on push
  insert: boolean;       // may new rows be created?
  deletable?: boolean;   // explicit Sheet deletes allowed only for low-risk tables
  hide?: string[];       // legacy columns intentionally omitted from the Sheet
  recomputeOrders?: boolean;
};

const TABLES: Record<string, TableCfg> = {
  designs: {
    pk: "design_no",
    cols: ["design_no","firm","image_url","category","style","fabric","pcs_per_set","description","active","sync_version","updated_at"],
    write: ["firm","image_url","category","style","fabric","pcs_per_set","description","active"],
    hide: ["color"],
    insert: true,
  },
  barcode_mappings: {
    pk: "barcode",
    cols: ["barcode","design_no","active","mapped_at","updated_at"],
    write: ["design_no","active"],
    insert: true,
  },
  customers: {
    pk: "id",
    cols: ["id","phone_e164","company_name","contact_name","city","state","gstin","agent","active","checked_in_at","ordering_started_at","edit_deadline","created_at"],
    write: ["company_name","contact_name","city","state","gstin","agent","active"],
    insert: false,
  },
  orders: {
    pk: "id",
    cols: ["id","customer_id","firm","status","total_designs","total_sets","total_pieces","version","admin_unlocked","updated_at"],
    write: ["status","admin_unlocked"],
    insert: false,
  },
  order_items: {
    pk: "id",
    cols: ["id","order_id","barcode","design_no","qty","category_snapshot","style_snapshot","fabric_snapshot","pcs_per_set_snapshot","line_note","description_snapshot","created_by_type","last_modified_by_type","last_modified_by_user_id"],
    write: ["qty","line_note"],
    hide: ["color_snapshot"],
    insert: false,
    recomputeOrders: true,
  },
  slots: {
    pk: "id",
    cols: ["id","starts_at","ends_at","label","capacity","active","created_at"],
    write: ["starts_at","ends_at","label","capacity","active"],
    insert: true,
  },
  bookings: {
    pk: "id",
    cols: ["id","customer_id","slot_id","party_size","note","status","created_at"],
    write: ["party_size","note","status","slot_id"],
    insert: false,
  },
  staff_profiles: {
    pk: "auth_user_id",
    cols: ["auth_user_id","staff_id","staff_name","preset","permissions","default_section","active","created_at","updated_at"],
    write: [],
    insert: false,
  },
  system_settings: {
    pk: "singleton",
    cols: ["singleton","event_name","event_start_date","event_end_date","registration_enabled","edit_window_hours","customer_email_domain"],
    write: ["event_name","event_start_date","event_end_date","registration_enabled","edit_window_hours"],
    insert: false,
  },
};

const BOOL = new Set(["active","admin_unlocked","registration_enabled","singleton"]);
const INT = new Set(["qty","pcs_per_set","pcs_per_set_snapshot","capacity","party_size","total_designs","total_sets","total_pieces","version","edit_window_hours"]);

function requireSecret(req: Request) {
  const exp = Deno.env.get("SHEET_SYNC_SECRET") ?? "";
  const got = req.headers.get("x-sheet-sync-secret") ?? "";
  if (!exp || !secureEqual(exp, got)) throw new Error("SHEET_SYNC_AUTH_REQUIRED");
}

function truthy(v: unknown) { return v === true || /^(true|yes|1|active)$/i.test(String(v ?? "")); }

function coerce(col: string, val: unknown) {
  if (val === "" || val === null || val === undefined) return col === "capacity" ? null : (BOOL.has(col) ? false : (INT.has(col) ? null : ""));
  if (BOOL.has(col)) return truthy(val);
  if (INT.has(col)) { const n = Number(val); return Number.isFinite(n) ? Math.round(n) : null; }
  return typeof val === "string" ? val : val;
}

async function pull(db: SupabaseClient, table: string) {
  const cfg = TABLES[table];
  if (!cfg) throw new Error("UNKNOWN_TABLE_" + table);
  const out: any[] = [];
  let from = 0; const size = 1000;
  while (true) {
    // Read every column so newly-added DB columns appear in the sheet automatically.
    const { data, error } = await db.from(table).select("*").range(from, from + size - 1);
    if (error) throw error;
    const rows = data ?? [];
    out.push(...rows);
    if (rows.length < size) break;
    from += size;
  }
  // Known columns first (stable order), then any new/extra columns discovered in the data.
  const seen = new Set(cfg.cols);
  const hidden = new Set(cfg.hide ?? []);
  const extra: string[] = [];
  for (const r of out) for (const k of Object.keys(r)) if (!seen.has(k) && !hidden.has(k)) { seen.add(k); extra.push(k); }
  return { table, columns: cfg.cols.concat(extra), rows: out };
}

async function recompute(db: SupabaseClient, orderId: string) {
  const { data } = await db.from("order_items").select("qty,pcs_per_set_snapshot").eq("order_id", orderId);
  const items = data ?? [];
  await db.from("orders").update({
    total_designs: items.length,
    total_sets: items.reduce((s: number, i: any) => s + Number(i.qty || 0), 0),
    total_pieces: items.reduce((s: number, i: any) => s + Number(i.qty || 0) * (Number(i.pcs_per_set_snapshot) || 1), 0),
    updated_at: new Date().toISOString(),
  }).eq("id", orderId);
}

async function push(db: SupabaseClient, table: string, rows: any[]) {
  const cfg = TABLES[table];
  if (!cfg) throw new Error("UNKNOWN_TABLE_" + table);
  if (!Array.isArray(rows)) throw new Error("ROWS_MUST_BE_AN_ARRAY");
  if (cfg.write.length === 0 && rows.length) throw new Error(`READ_ONLY_TABLE_${table.toUpperCase()}`);
  const pkArr = Array.isArray(cfg.pk) ? cfg.pk : [cfg.pk];
  const existingDesignNos = new Set<string>();
  if (table === "designs") {
    const designNos = Array.from(new Set(rows
      .map((row) => clean(row?.design_no))
      .filter(Boolean)));
    for (let i = 0; i < designNos.length; i += 500) {
      const { data, error } = await db.from("designs")
        .select("design_no")
        .in("design_no", designNos.slice(i, i + 500));
      if (error) throw error;
      for (const row of data ?? []) existingDesignNos.add(String(row.design_no));
    }
  }
  const affected = new Set<string>();
  const upserts: any[] = [];
  const inserts: any[] = [];
  let updated = 0, deleted = 0;

  for (const raw of rows) {
    const r = raw || {};
    if (cfg.recomputeOrders && r.order_id) affected.add(String(r.order_id));
    const hasPk = pkArr.every((k) => String(r[k] ?? "").trim() !== "");

    if (truthy(r._delete)) {
      if (!cfg.deletable) throw new Error(`DELETE_NOT_ALLOWED_FOR_${table.toUpperCase()}_USE_ACTIVE_OR_STATUS`);
      if (!hasPk) continue;
      const m: any = {}; pkArr.forEach((k) => m[k] = coerce(k, r[k]));
      const { error } = await db.from(table).delete().match(m);
      if (error) throw error;
      deleted++; continue;
    }

    const patch: any = {};
    for (const c of cfg.write) if (c in r) patch[c] = coerce(c, r[c]);

    if (table === "designs") {
      const designNo = clean(r.design_no);
      const rawPcs = r.pcs_per_set;
      const missingPcs = rawPcs === "" || rawPcs === null || rawPcs === undefined;
      if (missingPcs) {
        if (designNo && !existingDesignNos.has(designNo)) patch.pcs_per_set = 4;
        else delete patch.pcs_per_set;
      } else {
        const pcs = Number(rawPcs);
        if (!Number.isInteger(pcs) || pcs < 1 || pcs > 9999) {
          throw new Error(`INVALID_PCS_PER_SET_FOR_${designNo || "NEW_DESIGN"}`);
        }
        patch.pcs_per_set = pcs;
      }
    }

    if (cfg.insert) {
      if (hasPk) { const rec = { ...patch }; pkArr.forEach((k) => rec[k] = coerce(k, r[k])); upserts.push(rec); }
      else inserts.push(patch);
    } else {
      if (!hasPk) continue;
      const m: any = {}; pkArr.forEach((k) => m[k] = coerce(k, r[k]));
      const { error } = await db.from(table).update(patch).match(m);
      if (error) throw error;
      updated++;
    }
  }

  let upserted = 0;
  if (upserts.length) { const { error } = await db.from(table).upsert(upserts, { onConflict: pkArr.join(",") }); if (error) throw error; upserted += upserts.length; }
  if (inserts.length) { const { error } = await db.from(table).insert(inserts); if (error) throw error; upserted += inserts.length; }

  if (cfg.recomputeOrders) for (const oid of affected) await recompute(db, oid);

  return { table, updated, upserted, deleted };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return optionsResponse(req);
  if (req.method !== "POST") return jsonResponse(req, { ok: false, error: "POST_REQUIRED" }, 405);
  try {
    requireSecret(req);
    const body = await req.json().catch(() => ({}));
    const action = clean(body.action);
    const db = serviceClient();
    if (action === "ping") return jsonResponse(req, { ok: true, data: { tables: Object.keys(TABLES), at: new Date().toISOString() } });
    if (action === "pull") return jsonResponse(req, { ok: true, data: await pull(db, clean(body.table)) });
    if (action === "pullAll") {
      const all: Record<string, any> = {};
      for (const t of Object.keys(TABLES)) all[t] = await pull(db, t);
      return jsonResponse(req, { ok: true, data: all });
    }
    if (action === "push") return jsonResponse(req, { ok: true, data: await push(db, clean(body.table), body.rows) });
    return jsonResponse(req, { ok: false, error: "UNKNOWN_ACTION_" + action }, 400);
  } catch (error) {
    console.error(error);
    const m = errorMessage(error);
    return jsonResponse(req, { ok: false, error: m }, m.includes("AUTH_REQUIRED") ? 401 : 500);
  }
});
