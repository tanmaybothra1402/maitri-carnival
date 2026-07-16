BUNDLE 2 of 6 — SUPABASE EDGE FUNCTIONS (Deno/TypeScript). Contains 4 files.


################################################################################
# FILE: supabase/functions/customer-auth/index.ts
################################################################################

import { optionsResponse } from "../_shared/cors.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { authClient, serviceClient } from "../_shared/supabase.ts";

const CUSTOMER_DOMAIN = "accounts.maitricarnival.app";

type AuthSessionPayload = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  expires_at?: number;
  token_type: string;
};

function normalizePhone(value: unknown): string {
  let digits = clean(value).replace(/\D/g, "");
  if (digits.length === 10) digits = `91${digits}`;
  if (!/^91[6-9]\d{9}$/.test(digits)) {
    throw new Error("Enter a valid 10-digit Indian mobile number");
  }
  return digits;
}

function hiddenEmail(phone: string): string {
  return `c${phone}@${CUSTOMER_DOMAIN}`;
}

function validatePassword(value: unknown): string {
  const password = String(value ?? "");
  if (password.length < 8) throw new Error("Password must be at least 8 characters");
  if (password.length > 72) throw new Error("Password is too long");
  return password;
}

function sessionPayload(session: any): AuthSessionPayload {
  if (!session?.access_token || !session?.refresh_token) {
    throw new Error("AUTH_SESSION_NOT_CREATED");
  }
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: Number(session.expires_in ?? 3600),
    expires_at: session.expires_at ? Number(session.expires_at) : undefined,
    token_type: String(session.token_type ?? "bearer"),
  };
}

function publicError(error: unknown): { message: string; status: number } {
  const raw = errorMessage(error);
  const lower = raw.toLowerCase();

  if (lower.includes("already") || lower.includes("email_exists") || lower.includes("duplicate")) {
    return { message: "An account already exists for this mobile number. Use Login.", status: 409 };
  }
  if (lower.includes("invalid login credentials") || lower.includes("invalid_credentials")) {
    return { message: "Incorrect mobile number or password.", status: 401 };
  }
  if (raw.includes("REGISTRATION_CLOSED")) {
    return { message: "Customer registration is currently closed.", status: 403 };
  }
  if (raw.includes("INVALID_EXHIBITION_ACCESS_CODE")) {
    return { message: "The exhibition access code is incorrect.", status: 403 };
  }
  if (raw.includes("COMPANY_NAME_REQUIRED")) {
    return { message: "Company name is required.", status: 400 };
  }
  if (raw.includes("CONTACT_NAME_REQUIRED")) {
    return { message: "Contact person is required.", status: 400 };
  }
  if (lower.includes("rate limit")) {
    return { message: "Too many attempts. Wait a few minutes and try again.", status: 429 };
  }
  if (
    lower.includes("valid 10-digit") ||
    lower.includes("password must") ||
    lower.includes("password is too long")
  ) {
    return { message: raw, status: 400 };
  }
  return { message: "Authentication could not be completed. Please contact exhibition staff.", status: 500 };
}

async function signIn(email: string, password: string) {
  const client = authClient();
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return sessionPayload(data.session);
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") {
    return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);
  }

  try {
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action).toLowerCase();
    const phone = normalizePhone(body.phone);
    const password = validatePassword(body.password);
    const email = hiddenEmail(phone);

    if (action === "login") {
      const session = await signIn(email, password);
      return jsonResponse(request, { ok: true, data: { session } });
    }

    if (action === "register") {
      const companyName = clean(body.companyName);
      const contactName = clean(body.contactName);
      const city = clean(body.city);
      const state = clean(body.state);
      const gstin = clean(body.gstin).toUpperCase();
      const agent = clean(body.agent);
      const accessCode = clean(body.accessCode);

      if (companyName.length < 2) throw new Error("COMPANY_NAME_REQUIRED");
      if (contactName.length < 2) throw new Error("CONTACT_NAME_REQUIRED");

      const admin = serviceClient();
      const { error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          phone_e164: phone,
          company_name: companyName,
          contact_name: contactName,
          city,
          state,
          gstin,
          agent,
          access_code: accessCode,
          login_method: "phone_password_hidden_email",
        },
      });
      if (createError) throw createError;

      const session = await signIn(email, password);
      return jsonResponse(request, { ok: true, data: { session } }, 201);
    }

    return jsonResponse(request, { ok: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    console.error("customer-auth", error);
    const mapped = publicError(error);
    return jsonResponse(request, { ok: false, error: mapped.message }, mapped.status);
  }
});


