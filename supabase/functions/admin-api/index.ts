import { optionsResponse } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

async function fetchAll(
  db: SupabaseClient,
  table: string,
  columns = "*",
  orderColumn?: string,
): Promise<any[]> {
  const output: any[] = [];
  const pageSize = 1000;
  let from = 0;
  while (true) {
    let query: any = db.from(table).select(columns);
    if (orderColumn) query = query.order(orderColumn, { ascending: true });
    const { data, error } = await query.range(from, from + pageSize - 1);
    if (error) throw error;
    const rows = data ?? [];
    output.push(...rows);
    if (rows.length < pageSize) break;
    from += pageSize;
  }
  return output;
}

function normalizePhone(value: unknown): string {
  let digits = clean(value).replace(/\D/g, "");
  if (digits.length === 10) digits = `91${digits}`;
  if (!/^91[6-9]\d{9}$/.test(digits)) throw new Error("Enter a valid Indian mobile number");
  return digits;
}

function groupSum<T>(rows: T[], keyFn: (row: T) => string, valueFn: (row: T) => number) {
  const map = new Map<string, number>();
  for (const row of rows) {
    const key = clean(keyFn(row)) || "Not specified";
    map.set(key, (map.get(key) ?? 0) + Number(valueFn(row) || 0));
  }
  return Array.from(map, ([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));
}

async function dashboard(db: SupabaseClient) {
  const [customers, orders, items, designs] = await Promise.all([
    fetchAll(db, "customers", "id,phone_e164,company_name,contact_name,city,state,gstin,active,created_at,updated_at", "created_at"),
    fetchAll(db, "orders", "id,customer_id,firm,status,total_designs,total_pieces,version,created_at,updated_at", "created_at"),
    fetchAll(db, "order_items", "id,order_id,barcode,design_no,qty,category_snapshot,fabric_snapshot,color_snapshot,description_snapshot,created_at,updated_at", "created_at"),
    fetchAll(db, "designs", "design_no,image_url", "design_no"),
  ]);

  const customerById = new Map(customers.map((row) => [row.id, row]));
  const orderById = new Map(orders.map((row) => [row.id, row]));
  const imageByDesign = new Map(designs.map((row) => [row.design_no, row.image_url ?? ""]));
  const itemsByOrder = new Map<string, any[]>();
  for (const item of items) {
    const list = itemsByOrder.get(item.order_id) ?? [];
    list.push({
      id: item.id,
      barcode: item.barcode,
      designNo: item.design_no,
      imageUrl: imageByDesign.get(item.design_no) ?? "",
      qty: Number(item.qty) || 0,
      category: item.category_snapshot,
      fabric: item.fabric_snapshot,
      color: item.color_snapshot,
      description: item.description_snapshot,
    });
    itemsByOrder.set(item.order_id, list);
  }

  const orderRows = orders.map((order) => {
    const customer = customerById.get(order.customer_id) ?? {};
    return {
      id: order.id,
      customerId: order.customer_id,
      companyName: customer.company_name ?? "",
      contactName: customer.contact_name ?? "",
      phone: customer.phone_e164 ?? "",
      city: customer.city ?? "",
      state: customer.state ?? "",
      customerActive: customer.active !== false,
      firm: order.firm,
      status: order.status,
      totalDesigns: Number(order.total_designs) || 0,
      totalPieces: Number(order.total_pieces) || 0,
      version: Number(order.version) || 0,
      createdAt: order.created_at,
      updatedAt: order.updated_at,
      items: itemsByOrder.get(order.id) ?? [],
    };
  });

  const savedOrders = orderRows.filter((row) => row.totalDesigns > 0 || row.status === "Saved");
  const itemFacts = items.map((item) => {
    const order = orderById.get(item.order_id) ?? {};
    const customer = customerById.get(order.customer_id) ?? {};
    return {
      designNo: item.design_no,
      imageUrl: imageByDesign.get(item.design_no) ?? "",
      qty: Number(item.qty) || 0,
      category: item.category_snapshot,
      fabric: item.fabric_snapshot,
      color: item.color_snapshot,
      firm: order.firm ?? "",
      customerId: order.customer_id ?? "",
      companyName: customer.company_name ?? "",
      city: customer.city ?? "",
      state: customer.state ?? "",
    };
  });

  const customerTotals = new Map<string, { label: string; value: number; designs: Set<string> }>();
  const designCustomers = new Map<string, Set<string>>();
  for (const fact of itemFacts) {
    const current = customerTotals.get(fact.customerId) ?? {
      label: fact.companyName || "Unknown customer",
      value: 0,
      designs: new Set<string>(),
    };
    current.value += fact.qty;
    current.designs.add(fact.designNo);
    customerTotals.set(fact.customerId, current);

    const set = designCustomers.get(fact.designNo) ?? new Set<string>();
    set.add(fact.customerId);
    designCustomers.set(fact.designNo, set);
  }

  const topCustomers = Array.from(customerTotals.entries()).map(([customerId, value]) => ({
    customerId,
    label: value.label,
    value: value.value,
    designs: value.designs.size,
  })).sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));

  const topDesigns = groupSum(itemFacts, (row) => row.designNo, (row) => row.qty)
    .map((row) => ({ ...row, customers: designCustomers.get(row.label)?.size ?? 0 }));

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      totalCustomers: customers.length,
      activeCustomers: customers.filter((row) => row.active).length,
      customersWithOrders: new Set(savedOrders.map((row) => row.customerId)).size,
      savedOrders: savedOrders.length,
      totalPieces: itemFacts.reduce((sum, row) => sum + row.qty, 0),
      uniqueDesigns: new Set(itemFacts.map((row) => row.designNo)).size,
      maitriPieces: itemFacts.filter((row) => row.firm === "Maitri").reduce((sum, row) => sum + row.qty, 0),
      niharikaPieces: itemFacts.filter((row) => row.firm === "Niharika").reduce((sum, row) => sum + row.qty, 0),
    },
    charts: {
      firmPieces: groupSum(itemFacts, (row) => row.firm, (row) => row.qty),
      statePieces: groupSum(itemFacts, (row) => row.state, (row) => row.qty),
      cityPieces: groupSum(itemFacts, (row) => row.city, (row) => row.qty),
      categoryPieces: groupSum(itemFacts, (row) => row.category, (row) => row.qty),
      fabricPieces: groupSum(itemFacts, (row) => row.fabric, (row) => row.qty),
      topDesigns: topDesigns.slice(0, 20),
      topCustomers: topCustomers.slice(0, 20),
    },
    customers: customers.map((row) => ({
      id: row.id,
      phone: row.phone_e164,
      companyName: row.company_name,
      contactName: row.contact_name,
      city: row.city,
      state: row.state,
      gstin: row.gstin,
      active: row.active,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })),
    orders: orderRows.sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt))),
  };
}

