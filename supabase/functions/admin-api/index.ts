
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

const CUSTOMER_DOMAIN = "accounts.maitricarnival.app";
const STAFF_DOMAIN = "staff.maitricarnival.app";

function normalizePhone(value: unknown): string {
  let digits = clean(value).replace(/\D/g, "");
  if (digits.length === 10) digits = `91${digits}`;
  if (!/^91[6-9]\d{9}$/.test(digits)) throw new Error("Enter a valid Indian mobile number");
  return digits;
}

function hiddenEmail(phone: string): string {
  return `c${phone}@${CUSTOMER_DOMAIN}`;
}

function generatePassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}

const ALL_PERMISSIONS: Record<string, boolean> = {
  "reception.view": true,
  "reception.checkin": true,
  "reception.register": true,
  "reception.password_reset": true,
  "reception.customer_control": true,
  "dashboard.view": true,
  "dashboard.export": true,
  "sale.view": true,
  "sale.write": true,
  "sale.previous": true,
  "sale.pdf": true,
  "sale.lock": true,
  "products.view": true,
  "products.edit": true,
  "products.mapping": true,
  "products.lookups": true,
  "admin.slots": true,
  "admin.bookings": true,
  "admin.staff": true,
  "admin.settings": true,
};

const PRESET_PERMISSIONS: Record<string, Record<string, boolean>> = {
  sales: { "sale.view": true, "sale.write": true, "sale.previous": true, "sale.pdf": true, "reception.view": true },
  reception: { "reception.view": true, "reception.checkin": true, "reception.register": true, "reception.password_reset": true, "reception.customer_control": true, "admin.bookings": true },
  products: { "products.view": true, "products.edit": true, "products.mapping": true, "products.lookups": true },
  manager: Object.fromEntries(Object.entries(ALL_PERMISSIONS).filter(([key]) => !["admin.staff", "admin.settings"].includes(key))),
  administrator: { ...ALL_PERMISSIONS },
  custom: {},
};

type StaffContext = {
  authUserId: string;
  staffId: string;
  staffName: string;
  preset: string;
  permissions: Record<string, boolean>;
  defaultSection: string;
  active: boolean;
  legacyAdmin: boolean;
};

function normalizeStaffId(value: unknown): string {
  const staffId = clean(value).toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,39}$/.test(staffId)) {
    throw new Error("Staff ID must be 2-40 characters using letters, numbers, dot, underscore or dash");
  }
  return staffId;
}

function staffEmail(staffId: string): string {
  return `${staffId}@${STAFF_DOMAIN}`;
}

function normalizePermissions(value: unknown, preset: string): Record<string, boolean> {
  const source = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : PRESET_PERMISSIONS[preset] ?? {};
  const output: Record<string, boolean> = {};
  for (const key of Object.keys(ALL_PERMISSIONS)) output[key] = Boolean(source[key]);
  return output;
}

async function loadStaffContext(db: SupabaseClient, user: any): Promise<StaffContext> {
  const role = clean(user.app_metadata?.role);
  const { data: profile, error } = await db
    .from("staff_profiles")
    .select("auth_user_id,staff_id,staff_name,preset,permissions,default_section,active")
    .eq("auth_user_id", user.id)
    .maybeSingle();
  if (error) throw error;
  if (profile) {
    return {
      authUserId: profile.auth_user_id,
      staffId: profile.staff_id,
      staffName: profile.staff_name,
      preset: profile.preset,
      permissions: normalizePermissions(profile.permissions, profile.preset),
      defaultSection: profile.default_section,
      active: profile.active !== false,
      legacyAdmin: role === "admin",
    };
  }
  if (role === "admin") {
    return {
      authUserId: user.id,
      staffId: clean(user.email).split("@")[0] || "admin",
      staffName: clean(user.user_metadata?.name) || clean(user.email).split("@")[0] || "Administrator",
      preset: "administrator",
      permissions: { ...ALL_PERMISSIONS },
      defaultSection: "dashboard",
      active: true,
      legacyAdmin: true,
    };
  }
  throw new Error("STAFF_PROFILE_NOT_FOUND");
}

