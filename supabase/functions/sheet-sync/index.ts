import { optionsResponse } from "../_shared/cors.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { secureEqual } from "../_shared/secure.ts";
import { serviceClient } from "../_shared/supabase.ts";

type ProductRow = {
  DesignNo: string;
  Firm: string;
  ImageURL: string;
  Category: string;
  Fabric: string;
  Color: string;
  Description: string;
  Active: boolean | string;
  UpdatedAt?: string;
};

function requireSecret(request: Request): void {
  const expected = Deno.env.get("SHEET_SYNC_SECRET") ?? "";
  const supplied = request.headers.get("x-sheet-sync-secret") ?? "";
  if (!expected || !secureEqual(expected, supplied)) throw new Error("SHEET_SYNC_AUTH_REQUIRED");
}

function normalizeRows(input: unknown): ProductRow[] {
  if (!Array.isArray(input)) throw new Error("ROWS_MUST_BE_AN_ARRAY");
  if (input.length > 5000) throw new Error("TOO_MANY_ROWS");

  const seen = new Set<string>();
  return input.map((raw, index) => {
    const row = (raw ?? {}) as Record<string, unknown>;
    const designNo = clean(row.DesignNo ?? row.design_no);
    const firm = clean(row.Firm ?? row.firm);
    if (!designNo) throw new Error(`Row ${index + 2}: DesignNo is required`);
    const key = designNo.toLowerCase();
    if (seen.has(key)) throw new Error(`Duplicate DesignNo in request: ${designNo}`);
    seen.add(key);

    return {
      DesignNo: designNo,
      Firm: firm,
      ImageURL: clean(row.ImageURL ?? row.image_url),
      Category: clean(row.Category ?? row.category),
      Fabric: clean(row.Fabric ?? row.fabric),
      Color: clean(row.Color ?? row.color),
      Description: clean(row.Description ?? row.description),
      Active: row.Active ?? row.active ?? true,
      UpdatedAt: clean(row.UpdatedAt ?? row.updated_at) || new Date().toISOString(),
    };
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    requireSecret(request);
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action);
    const db = serviceClient();

    if (action === "ping") {
      const { count, error } = await db.from("designs").select("design_no", { count: "exact", head: true });
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: { connected: true, designCount: count ?? 0, at: new Date().toISOString() },
      });
    }

    if (action === "syncRows") {
      const rows = normalizeRows(body.rows ?? []);
      const { data, error } = await db.rpc("upsert_product_rows", { p_rows: rows });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "fullSnapshot") {
      const rows = normalizeRows(body.rows ?? []);
      const { data, error } = await db.rpc("apply_product_snapshot", { p_rows: rows });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "getStatus") {
      const [{ count: designCount, error: designError }, { data: lastRun, error: runError }] = await Promise.all([
        db.from("designs").select("design_no", { count: "exact", head: true }),
        db.from("product_sync_runs").select("*").order("created_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (designError) throw designError;
      if (runError) throw runError;
      return jsonResponse(request, {
        ok: true,
        data: { designCount: designCount ?? 0, lastRun: lastRun ?? null, at: new Date().toISOString() },
      });
    }

    return jsonResponse(request, { ok: false, error: `UNKNOWN_ACTION_${action}` }, 400);
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message.includes("AUTH_REQUIRED") ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