async function listDesigns(db: SupabaseClient) {
  const { data, error } = await db
    .from("designs")
    .select("design_no,firm,image_url,category,fabric,color,description,active,sync_version,updated_at")
    .order("design_no", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    designNo: row.design_no,
    firm: row.firm,
    imageUrl: row.image_url ?? "",
    category: row.category,
    fabric: row.fabric,
    color: row.color,
    description: row.description,
    active: row.active,
    syncVersion: row.sync_version,
    updatedAt: row.updated_at,
  }));
}

async function listMappings(db: SupabaseClient) {
  const { data, error } = await db
    .from("barcode_mappings")
    .select("barcode,design_no,active,mapped_at,updated_at,designs(firm,category,fabric,color)")
    .order("updated_at", { ascending: false })
    .limit(1000);
  if (error) throw error;
  return (data ?? []).map((row: any) => ({
    barcode: row.barcode,
    designNo: row.design_no,
    active: row.active,
    mappedAt: row.mapped_at,
    updatedAt: row.updated_at,
    firm: row.designs?.firm ?? "",
    category: row.designs?.category ?? "",
    fabric: row.designs?.fabric ?? "",
    color: row.designs?.color ?? "",
  }));
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    const admin = await requireAdmin(request);
    const db = serviceClient();
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action);

    if (action === "whoami") {
      return jsonResponse(request, { ok: true, data: { id: admin.id, email: admin.email, role: "admin" } });
    }

    if (action === "dashboard") {
      return jsonResponse(request, { ok: true, data: await dashboard(db) });
    }

    if (action === "listDesigns") {
      return jsonResponse(request, { ok: true, data: await listDesigns(db) });
    }

    if (action === "listMappings") {
      return jsonResponse(request, { ok: true, data: await listMappings(db) });
    }

    if (action === "mapBarcode") {
      const { data, error } = await db.rpc("admin_map_barcode", {
        p_barcode: clean(body.barcode),
        p_design_no: clean(body.designNo),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "mapBatch") {
      if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 300) {
        throw new Error("Provide 1 to 300 mapping rows");
      }
      const results = [];
      for (const raw of body.items) {
        const item = raw as Record<string, unknown>;
        try {
          const { data, error } = await db.rpc("admin_map_barcode", {
            p_barcode: clean(item.barcode),
            p_design_no: clean(item.designNo),
            p_admin_user_id: admin.id,
          });
          if (error) throw error;
          results.push({ ok: true, data });
        } catch (error) {
          results.push({ ok: false, barcode: clean(item.barcode), error: errorMessage(error) });
        }
      }
      return jsonResponse(request, { ok: true, data: { results } });
    }

    if (action === "deactivateBarcode") {
      const { data, error } = await db.rpc("admin_deactivate_barcode", {
        p_barcode: clean(body.barcode),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "resetPassword") {
      const phone = normalizePhone(body.phone);
      const password = clean(body.newPassword);
      if (password.length < 8) throw new Error("New password must be at least 8 characters");
      const { data: customer, error: customerError } = await db
        .from("customers")
        .select("id,company_name,phone_e164")
        .eq("phone_e164", phone)
        .maybeSingle();
      if (customerError) throw customerError;
      if (!customer) throw new Error("Customer not found");
      const { error } = await db.auth.admin.updateUserById(customer.id, { password });
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: { customerId: customer.id, companyName: customer.company_name, phone: customer.phone_e164 },
      });
    }

    if (action === "setCustomerActive") {
      const customerId = clean(body.customerId);
      const active = Boolean(body.active);
      const { data, error } = await db
        .from("customers")
        .update({ active })
        .eq("id", customerId)
        .select("id,company_name,phone_e164,active")
        .single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "setOrderLocked") {
      const orderId = clean(body.orderId);
      const locked = Boolean(body.locked);
      const { data, error } = await db
        .from("orders")
        .update({ status: locked ? "Locked" : "Saved" })
        .eq("id", orderId)
        .select("id,firm,status,updated_at")
        .single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    return jsonResponse(request, { ok: false, error: `UNKNOWN_ACTION_${action}` }, 400);
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message === "ADMIN_REQUIRED" ? 403 : message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