const ACTION_PERMISSIONS: Record<string, string[]> = {
  dashboard: ["dashboard.view"],
  listDesigns: ["products.view", "products.mapping"],
  listMappings: ["products.mapping"],
  mapBarcode: ["products.mapping"],
  mapBatch: ["products.mapping"],
  deactivateBarcode: ["products.mapping"],
  resetPassword: ["reception.password_reset"],
  setCustomerActive: ["reception.customer_control"],
  setOrderLocked: ["sale.lock"],
  directory: ["reception.view", "sale.view", "sale.write"],
  getProductDetail: ["products.view"],
  updateProduct: ["products.edit"],
  checkIn: ["reception.checkin"],
  revokeEntry: ["reception.checkin"],
  listSlots: ["admin.slots", "admin.bookings", "reception.view"],
  upsertSlot: ["admin.slots"],
  deleteSlot: ["admin.slots"],
  listBookings: ["admin.bookings", "reception.view"],
  updateBooking: ["admin.bookings"],
  assistedRegister: ["reception.register"],
  assistedSaveOrder: ["sale.write"],
  recentOrders: ["sale.previous", "sale.write"],
  getCustomerOrders: ["dashboard.view", "sale.previous", "sale.write"],
  createStaff: ["admin.staff"],
  listStaff: ["admin.staff"],
  updateStaff: ["admin.staff"],
  resetStaffPassword: ["admin.staff"],
  getSettings: ["admin.settings"],
  updateSettings: ["admin.settings"],
  listLookupsAdmin: ["products.lookups"],
  upsertLookup: ["products.lookups"],
  deleteLookup: ["products.lookups"],
};