################################################################################
# FILE: supabase/functions/admin-api/index.ts
################################################################################

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
      const q = clean(body.query);
      let query = db
        .from("customers")
        .select("id,phone_e164,company_name,contact_name,city,state,gstin,active,checked_in_at,ordering_started_at,edit_deadline,created_at")
        .order("created_at", { ascending: false })
        .limit(400);
      if (q) {
        const like = `%${q}%`;
        // Search across every customer field.
        query = query.or(
          `phone_e164.ilike.${like},company_name.ilike.${like},contact_name.ilike.${like},city.ilike.${like},state.ilike.${like},gstin.ilike.${like}`,
        );
      }
      const { data, error } = await query;
      if (error) throw error;
      // Attach each customer's booked slot.
      const ids = (data ?? []).map((r) => r.id);
      const bookingByCust = new Map<string, any>();
      if (ids.length) {
        const { data: bks, error: bErr } = await db
          .from("bookings")
          .select("customer_id,party_size,slots(starts_at,ends_at,label)")
          .eq("status", "Booked")
          .in("customer_id", ids);
        if (bErr) throw bErr;
        for (const b of bks ?? []) {
          bookingByCust.set(b.customer_id, {
            startsAt: (b as any).slots?.starts_at ?? null,
            endsAt: (b as any).slots?.ends_at ?? null,
            label: (b as any).slots?.label ?? "",
            partySize: b.party_size,
          });
        }
      }
      return jsonResponse(request, {
        ok: true,
        data: (data ?? []).map((r) => ({
          id: r.id,
          phone: r.phone_e164,
          companyName: r.company_name,
          contactName: r.contact_name,
          city: r.city,
          state: r.state,
          gstin: r.gstin,
          active: r.active,
          checkedInAt: r.checked_in_at,
          orderingStartedAt: r.ordering_started_at,
          editDeadline: r.edit_deadline,
          booking: bookingByCust.get(r.id) ?? null,
        })),
      });
    }

    if (action === "getProductDetail") {
      const dn = clean(body.designNo);
      const { data: d, error } = await db
        .from("designs")
        .select("design_no,firm,image_url,category,fabric,color,description,active,updated_at")
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
            category: d.category, fabric: d.fabric, color: d.color,
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
      const patch = {
        firm,
        category: clean(body.category),
        fabric: clean(body.fabric),
        color: clean(body.color),
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
      const email = clean(body.email).toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Error("Enter a valid email address");
      if (email.endsWith(CUSTOMER_DOMAIN)) throw new Error("Use a normal email, not the customer domain");
      const password = clean(body.password) || generatePassword();
      if (password.length < 8) throw new Error("Password must be at least 8 characters");
      const { data: created, error } = await db.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { role: "admin" },
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: { id: created.user?.id, email, password } });
    }

    if (action === "assistedSaveOrder") {
      const items = Array.isArray(body.items) ? body.items : [];
      const { data, error } = await db.rpc("admin_save_order", {
        p_customer_id: clean(body.customerId),
        p_firm: clean(body.firm),
        p_items: items,
        p_request_id: crypto.randomUUID(),
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
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
        .select("id,firm,status,version,total_designs,total_pieces,admin_unlocked,order_items(barcode,design_no,qty,category_snapshot,fabric_snapshot,color_snapshot,description_snapshot,designs(image_url))")
        .eq("customer_id", customerId);
      if (oErr) throw oErr;
      const shaped = (orders ?? []).map((o: any) => ({
        id: o.id,
        firm: o.firm,
        status: o.status,
        version: o.version,
        totalDesigns: o.total_designs,
        totalPieces: o.total_pieces,
        adminUnlocked: o.admin_unlocked,
        items: (o.order_items ?? []).map((i: any) => ({
          barcode: i.barcode,
          designNo: i.design_no,
          qty: i.qty,
          category: i.category_snapshot,
          fabric: i.fabric_snapshot,
          color: i.color_snapshot,
          description: i.description_snapshot,
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
    const status = message === "ADMIN_REQUIRED" ? 403 : message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});


################################################################################
# FILE: supabase/functions/data-sync/index.ts
################################################################################

// Generic two-way data mirror for the Google Sheet workbook.
// Secret-gated (x-sheet-sync-secret). Pull = read a table; Push = upsert/update/delete
// rows. Only whitelisted (writable) columns are ever changed.

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
  recomputeOrders?: boolean;
};

const TABLES: Record<string, TableCfg> = {
  designs: {
    pk: "design_no",
    cols: ["design_no","firm","image_url","category","fabric","color","description","active","sync_version","updated_at"],
    write: ["firm","image_url","category","fabric","color","description","active"],
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
    cols: ["id","customer_id","firm","status","total_designs","total_pieces","version","admin_unlocked","updated_at"],
    write: ["status","admin_unlocked"],
    insert: false,
  },
  order_items: {
    pk: "id",
    cols: ["id","order_id","barcode","design_no","qty","category_snapshot","fabric_snapshot","color_snapshot","description_snapshot"],
    write: ["qty"],
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
  lookup_values: {
    pk: ["kind","value"],
    cols: ["kind","value","created_at"],
    write: ["kind","value"],
    insert: true,
  },
  system_settings: {
    pk: "singleton",
    cols: ["singleton","event_name","event_start_date","event_end_date","registration_enabled","edit_window_hours","customer_email_domain"],
    write: ["event_name","event_start_date","event_end_date","registration_enabled","edit_window_hours"],
    insert: false,
  },
};

const BOOL = new Set(["active","admin_unlocked","registration_enabled","singleton"]);
const INT = new Set(["qty","capacity","party_size","total_designs","total_pieces","version","edit_window_hours"]);

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
  const extra: string[] = [];
  for (const r of out) for (const k of Object.keys(r)) if (!seen.has(k)) { seen.add(k); extra.push(k); }
  return { table, columns: cfg.cols.concat(extra), rows: out };
}

async function recompute(db: SupabaseClient, orderId: string) {
  const { data } = await db.from("order_items").select("qty").eq("order_id", orderId);
  const items = data ?? [];
  await db.from("orders").update({
    total_designs: items.length,
    total_pieces: items.reduce((s: number, i: any) => s + Number(i.qty || 0), 0),
    updated_at: new Date().toISOString(),
  }).eq("id", orderId);
}

async function push(db: SupabaseClient, table: string, rows: any[]) {
  const cfg = TABLES[table];
  if (!cfg) throw new Error("UNKNOWN_TABLE_" + table);
  if (!Array.isArray(rows)) throw new Error("ROWS_MUST_BE_AN_ARRAY");
  const pkArr = Array.isArray(cfg.pk) ? cfg.pk : [cfg.pk];
  const affected = new Set<string>();
  const upserts: any[] = [];
  const inserts: any[] = [];
  let updated = 0, deleted = 0;

  for (const raw of rows) {
    const r = raw || {};
    if (cfg.recomputeOrders && r.order_id) affected.add(String(r.order_id));
    const hasPk = pkArr.every((k) => String(r[k] ?? "").trim() !== "");

    if (truthy(r._delete)) {
      if (!hasPk) continue;
      const m: any = {}; pkArr.forEach((k) => m[k] = coerce(k, r[k]));
      const { error } = await db.from(table).delete().match(m);
      if (error) throw error;
      deleted++; continue;
    }

    const patch: any = {};
    for (const c of cfg.write) if (c in r) patch[c] = coerce(c, r[c]);

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


################################################################################
# FILE: supabase/functions/sheet-sync/index.ts
################################################################################

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
