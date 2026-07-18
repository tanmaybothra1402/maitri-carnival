
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
    // Read-only. A Sheet push runs with the service role and would bypass
    // _write_order entirely, defeating the edit window, the order lock and
    // the dispatch lock. Order lines must be changed in the app.
    write: [],
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

// Columns where a blank cell must NOT mean false. Silently deactivating a
// design because someone left the column empty took an entire 450-design
// catalogue offline and would have failed every barcode scan at the event.
const BLANK_MEANS_TRUE = new Set(["active"]);

function coerce(col: string, val: unknown) {
  if (val === "" || val === null || val === undefined) {
    if (BLANK_MEANS_TRUE.has(col)) return true;
    return col === "capacity" ? null : (BOOL.has(col) ? false : (INT.has(col) ? null : ""));
  }
  if (BOOL.has(col)) return truthy(val);
  if (INT.has(col)) { const n = Number(val); return Number.isFinite(n) ? Math.round(n) : null; }
  return typeof val === "string" ? val : val;
}

// ── Delete safety rails ────────────────────────────────────────────────────
// Diff-based deletion ("a row missing from the sheet is deleted") is powerful
// and, unguarded, capable of destroying live event data from one button press.
// The classic failure: pull at 10am, push at 2pm, and every customer who
// registered in between is absent from the sheet and therefore "deleted".
// Four rails make that survivable.

// 1. Ceiling. A push may never delete more than this.
const MAX_DELETES_ABSOLUTE = 25;
const MAX_DELETES_FRACTION = 0.10;

// Tables where a missing row may be deleted at all.
const DIFF_DELETABLE = new Set([
  "designs",
  "barcode_mappings",
  "slots",
  "customers",
  "orders",
  "order_items",
]);

// 2. Freshness. A token describing the table's state at pull time. If the
// table has changed since, the sheet is stale and the push is refused before
// a single row is touched.
async function tableToken(db: SupabaseClient, table: string): Promise<string> {
  const { count, error } = await db
    .from(table)
    .select("*", { count: "exact", head: true });
  if (error) throw error;
  let stamp = "";
  // Not every table has updated_at; fall back to the row count alone.
  const { data } = await db
    .from(table)
    .select("updated_at")
    .order("updated_at", { ascending: false })
    .limit(1);
  if (Array.isArray(data) && data[0]?.updated_at) stamp = String(data[0].updated_at);
  return `${count ?? 0}:${stamp}`;
}

