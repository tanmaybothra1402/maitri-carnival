
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
        .select("id,firm,status,version,total_designs,total_sets,total_pieces,admin_unlocked,order_items(barcode,design_no,qty,category_snapshot,style_snapshot,fabric_snapshot,pcs_per_set_snapshot,line_note,color_snapshot,description_snapshot,designs(image_url))")
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