function requireActionPermission(context: StaffContext, action: string) {
  if (!context.active) throw new Error("STAFF_ACCOUNT_DISABLED");
  const alternatives = ACTION_PERMISSIONS[action] ?? [];
  if (alternatives.length && !alternatives.some((key) => context.permissions[key])) {
    throw new Error("PERMISSION_DENIED");
  }
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
    fetchAll(db, "orders", "id,customer_id,firm,status,total_designs,total_sets,total_pieces,version,created_at,updated_at", "created_at"),
    fetchAll(db, "order_items", "id,order_id,barcode,design_no,qty,category_snapshot,style_snapshot,fabric_snapshot,pcs_per_set_snapshot,line_note,color_snapshot,description_snapshot,created_at,updated_at", "created_at"),
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
      style: item.style_snapshot,
      fabric: item.fabric_snapshot,
      pcsPerSet: Number(item.pcs_per_set_snapshot) || 1,
      totalPieces: (Number(item.qty) || 0) * (Number(item.pcs_per_set_snapshot) || 1),
      note: item.line_note ?? "",
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
      totalSets: Number(order.total_sets) || 0,
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
      style: item.style_snapshot,
      fabric: item.fabric_snapshot,
      pcsPerSet: Number(item.pcs_per_set_snapshot) || 1,
      pieces: (Number(item.qty) || 0) * (Number(item.pcs_per_set_snapshot) || 1),
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
      totalSets: itemFacts.reduce((sum, row) => sum + row.qty, 0),
      totalPieces: itemFacts.reduce((sum, row) => sum + row.pieces, 0),
      uniqueDesigns: new Set(itemFacts.map((row) => row.designNo)).size,
      maitriPieces: itemFacts.filter((row) => row.firm === "Maitri").reduce((sum, row) => sum + row.qty, 0),
      niharikaPieces: itemFacts.filter((row) => row.firm === "Niharika").reduce((sum, row) => sum + row.qty, 0),
    },
    charts: {
      firmPieces: groupSum(itemFacts, (row) => row.firm, (row) => row.qty),
      statePieces: groupSum(itemFacts, (row) => row.state, (row) => row.qty),
      cityPieces: groupSum(itemFacts, (row) => row.city, (row) => row.qty),
      categorySets: groupSum(itemFacts, (row) => row.category, (row) => row.qty),
      styleSets: groupSum(itemFacts, (row) => row.style, (row) => row.qty),
      fabricSets: groupSum(itemFacts, (row) => row.fabric, (row) => row.qty),
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
    .select("design_no,firm,image_url,category,style,fabric,pcs_per_set,color,description,active,sync_version,updated_at")
    .order("design_no", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    designNo: row.design_no,
    firm: row.firm,
    imageUrl: row.image_url ?? "",
    category: row.category,
    style: row.style,
    fabric: row.fabric,
    pcsPerSet: Number(row.pcs_per_set) || 1,
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
    .select("barcode,design_no,active,mapped_at,updated_at,designs(firm,category,style,fabric,pcs_per_set,color)")
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
    style: row.designs?.style ?? "",
    fabric: row.designs?.fabric ?? "",
    pcsPerSet: Number(row.designs?.pcs_per_set) || 1,
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
    const staff = await loadStaffContext(db, admin);

    const me = {
      id: admin.id,
      role: clean(admin.app_metadata?.role) || "staff",
      staffId: staff.staffId,
      staffName: staff.staffName,
      preset: staff.preset,
      permissions: staff.permissions,
      defaultSection: staff.defaultSection,
      active: staff.active,
    };

    if (action === "whoami") {
      if (!staff.active) throw new Error("STAFF_ACCOUNT_DISABLED");
      return jsonResponse(request, { ok: true, data: me });
    }

    if (action === "bootstrap") {
      if (!staff.active) throw new Error("STAFF_ACCOUNT_DISABLED");
      const { data: lookups, error: lookupError } = await db.rpc("list_lookups");
      if (lookupError) throw lookupError;
      return jsonResponse(request, {
        ok: true,
        data: { me, lookups: lookups ?? {} },
      });
    }

    requireActionPermission(staff, action);

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
      // Unlocking sets admin_unlocked so the customer can edit past the 24h window.
      const { data, error } = await db
        .from("orders")
        .update({ status: locked ? "Locked" : "Saved", admin_unlocked: locked ? false : true })
        .eq("id", orderId)
        .select("id,firm,status,admin_unlocked,updated_at")
        .single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    // ---- Entry gate ----------------------------------------------------
    if (action === "directory") {
      const { data, error } = await db.rpc("admin_directory", {
        p_query: clean(body.query),
        p_limit: 400,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: data ?? [] });
    }

    if (action === "getProductDetail") {
      const dn = clean(body.designNo);
      const { data: d, error } = await db
        .from("designs")
        .select("design_no,firm,image_url,category,style,fabric,pcs_per_set,color,description,active,updated_at")
        .eq("design_no", dn)
        .maybeSingle();
      if (error) throw error;
      if (!d) throw new Error("Design not found");
      const { data: bcs, error: bErr } = await db
        .from("barcode_mappings")
        .select("barcode,active,updated_at")
        .eq("design_no", dn)
        .order("updated_at", { ascending: false });
      if (bErr) throw bErr;
      return jsonResponse(request, {
        ok: true,
        data: {
          design: {
            designNo: d.design_no, firm: d.firm, imageUrl: d.image_url,
            category: d.category, style: d.style, fabric: d.fabric,
            pcsPerSet: Number(d.pcs_per_set) || 1, color: d.color,
            description: d.description, active: d.active, updatedAt: d.updated_at,
          },
          barcodes: (bcs ?? []).map((b) => ({ barcode: b.barcode, active: b.active })),
        },
      });
    }

    if (action === "updateProduct") {
      const dn = clean(body.designNo);
      if (!dn) throw new Error("Design number is required");
      const firm = clean(body.firm);
      if (!["Maitri", "Niharika", "Both"].includes(firm)) throw new Error("Firm must be Maitri, Niharika or Both");
      // Image is owned by the Excel/sheet sync and is not editable here.
      const pcsPerSet = Math.round(Number(body.pcsPerSet));
      if (!Number.isFinite(pcsPerSet) || pcsPerSet < 1 || pcsPerSet > 9999) {
        throw new Error("Pcs per set must be between 1 and 9999");
      }
      const patch = {
        firm,
        category: clean(body.category),
        style: clean(body.style),
        fabric: clean(body.fabric),
        pcs_per_set: pcsPerSet,
        description: clean(body.description),
        active: body.active === undefined ? true : Boolean(body.active),
      };
      const { data, error } = await db.from("designs").update(patch).eq("design_no", dn).select("design_no").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "checkIn") {
      const { data, error } = await db.rpc("check_in_customer", {
        p_customer_id: clean(body.customerId),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "revokeEntry") {
      const { data, error } = await db.rpc("revoke_entry", {
        p_customer_id: clean(body.customerId),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    // ---- Slots & bookings ---------------------------------------------
    if (action === "listSlots") {
      const [{ data: slots, error: sErr }, { data: booked, error: bErr }] = await Promise.all([
        db.from("slots").select("id,starts_at,ends_at,label,capacity,active").order("starts_at", { ascending: true }),
        db.from("bookings").select("slot_id").eq("status", "Booked"),
      ]);
      if (sErr) throw sErr;
      if (bErr) throw bErr;
      const counts = new Map<string, number>();
      for (const b of booked ?? []) counts.set(b.slot_id, (counts.get(b.slot_id) ?? 0) + 1);
      return jsonResponse(request, {
        ok: true,
        data: (slots ?? []).map((s) => ({
          id: s.id,
          startsAt: s.starts_at,
          endsAt: s.ends_at,
          label: s.label,
          capacity: s.capacity,
          active: s.active,
          booked: counts.get(s.id) ?? 0,
        })),
      });
    }

    if (action === "upsertSlot") {
      const row: Record<string, unknown> = {
        starts_at: clean(body.startsAt),
        ends_at: clean(body.endsAt),
        label: clean(body.label),
        capacity: body.capacity === null || body.capacity === "" || body.capacity === undefined ? null : Number(body.capacity),
        active: body.active === undefined ? true : Boolean(body.active),
      };
      if (!row.starts_at || !row.ends_at) throw new Error("Slot start and end are required");
      const id = clean(body.id);
      const { data, error } = id
        ? await db.from("slots").update(row).eq("id", id).select("id").single()
        : await db.from("slots").insert(row).select("id").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "deleteSlot") {
      const id = clean(body.id);
      const { count, error: cErr } = await db
        .from("bookings").select("id", { count: "exact", head: true }).eq("slot_id", id).eq("status", "Booked");
      if (cErr) throw cErr;
      if ((count ?? 0) > 0) {
        const { error } = await db.from("slots").update({ active: false }).eq("id", id);
        if (error) throw error;
        return jsonResponse(request, { ok: true, data: { deactivated: true, bookings: count } });
      }
      const { error } = await db.from("slots").delete().eq("id", id);
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: { deleted: true } });
    }

    if (action === "listBookings") {
      const { data, error } = await db
        .from("bookings")
        .select("id,party_size,note,status,created_at,slots(starts_at,ends_at,label),customers(company_name,contact_name,phone_e164,checked_in_at)")
        .eq("status", "Booked")
        .limit(1000);
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: (data ?? []).map((b: any) => ({
          id: b.id,
          partySize: b.party_size,
          note: b.note,
          startsAt: b.slots?.starts_at ?? null,
          endsAt: b.slots?.ends_at ?? null,
          slotLabel: b.slots?.label ?? "",
          companyName: b.customers?.company_name ?? "",
          contactName: b.customers?.contact_name ?? "",
          phone: b.customers?.phone_e164 ?? "",
          checkedIn: !!b.customers?.checked_in_at,
        })),
      });
    }

    if (action === "updateBooking") {
      const id = clean(body.id);
      const patch: Record<string, unknown> = {};
      if (body.slotId !== undefined) patch.slot_id = clean(body.slotId);
      if (body.partySize !== undefined) patch.party_size = Math.max(1, Math.min(99, Math.round(Number(body.partySize) || 1)));
      if (body.note !== undefined) patch.note = clean(body.note);
      if (body.status !== undefined) patch.status = clean(body.status) === "Cancelled" ? "Cancelled" : "Booked";
      const { data, error } = await db.from("bookings").update(patch).eq("id", id).select("id,status,slot_id,party_size,note").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "getSettings") {
      const { data, error } = await db.from("system_settings")
        .select("event_name,event_start_date,event_end_date,registration_enabled,edit_window_hours,registration_access_code_hash")
        .eq("singleton", true).single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: {
        eventName: data.event_name,
        eventStartDate: data.event_start_date,
        eventEndDate: data.event_end_date,
        registrationEnabled: data.registration_enabled,
        editWindowHours: data.edit_window_hours,
        accessCodeEnabled: !!data.registration_access_code_hash,
      } });
    }

    if (action === "updateSettings") {
      const patch: Record<string, unknown> = {
        event_name: clean(body.eventName),
        event_start_date: clean(body.eventStartDate),
        event_end_date: clean(body.eventEndDate),
        registration_enabled: Boolean(body.registrationEnabled),
        edit_window_hours: Math.max(1, Math.min(168, Math.round(Number(body.editWindowHours) || 24))),
      };
      if (Boolean(body.clearAccessCode)) patch.registration_access_code_hash = null;
      else if (clean(body.accessCode)) {
        const bytes = new TextEncoder().encode(clean(body.accessCode));
        const digest = await crypto.subtle.digest("SHA-256", bytes);
        patch.registration_access_code_hash = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2,"0")).join("");
      }
      const { data, error } = await db.from("system_settings").update(patch).eq("singleton", true)
        .select("event_name,event_start_date,event_end_date,registration_enabled,edit_window_hours,registration_access_code_hash").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "listLookupsAdmin") {
      const { data, error } = await db.from("lookup_values").select("kind,value,created_at").order("kind").order("value");
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "upsertLookup") {
      const kind = clean(body.kind).toLowerCase();
      const value = clean(body.value);
      if (!["city","agent","category","style","fabric"].includes(kind)) throw new Error("Invalid lookup type");
      if (!value) throw new Error("Lookup value is required");
      const { data, error } = await db.from("lookup_values")
        .upsert({ kind, value }, { onConflict: "kind,value" })
        .select("kind,value").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "deleteLookup") {
      const { error } = await db.from("lookup_values").delete()
        .eq("kind", clean(body.kind).toLowerCase()).eq("value", clean(body.value));
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: { deleted: true } });
    }

    // ---- Assisted registration & ordering -----------------------------
    if (action === "assistedRegister") {
      const phone = normalizePhone(body.phone);
      const companyName = clean(body.companyName);
      const contactName = clean(body.contactName);
      if (companyName.length < 2) throw new Error("Company name is required");
      if (contactName.length < 2) throw new Error("Contact person is required");
      const password = clean(body.password) || generatePassword();
      if (password.length < 8) throw new Error("Password must be at least 8 characters");
      const { data: created, error } = await db.auth.admin.createUser({
        email: hiddenEmail(phone),
        password,
        email_confirm: true,
        user_metadata: {
          phone_e164: phone,
          company_name: companyName,
          contact_name: contactName,
          city: clean(body.city),
          state: clean(body.state),
          gstin: clean(body.gstin).toUpperCase(),
          agent: clean(body.agent),
          login_method: "phone_password_hidden_email",
          created_by: "admin_assisted",
        },
      });
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: { customerId: created.user?.id, phone, password, companyName },
      });
    }

    if (action === "createStaff") {
      const staffId = normalizeStaffId(body.staffId);
      const staffName = clean(body.staffName);
      if (staffName.length < 2) throw new Error("Staff name is required");
      const preset = ["sales","reception","products","manager","administrator","custom"].includes(clean(body.preset)) ? clean(body.preset) : "custom";
      const permissions = normalizePermissions(body.permissions, preset);
      const allowedSections = ["reception","dashboard","sale","products","admin"];
      const defaultSection = allowedSections.includes(clean(body.defaultSection)) ? clean(body.defaultSection) : "sale";
      const modulePermission: Record<string,string> = { reception:"reception.view", dashboard:"dashboard.view", sale:"sale.view", products:"products.view", admin:"admin.slots" };
      if (!permissions[modulePermission[defaultSection]] && defaultSection !== "admin") throw new Error("Default section must be permitted");
      if (defaultSection === "admin" && !Object.keys(permissions).some((key) => key.startsWith("admin.") && permissions[key])) throw new Error("Default section must be permitted");
      const password = clean(body.password) || generatePassword();
      if (password.length < 8) throw new Error("Password must be at least 8 characters");
      const email = staffEmail(staffId);
      const { data: created, error } = await db.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { role: "staff" },
        user_metadata: { name: staffName, staff_id: staffId },
      });
      if (error) throw error;
      const userId = created.user?.id;
      if (!userId) throw new Error("STAFF_USER_NOT_CREATED");
      const { error: profileError } = await db.from("staff_profiles").insert({
        auth_user_id: userId,
        staff_id: staffId,
        staff_name: staffName,
        preset,
        permissions,
        default_section: defaultSection,
        active: true,
      });
      if (profileError) {
        await db.auth.admin.deleteUser(userId).catch(() => undefined);
        throw profileError;
      }
      return jsonResponse(request, { ok: true, data: { id: userId, staffId, staffName, email, password, preset, permissions, defaultSection } });
    }

    if (action === "listStaff") {
      const { data, error } = await db.from("staff_profiles")
        .select("auth_user_id,staff_id,staff_name,preset,permissions,default_section,active,created_at,updated_at")
        .order("staff_name", { ascending: true });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: (data ?? []).map((row: any) => ({
        authUserId: row.auth_user_id, staffId: row.staff_id, staffName: row.staff_name,
        preset: row.preset, permissions: normalizePermissions(row.permissions,row.preset),
        defaultSection: row.default_section, active: row.active, createdAt: row.created_at, updatedAt: row.updated_at,
      })) });
    }

    if (action === "updateStaff") {
      const authUserId = clean(body.authUserId);
      const preset = ["sales","reception","products","manager","administrator","custom"].includes(clean(body.preset)) ? clean(body.preset) : "custom";
      const permissions = normalizePermissions(body.permissions,preset);
      const defaultSection = ["reception","dashboard","sale","products","admin"].includes(clean(body.defaultSection)) ? clean(body.defaultSection) : "sale";
      const row: Record<string,unknown> = { preset, permissions, default_section: defaultSection };
      if (body.staffName !== undefined) row.staff_name = clean(body.staffName);
      if (body.active !== undefined) row.active = Boolean(body.active);
      const { data, error } = await db.from("staff_profiles").update(row).eq("auth_user_id",authUserId)
        .select("auth_user_id,staff_id,staff_name,preset,permissions,default_section,active").single();
      if (error) throw error;
      return jsonResponse(request,{ok:true,data});
    }

    if (action === "resetStaffPassword") {
      const authUserId = clean(body.authUserId);
      const password = clean(body.password) || generatePassword();
      if (password.length < 8) throw new Error("Password must be at least 8 characters");
      const { error } = await db.auth.admin.updateUserById(authUserId,{password});
      if (error) throw error;
      return jsonResponse(request,{ok:true,data:{password}});
    }

    if (action === "assistedSaveOrder") {
      const items = Array.isArray(body.items) ? body.items : [];
      const { data, error } = await db.rpc("admin_save_order_with_actor", {
        p_customer_id: clean(body.customerId),
        p_firm: clean(body.firm),
        p_items: items,
        p_request_id: crypto.randomUUID(),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "recentOrders") {
      const q = clean(body.query);
      let query = db.from("orders")
        .select("id,customer_id,firm,status,total_designs,total_sets,total_pieces,updated_at,customers(company_name,contact_name,phone_e164,city,state,agent)")
        .order("updated_at", { ascending: false }).limit(200);
      if (q) {
        const { data: customers, error: cErr } = await db.from("customers")
          .select("id").or(`company_name.ilike.%${q}%,contact_name.ilike.%${q}%,phone_e164.ilike.%${q}%`).limit(300);
        if (cErr) throw cErr;
        const ids = (customers ?? []).map((row) => row.id);
        if (!ids.length) return jsonResponse(request,{ok:true,data:[]});
        query = query.in("customer_id",ids);
      }
      const { data, error } = await query;
      if (error) throw error;
      return jsonResponse(request,{ok:true,data:(data ?? []).filter((o:any)=>Number(o.total_designs)>0 || o.status!=="Draft").map((o:any)=>({
        orderId:o.id,customerId:o.customer_id,firm:o.firm,status:o.status,designs:Number(o.total_designs)||0,
        sets:Number(o.total_sets)||0,pieces:Number(o.total_pieces)||0,updatedAt:o.updated_at,
        companyName:o.customers?.company_name??"",contactName:o.customers?.contact_name??"",phone:o.customers?.phone_e164??"",
        city:o.customers?.city??"",state:o.customers?.state??"",agent:o.customers?.agent??""
      }))});
    }

    if (action === "getCustomerOrders") {
      const customerId = clean(body.customerId);
      const { data: cust } = await db
        .from("customers")
        .select("company_name,contact_name,phone_e164,city,state,agent,gstin,active,checked_in_at")
        .eq("id", customerId)
        .maybeSingle();
      // Fetch both firm orders + items for assisted editing.
      const { data: orders, error: oErr } = await db
        .from("orders")
        .select("id,firm,status,version,total_designs,total_sets,total_pieces,admin_unlocked,order_items(barcode,design_no,qty,category_snapshot,style_snapshot,fabric_snapshot,pcs_per_set_snapshot,line_note,color_snapshot,description_snapshot,created_by_type,last_modified_by_type,last_modified_by_user_id,designs(image_url))")
        .eq("customer_id", customerId);
      if (oErr) throw oErr;
      const shaped = (orders ?? []).map((o: any) => ({
        id: o.id,
        firm: o.firm,
        status: o.status,
        version: o.version,
        totalDesigns: o.total_designs,
        totalSets: o.total_sets,
        totalPieces: o.total_pieces,
        adminUnlocked: o.admin_unlocked,
        items: (o.order_items ?? []).map((i: any) => ({
          barcode: i.barcode,
          designNo: i.design_no,
          qty: i.qty,
          category: i.category_snapshot,
          style: i.style_snapshot,
          fabric: i.fabric_snapshot,
          pcsPerSet: Number(i.pcs_per_set_snapshot) || 1,
          totalPieces: Number(i.qty || 0) * (Number(i.pcs_per_set_snapshot) || 1),
          note: i.line_note ?? "",
          color: i.color_snapshot,
          description: i.description_snapshot,
          createdByType: i.created_by_type ?? "unknown",
          lastModifiedByType: i.last_modified_by_type ?? "unknown",
          lastModifiedByUserId: i.last_modified_by_user_id ?? null,
          imageUrl: i.designs?.image_url ?? "",
        })),
      }));
      return jsonResponse(request, {
        ok: true,
        data: {
          orders: shaped,
          customer: cust ? {
            companyName: cust.company_name, contactName: cust.contact_name,
            phone: cust.phone_e164, city: cust.city, state: cust.state,
            agent: cust.agent, gstin: cust.gstin, active: cust.active,
            checkedIn: !!cust.checked_in_at,
          } : null,
        },
      });
    }

    return jsonResponse(request, { ok: false, error: `UNKNOWN_ACTION_${action}` }, 400);
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = /PERMISSION_DENIED|STAFF_ACCESS_REQUIRED|STAFF_ACCOUNT_DISABLED|STAFF_PROFILE_NOT_FOUND|ADMIN_REQUIRED/.test(message)
      ? 403
      : message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