// 4. Rows that must never be removed from a spreadsheet, whatever the token
// says. A customer standing in your hall with an order against their name is
// not a spreadsheet row.
async function protectedKeys(db: SupabaseClient, table: string): Promise<Set<string>> {
  const keep = new Set<string>();
  if (table === "customers") {
    const { data, error } = await db
      .from("customers")
      .select("id,checked_in_at,ordering_started_at");
    if (error) throw error;
    for (const r of data ?? []) {
      if (r.checked_in_at || r.ordering_started_at) keep.add(String(r.id));
    }
    const { data: withOrders } = await db.from("orders").select("customer_id").gt("total_designs", 0);
    for (const r of withOrders ?? []) keep.add(String(r.customer_id));
  }
  if (table === "orders") {
    const { data } = await db.from("orders").select("id").gt("total_designs", 0);
    for (const r of data ?? []) keep.add(String(r.id));
  }
  if (table === "order_items") {
    // Anything already dispatched is physically gone from the warehouse.
    const { data } = await db.from("dispatch_lines").select("order_id,design_no").gt("dispatched_sets", 0);
    const shipped = new Set((data ?? []).map((r: any) => `${r.order_id}|${r.design_no}`));
    if (shipped.size) {
      const { data: items } = await db.from("order_items").select("id,order_id,design_no");
      for (const r of items ?? []) {
        if (shipped.has(`${r.order_id}|${r.design_no}`)) keep.add(String(r.id));
      }
    }
  }
  if (table === "slots") {
    const { data } = await db.from("bookings").select("slot_id").neq("status", "Cancelled");
    for (const r of data ?? []) keep.add(String(r.slot_id));
  }
  if (table === "barcode_mappings") {
    // A barcode already scanned onto an order must keep resolving.
    const { data } = await db.from("order_items").select("barcode").neq("barcode", "");
    for (const r of data ?? []) if (r.barcode) keep.add(String(r.barcode));
  }
  if (table === "designs") {
    const { data } = await db.from("order_items").select("design_no");
    for (const r of data ?? []) keep.add(String(r.design_no));
  }
  return keep;
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
  return {
    table,
    columns: cfg.cols.concat(extra),
    rows: out,
    token: await tableToken(db, table),
  };
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

// Works out which rows would be deleted by a diff, and refuses if any rail
// is breached. `dryRun` lets the Sheet show the operator exactly what will go
// before anything happens.
async function planDeletes(
  db: SupabaseClient,
  table: string,
  rows: any[],
  token: string,
) {
  if (!DIFF_DELETABLE.has(table)) return { keys: [] as string[], pk: "" };

  const cfg = TABLES[table];
  const pkArr = Array.isArray(cfg.pk) ? cfg.pk : [cfg.pk];
  if (pkArr.length !== 1) return { keys: [] as string[], pk: "" };
  const pk = pkArr[0];

  const inSheet = new Set(
    rows
      .map((r) => String((r || {})[pk] ?? "").trim())
      .filter((v) => v !== ""),
  );

  const existing: string[] = [];
  let from = 0;
  const size = 1000;
  while (true) {
    const { data, error } = await db.from(table).select(pk).range(from, from + size - 1);
    if (error) throw error;
    const batch = data ?? [];
    for (const r of batch) existing.push(String((r as any)[pk]));
    if (batch.length < size) break;
    from += size;
  }

  const missing = existing.filter((k) => !inSheet.has(k));

  // Nothing would be deleted, so this is a plain insert/update push. Do not
  // demand a pull token — requiring one would block bulk imports, and the
  // "fix" (pulling) would overwrite the operator's unsaved work.
  if (!missing.length) return { keys: [] as string[], pk };

  // Rail 2: freshness. Only enforced once deletion is actually implicated.
  const current = await tableToken(db, table);
  if (!token) throw new Error(`PULL_REQUIRED_BEFORE_DELETE_ON_${table.toUpperCase()}`);
  if (token !== current) {
    throw new Error(
      `SHEET_IS_STALE_FOR_${table.toUpperCase()}_PULL_AGAIN_BEFORE_PUSHING`,
    );
  }

  const protectedSet = await protectedKeys(db, table);

  // Rail 4: protected rows are simply never candidates.
  const blocked = missing.filter((k) => protectedSet.has(k));
  const keys = missing.filter((k) => !protectedSet.has(k));

  if (blocked.length) {
    throw new Error(
      `PROTECTED_ROWS_CANNOT_BE_DELETED_FROM_${table.toUpperCase()}: ${blocked.slice(0, 10).join(", ")}${blocked.length > 10 ? ` and ${blocked.length - 10} more` : ""}. Use active or status instead.`,
    );
  }

  // Rail 1: ceiling.
  const ceiling = Math.max(
    1,
    Math.min(MAX_DELETES_ABSOLUTE, Math.floor(existing.length * MAX_DELETES_FRACTION) || MAX_DELETES_ABSOLUTE),
  );
  if (keys.length > ceiling) {
    throw new Error(
      `TOO_MANY_DELETES_ON_${table.toUpperCase()}: ${keys.length} rows would be removed, limit is ${ceiling}. This usually means the sheet is incomplete or filtered. Pull again and delete in smaller batches.`,
    );
  }

  return { keys, pk };
}

async function push(db: SupabaseClient, table: string, rows: any[], token = "", dryRun = false) {
  const cfg = TABLES[table];
  if (!cfg) throw new Error("UNKNOWN_TABLE_" + table);
  if (!Array.isArray(rows)) throw new Error("ROWS_MUST_BE_AN_ARRAY");
  if (cfg.write.length === 0 && rows.length && !DIFF_DELETABLE.has(table)) {
    throw new Error(`READ_ONLY_TABLE_${table.toUpperCase()}`);
  }
  const pkArr = Array.isArray(cfg.pk) ? cfg.pk : [cfg.pk];

  // Rail 3 lives in the Sheet: this returns the plan so the operator can be
  // shown the exact rows by name before confirming.
  const plan = await planDeletes(db, table, rows, token);
  if (dryRun) {
    return { table, dryRun: true, willDelete: plan.keys, pk: plan.pk, updated: 0, upserted: 0, deleted: 0 };
  }
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

    // Explicit per-row delete marker, kept alongside the diff for operators who
    // prefer to be unambiguous. Same table allow-list applies.
    if (truthy(r._delete)) {
      if (!cfg.deletable && !DIFF_DELETABLE.has(table)) {
        throw new Error(`DELETE_NOT_ALLOWED_FOR_${table.toUpperCase()}_USE_ACTIVE_OR_STATUS`);
      }
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
      // A read-only table (order_items) produces an empty patch. Updating with
      // {} errors in PostgREST, and there is nothing to write anyway.
      if (!Object.keys(patch).length) continue;
      const m: any = {}; pkArr.forEach((k) => m[k] = coerce(k, r[k]));
      const { error } = await db.from(table).update(patch).match(m);
      if (error) throw error;
      updated++;
    }
  }

  let upserted = 0;

  // Postgres refuses an upsert that touches the same key twice within one
  // command ("ON CONFLICT DO UPDATE command cannot affect row a second time").
  // Catch it here and name the offending rows, because the raw 21000 tells the
  // operator nothing about which of 450 rows is at fault.
  if (upserts.length) {
    const seenKeys = new Map<string, number>();
    for (const rec of upserts) {
      const key = pkArr.map((k) => String(rec[k] ?? "").trim()).join("|");
      seenKeys.set(key, (seenKeys.get(key) ?? 0) + 1);
    }
    const dupes = Array.from(seenKeys.entries())
      .filter(([, n]) => n > 1)
      .map(([k]) => k);
    if (dupes.length) {
      throw new Error(
        `DUPLICATE_${pkArr.join("_").toUpperCase()}_IN_SHEET: ${dupes.slice(0, 15).join(", ")}${dupes.length > 15 ? ` and ${dupes.length - 15} more` : ""}. Each row must have a unique ${pkArr.join(" + ")}. Nothing was saved.`,
      );
    }
  }

  if (upserts.length) { const { error } = await db.from(table).upsert(upserts, { onConflict: pkArr.join(",") }); if (error) throw error; upserted += upserts.length; }
  if (inserts.length) { const { error } = await db.from(table).insert(inserts); if (error) throw error; upserted += inserts.length; }

  // Diff-based removal runs last, so a failure mid-update never leaves the
  // table half-written and half-deleted.
  if (plan.keys.length && plan.pk) {
    for (let i = 0; i < plan.keys.length; i += 100) {
      const slice = plan.keys.slice(i, i + 100);
      const { error } = await db.from(table).delete().in(plan.pk, slice);
      if (error) throw error;
      deleted += slice.length;
    }
  }

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
    if (action === "push") {
      return jsonResponse(req, {
        ok: true,
        data: await push(db, clean(body.table), body.rows, clean(body.token), truthy(body.dryRun)),
      });
    }
    return jsonResponse(req, { ok: false, error: "UNKNOWN_ACTION_" + action }, 400);
  } catch (error) {
    console.error(error);
    const m = errorMessage(error);
    return jsonResponse(req, { ok: false, error: m }, m.includes("AUTH_REQUIRED") ? 401 : 500);
  }
});
