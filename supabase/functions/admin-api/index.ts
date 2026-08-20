
import { optionsResponse } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const CUSTOMER_DOMAIN = "accounts.maitricarnival.app";
const STAFF_DOMAIN = "staff.maitricarnival.app";

// ImageKit client-upload signature (HMAC-SHA1 of token+expire with the private key).
async function hmacSha1Hex(key: string, data: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// App uploads follow the existing ImageKit library, filed by design prefix — see
// the maitri-media skill. Never dump at the root (unfindable among 11.7K files).
function imagekitFolder(designNo: string): string {
  // Bare letter prefix, e.g. "MU - 0322" -> "/MU". This matches the catalogue
  // convention VERIFIED against the DB: 579/593 stored image URLs sit under the
  // bare-prefix folder (/MU, /BS, /NRK…). The earlier "-DESIGN" mapping appears in
  // ZERO of the 593 stored URLs, so it was almost certainly never exercised — this
  // only aligns FUTURE uploads with the catalogue. UNVERIFIED that "-DESIGN" ever
  // wrote a real file. The stored URL is authoritative regardless: we upload with
  // useUniqueFileName and persist whatever ImageKit returns — the folder is not
  // predicted or relied on. (Only caller: signImageUpload.)
  const prefix = (clean(designNo).match(/^[A-Za-z]+/)?.[0] ?? "").toUpperCase();
  return prefix ? "/" + prefix : "/App-Uploads";
}

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
  "products.create": true,
  "dispatch.view": true,
  "dispatch.write": true,
  "crm.view": true,
  "crm.write": true,
  "crm.assign": true,
  // Mass CRM edits (bulk reassign / retype / retier). A separate high-blast-radius
  // key held by only a couple of accounts — NOT part of the CRM module group, and
  // deliberately excluded from the manager/administrator presets so it is never
  // granted broadly. Must be listed here so normalizePermissions preserves it on
  // read (a key absent from ALL_PERMISSIONS is silently stripped).
  "crm.bulk": true,
  "admin.slots": true,
  "admin.bookings": true,
  "admin.staff": true,
  "admin.settings": true,
  "admin.exhibitions": true,
};

const PRESET_PERMISSIONS: Record<string, Record<string, boolean>> = {
  sales: { "sale.view": true, "sale.write": true, "sale.previous": true, "sale.pdf": true, "reception.view": true },
  reception: { "reception.view": true, "reception.checkin": true, "reception.register": true, "reception.password_reset": true, "reception.customer_control": true, "admin.bookings": true },
  products: { "products.view": true, "products.edit": true, "products.mapping": true },
  dispatch: { "dispatch.view": true, "dispatch.write": true, "sale.pdf": true },
  // The three CRM keys always move together. crm.assign is a write action INSIDE
  // the CRM module — it must not ride on an unrelated group (that produced
  // assign-without-view when Admin was edited). See GROUPS.crm.
  crm: { "crm.view": true, "crm.write": true, "crm.assign": true },
  // crm.bulk is intentionally NOT in any preset (not even administrator). It is a
  // rare, high-blast-radius capability granted to a named handful of accounts only
  // (see migration 202608010023). Presets must not hand it out en masse.
  manager: Object.fromEntries(Object.entries(ALL_PERMISSIONS).filter(([key]) => !["admin.staff", "admin.settings", "admin.exhibitions", "products.create", "crm.bulk"].includes(key))),
  administrator: Object.fromEntries(Object.entries(ALL_PERMISSIONS).filter(([key]) => key !== "crm.bulk")),
  custom: {},
};

const GROUPS: Record<string, string[]> = {
  reception: [
    "reception.view",
    "reception.checkin",
    "reception.register",
    "reception.password_reset",
    "reception.customer_control",
    "admin.bookings",
  ],
  sales: [
    "sale.view",
    "sale.write",
    "sale.previous",
    "sale.pdf",
    "sale.lock",
    "reception.view",
  ],
  products: ["products.view", "products.edit", "products.mapping"],
  // sale.pdf is included so a dispatch-only packer can print a packing sheet
  // without being granted any Sales rights.
  dispatch: ["dispatch.view", "dispatch.write", "sale.pdf"],
  // All three CRM keys are granted by the CRM checkbox together. crm.assign USED to
  // ride on the admin group; that let editing Admin toggle it independently of
  // crm.view and produced an incoherent assign-without-view state — it now lives
  // here with view + write.
  crm: ["crm.view", "crm.write", "crm.assign"],
  dashboard: ["dashboard.view", "dashboard.export"],
  // products.create is an admin-tier capability (creating a product can overwrite
  // catalogue data), granted alongside admin.settings — never via the Products
  // module. It tracks admin.settings everywhere: here, the presets, and the backfill.
  admin: ["admin.slots", "admin.staff", "admin.settings", "admin.bookings", "admin.exhibitions", "products.create"],
};

function expandGroups(value: unknown): Record<string, boolean> {
  const selected = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  const output: Record<string, boolean> = Object.fromEntries(
    Object.keys(ALL_PERMISSIONS).map((key) => [key, false]),
  );
  for (const [group, permissions] of Object.entries(GROUPS)) {
    if (!selected[group]) continue;
    for (const permission of permissions) output[permission] = true;
  }
  return output;
}

function collapseGroups(permissions: Record<string, boolean>): Record<string, boolean> {
  return {
    reception: Boolean(permissions["reception.view"]),
    sales: Boolean(permissions["sale.view"]),
    products: Boolean(permissions["products.view"]),
    dispatch: Boolean(permissions["dispatch.view"]),
    crm: Boolean(permissions["crm.view"]),
    dashboard: Boolean(permissions["dashboard.view"]),
    admin: Boolean(
      permissions["admin.staff"] ||
      permissions["admin.settings"] ||
      permissions["admin.slots"] ||
      permissions["admin.exhibitions"]
    ),
  };
}

// Server-side coherence guard, mutates in place. A staff member must never hold
// crm.assign (a CRM write action) without crm.view — that "can act but can't see"
// state is exactly the bug that shipped. Enforced here, at the write path, because
// the UI is not the only writer. Drop the orphaned action rather than silently
// granting read access nobody selected.
function enforcePermissionCoherence(permissions: Record<string, boolean>): void {
  if (permissions["crm.assign"] && !permissions["crm.view"]) permissions["crm.assign"] = false;
  // crm.bulk operates on the CRM list — holding it without crm.view is the same
  // "can act but can't see" incoherence. Drop it rather than silently widening read.
  if (permissions["crm.bulk"] && !permissions["crm.view"]) permissions["crm.bulk"] = false;
}

type StaffContext = {
  authUserId: string;
  staffId: string;
  staffName: string;
  preset: string;
  permissions: Record<string, boolean>;
  groups: Record<string, boolean>;
  defaultSection: string;
  active: boolean;
  legacyAdmin: boolean;
};

function normalizeStaffId(value: unknown): string {
  const staffId = clean(value).toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,39}$/.test(staffId)) {
    throw new Error("Team ID must be 2-40 characters using letters, numbers, dot, underscore or dash");
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
      groups: collapseGroups(normalizePermissions(profile.permissions, profile.preset)),
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
      // Break-glass legacy admin (role=admin, no staff_profiles row) gets every
      // capability EXCEPT crm.bulk — that stays confined to the two named accounts
      // so "nobody else" holds it. A root operator can still self-grant via SQL.
      permissions: { ...ALL_PERMISSIONS, "crm.bulk": false },
      groups: collapseGroups({ ...ALL_PERMISSIONS }),
      defaultSection: "dashboard",
      active: true,
      legacyAdmin: true,
    };
  }
  throw new Error("TEAM_PROFILE_NOT_FOUND");
}

const ACTION_PERMISSIONS: Record<string, string[]> = {
  // dashboard.view included so the dashboard's per-design thumbnails can load the
  // catalogue. Staff-only (admin-api checks app_metadata.role) — never `authenticated`,
  // so this does not widen master-image exposure to customers.
  listDesigns: ["products.view", "products.mapping", "dashboard.view"],
  countDesigns: ["products.view", "products.mapping", "dashboard.view"],
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
  createProduct: ["products.create"],
  saveProductRows: ["products.create"],
  setProductImage: ["products.create"],
  signImageUpload: ["products.create"],
  checkIn: ["reception.checkin"],
  revokeEntry: ["reception.checkin"],
  listSlots: ["admin.slots", "admin.bookings", "reception.view"],
  upsertSlot: ["admin.slots"],
  deleteSlot: ["admin.slots"],
  listBookings: ["admin.bookings", "reception.view"],
  updateBooking: ["admin.bookings"],
  setCustomerBooking: ["admin.bookings"],
  setSlotActive: ["admin.slots"],
  assistedRegister: ["reception.register"],
  assistedSaveOrder: ["sale.write"],
  recentOrders: ["sale.previous", "sale.write"],
  getCustomerOrders: ["dashboard.view", "sale.previous", "sale.write"],
  listDispatch: ["dispatch.view"],
  getDispatch: ["dispatch.view"],
  saveDispatch: ["dispatch.write"],
  // CRM. view lists/reads; write logs calls, sets buyer type / status, edits
  // references; assign (manager/admin) reassigns a buyer to a salesperson. Every
  // action is listed — an action absent from this map has alternatives.length 0
  // and passes UNGATED (guardrail A3).
  crmListCustomers: ["crm.view"],
  crmCustomerDetail: ["crm.view"],
  crmSetBuyerType: ["crm.write"],
  crmSetTier: ["crm.write"],
  crmSetStatus: ["crm.write"],
  crmSetReferenceFlag: ["crm.write"],
  crmSetToken: ["crm.write"],
  crmLogCall: ["crm.write"],
  // The three mass-edit actions require crm.bulk — a stray "select all shown" can
  // rewrite hundreds of records, so this is gated tighter than per-customer writes.
  // Enforced here (server), not just by hiding the UI: a crm.write salesperson
  // crafting the request directly is rejected.
  crmBulkSetTier: ["crm.bulk"],
  crmBulkSetBuyerType: ["crm.bulk"],
  crmBulkAssign: ["crm.bulk"],
  crmAddReference: ["crm.write"],
  crmDeleteReference: ["crm.write"],
  crmAssign: ["crm.assign"],
  createStaff: ["admin.staff"],
  listStaff: ["admin.staff"],
  updateStaff: ["admin.staff"],
  resetStaffPassword: ["admin.staff"],
  deleteStaff: ["admin.staff"],
  getSettings: ["admin.settings"],
  updateSettings: ["admin.settings"],
  listExhibitions: ["admin.exhibitions"],
  createExhibition: ["admin.exhibitions"],
  updateExhibition: ["admin.exhibitions"],
  setCurrentExhibition: ["admin.exhibitions"],
};

function requireActionPermission(context: StaffContext, action: string) {
  if (!context.active) throw new Error("TEAM_ACCOUNT_DISABLED");
  const alternatives = ACTION_PERMISSIONS[action] ?? [];
  if (alternatives.length && !alternatives.some((key) => context.permissions[key])) {
    throw new Error("PERMISSION_DENIED");
  }
}

async function listDesigns(db: SupabaseClient) {
  // PostgREST caps a select at 1000 rows. The catalogue passed 1000, so a single
  // fetch SILENTLY truncated the tail (designs invisible to Product Master, manual
  // entry and the dup guard). Page through with .range() until a short page — do NOT
  // raise a server max-rows setting, that just moves the cliff.
  const cols = "design_no,firm,image_url,category,style,fabric,pcs_per_set,color,description,active,sync_version,updated_at";
  const PAGE = 1000;
  const all: Record<string, unknown>[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await db
      .from("designs")
      .select(cols)
      .order("design_no", { ascending: true })
      .range(from, from + PAGE - 1);
    if (error) throw error;
    const rows = data ?? [];
    all.push(...rows);
    if (rows.length < PAGE) break;
  }
  return all.map((row: any) => ({
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
  // Barcode mappings are global (one sticker run across every exhibition).
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

// Resolve the exhibition a request targets: body.exhibitionId if given (must
// exist), else the current exhibition. Scoped actions call this and pass the id
// (or slug) into their query/RPC — that pass-through is what makes them
// exhibition-aware. An action that resolves but never uses the result looks
// identical to a scoped one until two exhibitions exist.
async function resolveExhibition(db: SupabaseClient, body: any): Promise<{ id: string; slug: string }> {
  const requested = clean(body?.exhibitionId);
  if (requested) {
    const { data, error } = await db.from("exhibitions").select("id,slug").eq("id", requested).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("UNKNOWN_EXHIBITION");
    return { id: data.id, slug: data.slug };
  }
  const { data, error } = await db.from("exhibitions").select("id,slug").eq("is_current", true).maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("NO_EXHIBITION");
  return { id: data.id, slug: data.slug };
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
      groups: staff.groups,
      defaultSection: staff.defaultSection,
      active: staff.active,
    };

    if (action === "whoami") {
      if (!staff.active) throw new Error("TEAM_ACCOUNT_DISABLED");
      return jsonResponse(request, { ok: true, data: me });
    }

    if (action === "bootstrap") {
      if (!staff.active) throw new Error("TEAM_ACCOUNT_DISABLED");
      return jsonResponse(request, { ok: true, data: { me } });
    }

    requireActionPermission(staff, action);

        if (action === "listDesigns") {
      return jsonResponse(request, { ok: true, data: await listDesigns(db) });
    }

    if (action === "countDesigns") {
      // Cheap exact count so the client can detect silent truncation: if the cached
      // row count ever differs from this, the catalogue is incomplete — warn loudly.
      const { count, error } = await db.from("designs").select("design_no", { count: "exact", head: true });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: { total: Number(count) || 0 } });
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
        p_exhibition_id: (await resolveExhibition(db, body)).id,
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
      // Taxonomy only — the image is managed via setProductImage (add/replace/remove).
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

    if (action === "createProduct") {
      const dn = clean(body.designNo);
      if (!dn) throw new Error("Design number is required");
      const firm = clean(body.firm);
      if (!["Maitri", "Niharika", "Both"].includes(firm)) throw new Error("Firm must be Maitri, Niharika or Both");
      const pcsPerSet = Math.round(Number(body.pcsPerSet) || 4);
      if (!Number.isFinite(pcsPerSet) || pcsPerSet < 1 || pcsPerSet > 9999) throw new Error("Pcs per set must be between 1 and 9999");
      // Reject an existing design_no. Creating over a sheet-imported design would
      // silently overwrite it; editing an existing one is updateProduct's job.
      const { data: existing, error: exErr } = await db.from("designs").select("design_no").eq("design_no", dn).maybeSingle();
      if (exErr) throw exErr;
      if (existing) throw new Error(`Design ${dn} already exists — open it to edit instead`);
      const { data, error } = await db.from("designs").insert({
        design_no: dn,
        firm,
        category: clean(body.category),
        style: clean(body.style),
        fabric: clean(body.fabric),
        description: clean(body.description),
        pcs_per_set: pcsPerSet,
        image_url: clean(body.imageUrl), // may be blank — a photo can be attached later
        active: true,
      }).select("design_no,firm,category,style,fabric,pcs_per_set,description,image_url,active").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data }, 201);
    }

    if (action === "setProductImage") {
      // Attach / replace / remove a design's photo. Removal is a DISTINCT explicit
      // intent (clearImage:true), never an empty imageUrl — so a photo can never be
      // wiped by omission (mirrors saveProductRows' only-set-when-supplied rule).
      const dn = clean(body.designNo);
      if (!dn) throw new Error("Design number is required");
      if (body.clearImage === true) {
        // Deliberate removal. The ImageKit object is left orphaned — we do not delete
        // from ImageKit here (removing the URL does not free storage).
        const { data, error } = await db.from("designs").update({ image_url: "" })
          .eq("design_no", dn).select("design_no,image_url").single();
        if (error) throw error;
        return jsonResponse(request, { ok: true, data });
      }
      const url = clean(body.imageUrl);
      if (!url) throw new Error("No image to set — to remove a photo, use Remove");
      const { data, error } = await db.from("designs").update({ image_url: url })
        .eq("design_no", dn).select("design_no,image_url").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "saveProductRows") {
      // Bulk product grid — ADD-only, mirrors createProduct per row (never
      // upsert_product_rows, which blanks columns; never an update, which would let a
      // bulk paste silently overwrite an existing design). An existing design_no is
      // refused. Per-row try/catch so one bad row is marked and retryable while the
      // rest commit.
      if (!Array.isArray(body.rows) || body.rows.length < 1 || body.rows.length > 200) {
        throw new Error("Provide 1 to 200 product rows");
      }
      const results: Array<Record<string, unknown>> = [];
      for (const raw of body.rows) {
        const row = raw as Record<string, unknown>;
        const dn = clean(row.designNo);
        try {
          if (!dn) throw new Error("Design number is required");
          const firm = clean(row.firm);
          if (!["Maitri", "Niharika", "Both"].includes(firm)) throw new Error("Firm must be Maitri, Niharika or Both");
          const pcsPerSet = Math.round(Number(row.pcsPerSet));
          if (!Number.isFinite(pcsPerSet) || pcsPerSet < 1 || pcsPerSet > 9999) throw new Error("Pcs per set must be between 1 and 9999");
          const { data: existing, error: exErr } = await db.from("designs").select("design_no").eq("design_no", dn).maybeSingle();
          if (exErr) throw exErr;
          // ADD-only: refuse an existing design rather than silently overwriting it
          // (parity with createProduct). Editing an existing design is done in Product
          // Master; a bulk grid that quietly overwrote firm/category/fabric was the bug.
          if (existing) throw new Error(`${dn} already exists — edit it in Product Master instead of re-adding`);
          const { error } = await db.from("designs").insert({
            design_no: dn,
            firm,
            category: clean(row.category),
            style: clean(row.style),
            fabric: clean(row.fabric),
            description: clean(row.description),
            pcs_per_set: pcsPerSet,
            image_url: clean(row.imageUrl),
            active: row.active === undefined ? true : Boolean(row.active),
          }).select("design_no").single();
          if (error) throw error;
          results.push({ ok: true, designNo: dn, action: "created" });
        } catch (error) {
          results.push({ ok: false, designNo: dn, error: errorMessage(error) });
        }
      }
      return jsonResponse(request, { ok: true, data: { results } });
    }

    if (action === "signImageUpload") {
      // Short-lived signature for a direct browser->ImageKit upload. The private
      // key never leaves this function; the browser only receives the signature.
      const priv = Deno.env.get("IMAGEKIT_PRIVATE_KEY") ?? "";
      const pub = Deno.env.get("IMAGEKIT_PUBLIC_KEY") ?? "";
      const endpoint = Deno.env.get("IMAGEKIT_URL_ENDPOINT") ?? "";
      if (!priv || !pub || !endpoint) throw new Error("Image uploads are not configured on the server");
      const token = crypto.randomUUID();
      const expire = Math.floor(Date.now() / 1000) + 240;
      const signature = await hmacSha1Hex(priv, token + expire);
      return jsonResponse(request, {
        ok: true,
        data: { token, expire, signature, publicKey: pub, urlEndpoint: endpoint, folder: imagekitFolder(clean(body.designNo)) },
      });
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
      const ex = await resolveExhibition(db, body);
      const [{ data: slots, error: sErr }, { data: booked, error: bErr }] = await Promise.all([
        db.from("slots").select("id,starts_at,ends_at,label,capacity,active").eq("exhibition_id", ex.id).order("starts_at", { ascending: true }),
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
        : await db.from("slots").insert({ ...row, exhibition_id: (await resolveExhibition(db, body)).id }).select("id").single();
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

    if (action === "setSlotActive") {
      const id = clean(body.id);
      const active = Boolean(body.active);
      const { data, error } = await db.from("slots").update({ active }).eq("id", id)
        .select("id,active").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "listBookings") {
      const ex = await resolveExhibition(db, body);
      const { data, error } = await db
        .from("bookings")
        .select("id,party_size,note,status,created_at,slots!inner(starts_at,ends_at,label,exhibition_id),customers(company_name,contact_name,phone_e164,checked_in_at)")
        .eq("status", "Booked")
        .eq("slots.exhibition_id", ex.id)
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

    if (action === "setCustomerBooking") {
      const customerId = clean(body.customerId);
      const slotId = clean(body.slotId);
      const partySize = Math.max(1, Math.min(99, Math.round(Number(body.partySize) || 1)));
      const note = clean(body.note);
      if (!customerId) throw new Error("Customer is required");
      if (!slotId) {
        const { error } = await db.from("bookings").update({ status: "Cancelled" })
          .eq("customer_id", customerId).eq("status", "Booked");
        if (error) throw error;
        return jsonResponse(request, { ok: true, data: { cancelled: true } });
      }
      const { data: slot, error: slotError } = await db.from("slots")
        .select("id,capacity,active").eq("id", slotId).maybeSingle();
      if (slotError) throw slotError;
      if (!slot || slot.active === false) throw new Error("Selected slot is not available");
      if (slot.capacity != null) {
        const { count, error: countError } = await db.from("bookings")
          .select("id", { count: "exact", head: true })
          .eq("slot_id", slotId).eq("status", "Booked").neq("customer_id", customerId);
        if (countError) throw countError;
        if ((count ?? 0) >= Number(slot.capacity)) throw new Error("This visit slot is full");
      }
      const { data, error } = await db.from("bookings").upsert({
        customer_id: customerId,
        slot_id: slotId,
        party_size: partySize,
        note,
        status: "Booked",
      }, { onConflict: "customer_id" }).select("id,status,slot_id,party_size,note").single();
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


    // ---- Exhibitions --------------------------------------------------
    if (action === "listExhibitions") {
      const { data, error } = await db.rpc("admin_list_exhibitions");
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: data ?? [] });
    }

    if (action === "createExhibition") {
      const name = clean(body.name);
      const slug = clean(body.slug).toLowerCase();
      const startDate = clean(body.startDate);
      const endDate = clean(body.endDate);
      const editWindowHours = Math.max(1, Math.min(240, Math.round(Number(body.editWindowHours) || 24)));
      if (name.length < 2) throw new Error("Exhibition name is required");
      if (!/^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$/.test(slug)) throw new Error("Slug must be lowercase letters, numbers and dashes (used in the login link)");
      if (!startDate || !endDate) throw new Error("Start and end dates are required");

      // Guard: refuse a SECOND exhibition unless the prerequisites are actually
      // deployed. Both checks fail closed, and the two failures are distinct.
      const { count: existing, error: cErr } = await db.from("exhibitions").select("id", { count: "exact", head: true });
      if (cErr) throw cErr;
      if ((existing ?? 0) >= 1) {
        // (a) Is the deployed customer-auth slug-aware? Ask the live function.
        let authContract = 0;
        try {
          const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/customer-auth`, {
            method: "POST",
            headers: { "Content-Type": "application/json", apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "" },
            body: JSON.stringify({ action: "getExhibition", slug: "" }),
          });
          const out = await res.json().catch(() => ({}));
          authContract = Number(out?.data?.authContract ?? 0);
        } catch (_e) {
          throw new Error("Could not reach customer-auth to verify it passes exhibition slugs. Try again — do not create a second exhibition until this check succeeds.");
        }
        if (authContract < 2) {
          throw new Error("The deployed customer-auth is out of date and does not pass exhibition slugs. Deploy the current customer-auth before creating a second exhibition.");
        }
        // The barcode functions are no longer exhibition-scoped (mappings are
        // global). Only the customer-auth slug contract still gates a 2nd event.
      }

      const { data, error } = await db.from("exhibitions").insert({
        name,
        slug,
        start_date: startDate,
        end_date: endDate,
        edit_window_hours: editWindowHours,
        customer_email_domain: "accounts.maitricarnival.app",
        registration_enabled: body.registrationEnabled === undefined ? true : Boolean(body.registrationEnabled),
        is_current: false,
      }).select("id,slug,name,start_date,end_date,edit_window_hours,registration_enabled,is_current").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data }, 201);
    }

    if (action === "updateExhibition") {
      const id = clean(body.id);
      if (!id) throw new Error("Exhibition id is required");
      const patch: Record<string, unknown> = {};
      if (body.startDate !== undefined) patch.start_date = clean(body.startDate);
      if (body.endDate !== undefined) patch.end_date = clean(body.endDate);
      if (body.registrationEnabled !== undefined) patch.registration_enabled = Boolean(body.registrationEnabled);
      if (body.editWindowHours !== undefined) patch.edit_window_hours = Math.max(1, Math.min(240, Math.round(Number(body.editWindowHours) || 24)));
      // slug is deliberately not updatable — it is baked into login emails and
      // the slug-lock trigger blocks changing it once customers exist.
      const { data, error } = await db.from("exhibitions").update(patch).eq("id", id)
        .select("id,slug,name,start_date,end_date,edit_window_hours,registration_enabled,is_current").single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "setCurrentExhibition") {
      const id = clean(body.id);
      if (!id) throw new Error("Exhibition id is required");
      const { data, error } = await db.rpc("admin_set_current_exhibition", { p_exhibition_id: id });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
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
      const ex = await resolveExhibition(db, body);
      const { data: created, error } = await db.auth.admin.createUser({
        // Slug email so the same phone can register across exhibitions; the
        // trigger stamps the SELECTED exhibition from exhibition_slug metadata.
        email: `c${phone}.${ex.slug}@${CUSTOMER_DOMAIN}`,
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
          exhibition_slug: ex.slug,
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
      if (staffName.length < 2) throw new Error("Team member name is required");
      const preset = clean(body.preset) || "custom";
      const permissions = body.groups && typeof body.groups === "object" && !Array.isArray(body.groups)
        ? expandGroups(body.groups)
        : normalizePermissions(body.permissions, preset);
      // crm.bulk is a sub-toggle inside the CRM module, NOT part of GROUPS.crm — so
      // ticking the CRM checkbox never auto-grants it (that would hand bulk to every
      // salesperson at the first edit). It rides in on its own boolean, applied
      // before the coherence guard drops any bulk-without-view.
      if (typeof body.crmBulk === "boolean") permissions["crm.bulk"] = body.crmBulk;
      enforcePermissionCoherence(permissions);
      const allowedSections = ["reception","dashboard","sale","products","dispatch","crm","admin"];
      const defaultSection = allowedSections.includes(clean(body.defaultSection)) ? clean(body.defaultSection) : "sale";
      const modulePermission: Record<string,string> = { reception:"reception.view", dashboard:"dashboard.view", sale:"sale.view", products:"products.view", dispatch:"dispatch.view", crm:"crm.view", admin:"admin.slots" };
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
      if (!userId) throw new Error("TEAM_USER_NOT_CREATED");
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
      return jsonResponse(request, { ok: true, data: { id: userId, staffId, staffName, email, password, preset, permissions, groups: collapseGroups(permissions), defaultSection } });
    }

    if (action === "listStaff") {
      const { data, error } = await db.from("staff_profiles")
        .select("auth_user_id,staff_id,staff_name,preset,permissions,default_section,active,created_at,updated_at")
        .order("staff_name", { ascending: true });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: (data ?? []).map((row: any) => ({
        authUserId: row.auth_user_id, staffId: row.staff_id, staffName: row.staff_name,
        preset: row.preset,
        permissions: normalizePermissions(row.permissions,row.preset),
        groups: collapseGroups(normalizePermissions(row.permissions,row.preset)),
        defaultSection: row.default_section, active: row.active, createdAt: row.created_at, updatedAt: row.updated_at,
      })) });
    }

    if (action === "updateStaff") {
      const authUserId = clean(body.authUserId);
      const preset = clean(body.preset) || "custom";
      const permissions = body.groups && typeof body.groups === "object" && !Array.isArray(body.groups)
        ? expandGroups(body.groups)
        : normalizePermissions(body.permissions,preset);
      // crm.bulk sub-toggle (see createStaff) — carried on its own boolean so the
      // CRM module checkbox never grants it, and preserved across edits because the
      // editor sends the current state back.
      if (typeof body.crmBulk === "boolean") permissions["crm.bulk"] = body.crmBulk;
      enforcePermissionCoherence(permissions);
      const defaultSection = ["reception","dashboard","sale","products","dispatch","crm","admin"].includes(clean(body.defaultSection)) ? clean(body.defaultSection) : "sale";
      const row: Record<string,unknown> = { preset, permissions, default_section: defaultSection };
      if (body.staffName !== undefined) row.staff_name = clean(body.staffName);
      if (body.active !== undefined) row.active = Boolean(body.active);
      const { data, error } = await db.from("staff_profiles").update(row).eq("auth_user_id",authUserId)
        .select("auth_user_id,staff_id,staff_name,preset,permissions,default_section,active").single();
      if (error) throw error;
      return jsonResponse(request,{ok:true,data:{
        authUserId: data.auth_user_id,
        staffId: data.staff_id,
        staffName: data.staff_name,
        preset: data.preset,
        permissions: normalizePermissions(data.permissions,data.preset),
        groups: collapseGroups(normalizePermissions(data.permissions,data.preset)),
        defaultSection: data.default_section,
        active: data.active,
      }});
    }

    if (action === "resetStaffPassword") {
      const authUserId = clean(body.authUserId);
      const password = clean(body.password) || generatePassword();
      if (password.length < 8) throw new Error("Password must be at least 8 characters");
      const { error } = await db.auth.admin.updateUserById(authUserId,{password});
      if (error) throw error;
      return jsonResponse(request,{ok:true,data:{password}});
    }

    if (action === "deleteStaff") {
      const authUserId = clean(body.authUserId);
      if (!authUserId) throw new Error("Team member is required");
      if (authUserId === admin.id) throw new Error("You cannot remove your own account");
      const { error } = await db.auth.admin.deleteUser(authUserId);
      if (error) throw error;
      return jsonResponse(request, { ok: true, data: { deleted: true } });
    }

    if (action === "assistedSaveOrder") {
      const items = Array.isArray(body.items) ? body.items : [];
      const { data, error } = await db.rpc("admin_save_order_with_actor", {
        p_customer_id: clean(body.customerId),
        p_firm: clean(body.firm),
        p_items: items,
        // Multi-customer batch passes a stable per-(customer,firm) id so a retry
        // of the batch is idempotent; single-customer save omits it and gets a
        // fresh one. _write_order dedupes on this.
        p_request_id: clean(body.requestId) || crypto.randomUUID(),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "recentOrders") {
      const q = clean(body.query);
      const ex = await resolveExhibition(db, body);
      let query = db.from("orders")
        .select("id,customer_id,firm,status,total_designs,total_sets,total_pieces,updated_at,customers(company_name,contact_name,phone_e164,city,state,agent)")
        .eq("exhibition_id", ex.id)
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

    // ── Dispatch ───────────────────────────────────────────────────────────
    // The queue. Draft orders with nothing in them are excluded: there is
    // nothing to pack.
    if (action === "listDispatch") {
      const q = clean(body.query);
      const firm = clean(body.firm);
      const statusFilter = clean(body.dispatchStatus);
      const ex = await resolveExhibition(db, body);

      // Ordering is tier-first (A→B→C→unranked) with updated_at desc as the
      // tiebreak, done in SQL BEFORE the row cap. There are 486 dispatchable
      // orders against a 300 cap, so a post-limit sort would silently drop A-tier
      // orders that fall past row 300 — and a PostgREST query can neither express
      // the tier rank nor order the parent by the nested customer_crm. Hence the
      // admin_dispatch_orders RPC. The search now joins in SQL (no separate
      // <=300-row customer id lookup, so it is no longer capped).
      const off = Math.max(0, Number(body.offset) || 0);
      const { data, error } = await db.rpc("admin_dispatch_orders", {
        p_filters: {
          exhibitionId: ex.id,
          firm: (firm === "Maitri" || firm === "Niharika") ? firm : null,
          dispatchStatus: ["Pending", "Partial", "Completed"].includes(statusFilter) ? statusFilter : null,
          search: q || null,
          limit: 300,
          offset: off,
        },
      });
      if (error) throw error;
      // SHAPE-TOLERANT (deliberate): admin_dispatch_orders may return the older bare
      // ARRAY of snake_case rows, or the newer OBJECT { orders:[camelCase], total }
      // that adds pagination + a true total. Read either, camelCase-first with a
      // snake_case fallback, so an Edge/migration deploy in either order degrades to a
      // working list instead of breaking dispatch.
      const paged = data && typeof data === "object" && !Array.isArray(data) && Array.isArray((data as any).orders);
      const rawRows: any[] = paged ? (data as any).orders : (((data as any[]) ?? []));
      const total: number | null = paged ? (Number((data as any).total) || rawRows.length) : null;
      const orders = rawRows.map((o: any) => ({
        orderId: o.orderId ?? o.id,
        customerId: o.customerId ?? o.customer_id,
        firm: o.firm,
        status: o.status,
        dispatchStatus: o.dispatchStatus ?? o.dispatch_status ?? "Pending",
        designs: Number(o.designs ?? o.total_designs) || 0,
        sets: Number(o.sets ?? o.total_sets) || 0,
        pieces: Number(o.pieces ?? o.total_pieces) || 0,
        updatedAt: o.updatedAt ?? o.updated_at,
        companyName: o.companyName ?? o.company_name ?? "",
        contactName: o.contactName ?? o.contact_name ?? "",
        phone: o.phone ?? o.phone_e164 ?? "",
        city: o.city ?? "",
        state: o.state ?? "",
        agent: o.agent ?? "",
        tier: o.tier ?? null,
      }));
      // By-order view: a bare array when total is unknown (old RPC) so the current
      // client is unaffected; { orders, total } once the RPC provides a total, so the
      // client can page past the 300 cap with Load more. The client reads both.
      if (!body.withLines) return jsonResponse(request, { ok: true, data: total === null ? orders : { orders, total } });
      // By-product pick-list: also return every design line for these orders so the
      // client can roll up "remaining to ship" per design. No images — quantities only.
      const orderIds = orders.map((o) => o.orderId);
      let lines: Array<Record<string, unknown>> = [];
      if (orderIds.length) {
        const [{ data: items, error: iErr }, { data: dls, error: dErr }] = await Promise.all([
          db.from("order_items").select("order_id,design_no,qty,pcs_per_set_snapshot").in("order_id", orderIds),
          db.from("dispatch_lines").select("order_id,design_no,dispatched_sets,dispatched_at").in("order_id", orderIds),
        ]);
        if (iErr) throw iErr;
        if (dErr) throw dErr;
        const k = (oid: string, dn: string) => oid + " " + dn;
        // Keep the per-line dispatch timestamp alongside the set count. The removal
        // confirmation must name the date THIS line was actually shipped — not the
        // order's updated_at, which recompute_dispatch_status()/_write_order bump on
        // every later dispatch or edit and would show a plausible-but-wrong date.
        const dispatched = new Map<string, { sets: number; at: string | null }>();
        (dls ?? []).forEach((d: any) => dispatched.set(k(d.order_id, d.design_no), { sets: Number(d.dispatched_sets) || 0, at: d.dispatched_at ?? null }));
        lines = (items ?? []).map((it: any) => {
          const dl = dispatched.get(k(it.order_id, it.design_no));
          return {
            orderId: it.order_id,
            designNo: it.design_no,
            orderedSets: Number(it.qty) || 0,
            dispatchedSets: dl?.sets || 0,
            dispatchedAt: dl?.at ?? null,
            pcsPerSet: Number(it.pcs_per_set_snapshot) || 0,
          };
        });
      }
      return jsonResponse(request, { ok: true, data: { orders, lines, total: total ?? orders.length } });
    }

    // Full-resolution images here by design: dispatch staff must be able to
    // open an image and identify the physical product.
    if (action === "getDispatch") {
      const orderId = clean(body.orderId);
      if (!orderId) throw new Error("ORDER_ID_REQUIRED");
      const { data, error } = await db.rpc("admin_dispatch_detail", {
        p_order_id: orderId,
      });
      if (error) throw error;
      if (!data) throw new Error("ORDER_NOT_FOUND");
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "saveDispatch") {
      const orderId = clean(body.orderId);
      if (!orderId) throw new Error("ORDER_ID_REQUIRED");
      const lines = Array.isArray(body.lines) ? body.lines : [];
      const { data, error } = await db.rpc("admin_save_dispatch", {
        p_order_id: orderId,
        p_lines: lines,
        p_note: clean(body.note),
        p_actor_id: admin.id,
      });
      if (error) throw error;
      const { data: detail, error: dErr } = await db.rpc("admin_dispatch_detail", {
        p_order_id: orderId,
      });
      if (dErr) throw dErr;
      return jsonResponse(request, { ok: true, data: { result: data, detail } });
    }

    // ── CRM ────────────────────────────────────────────────────────────────
    // Every action is in ACTION_PERMISSIONS above; the gate runs before we get
    // here. Writes pass admin.id as the actor so customer_crm_log/calls attribute
    // correctly. Assignable staff = anyone who can see CRM (crm.view holders) —
    // returned here so the assign picker works without admin.staff.
    if (action === "crmListCustomers") {
      const filters = body.filters && typeof body.filters === "object" && !Array.isArray(body.filters) ? body.filters : {};
      const { data, error } = await db.rpc("crm_list_customers", { p_filters: filters });
      if (error) throw error;
      // SHAPE-TOLERANT (deliberate): crm_list_customers may return either the older
      // ARRAY of customers, or the newer OBJECT { customers, assigneeCounts,
      // unassignedCount, totalCount } that backs the salesperson-picker counts.
      // Handling both means an Edge/migration deploy in either order degrades to a
      // working list instead of breaking the CRM (an object handed to the old array
      // client is exactly the outage this guards against). Count fields are forwarded
      // ONLY when present, so the client shows plain names until counts are live.
      const isObj = data && typeof data === "object" && !Array.isArray(data);
      const customers = isObj ? ((data as any).customers ?? []) : (data ?? []);
      const { data: staffRows, error: sErr } = await db
        .from("staff_profiles")
        .select("auth_user_id,staff_name,permissions,active")
        .order("staff_name", { ascending: true });
      if (sErr) throw sErr;
      // ALL active staff, not only crm.view holders — a buyer can be assigned to a
      // salesperson before their CRM access is granted. hasCrm marks who can act on
      // it now; the client shows a "no CRM access" note but never hides or blocks them.
      const staff = (staffRows ?? [])
        .filter((r: any) => r.active !== false)
        .map((r: any) => ({ id: r.auth_user_id, name: r.staff_name, hasCrm: !!(r.permissions && r.permissions["crm.view"]) }));
      const out: Record<string, unknown> = { customers, staff };
      if (isObj) {
        out.assigneeCounts = (data as any).assigneeCounts ?? [];
        out.unassignedCount = (data as any).unassignedCount ?? 0;
        out.totalCount = (data as any).totalCount ?? 0;
      }
      return jsonResponse(request, { ok: true, data: out });
    }

    if (action === "crmCustomerDetail") {
      const customerId = clean(body.customerId);
      if (!customerId) throw new Error("CUSTOMER_ID_REQUIRED");
      const { data, error } = await db.rpc("crm_customer_detail", { p_customer_id: customerId });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmSetBuyerType") {
      const { data, error } = await db.rpc("crm_set_buyer_type", {
        p_customer_id: clean(body.customerId),
        p_buyer_type: clean(body.buyerType) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmSetTier") {
      const { data, error } = await db.rpc("crm_set_tier", {
        p_customer_id: clean(body.customerId),
        p_tier: clean(body.tier) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmBulkSetTier") {
      const ids = Array.isArray(body.customerIds) ? body.customerIds.map((x: unknown) => clean(x)).filter(Boolean) : [];
      if (!ids.length) throw new Error("NO_CUSTOMERS");
      const { data, error } = await db.rpc("crm_bulk_set_tier", {
        p_customer_ids: ids,
        p_tier: clean(body.tier) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmSetStatus") {
      const { data, error } = await db.rpc("crm_set_status", {
        p_customer_id: clean(body.customerId),
        p_status: clean(body.status),
        p_reason: clean(body.reason) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmSetReferenceFlag") {
      const { data, error } = await db.rpc("crm_set_reference_flag", {
        p_customer_id: clean(body.customerId),
        p_has_reference: Boolean(body.hasReference),
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmSetToken") {
      const rawAmount = body.tokenAmount;
      const tokenAmount = rawAmount === "" || rawAmount === null || rawAmount === undefined ? null : Number(rawAmount);
      if (tokenAmount !== null && !Number.isFinite(tokenAmount)) throw new Error("INVALID_TOKEN_AMOUNT");
      const { data, error } = await db.rpc("crm_set_token", {
        p_customer_id: clean(body.customerId),
        p_token_agreed: Boolean(body.tokenAgreed),
        p_token_amount: tokenAmount,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmAssign") {
      const { data, error } = await db.rpc("crm_assign", {
        p_customer_id: clean(body.customerId),
        p_assigned_to: clean(body.assignedTo) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmBulkAssign") {
      const ids = Array.isArray(body.customerIds) ? body.customerIds.map((x: unknown) => clean(x)).filter(Boolean) : [];
      if (!ids.length) throw new Error("NO_CUSTOMERS");
      const { data, error } = await db.rpc("crm_bulk_assign", {
        p_customer_ids: ids,
        p_assigned_to: clean(body.assignedTo) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmBulkSetBuyerType") {
      const ids = Array.isArray(body.customerIds) ? body.customerIds.map((x: unknown) => clean(x)).filter(Boolean) : [];
      if (!ids.length) throw new Error("NO_CUSTOMERS");
      const { data, error } = await db.rpc("crm_bulk_set_buyer_type", {
        p_customer_ids: ids,
        p_buyer_type: clean(body.buyerType) || null,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmLogCall") {
      const followupAt = clean(body.followupAt) || null;
      const { data, error } = await db.rpc("crm_log_call", {
        p_customer_id: clean(body.customerId),
        p_outcome: clean(body.outcome),
        p_notes: clean(body.notes),
        p_status_after: clean(body.statusAfter) || null,
        p_followup_at: followupAt,
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmAddReference") {
      const { data, error } = await db.rpc("crm_add_reference", {
        p_customer_id: clean(body.customerId),
        p_reference_text: clean(body.referenceText),
        p_actor: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "crmDeleteReference") {
      const { data, error } = await db.rpc("crm_delete_reference", {
        p_reference_id: clean(body.referenceId),
        p_actor: admin.id,
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
    const raw = errorMessage(error);
    let message = raw;
    let status = /PERMISSION_DENIED|STAFF_ACCESS_REQUIRED|TEAM_ACCOUNT_DISABLED|TEAM_PROFILE_NOT_FOUND|ADMIN_REQUIRED/.test(raw)
      ? 403
      : raw.includes("SESSION") || raw === "AUTH_REQUIRED" ? 401 : 500;
    // Friendly text for the exhibition-scoping codes (BARCODE_ALREADY_MAPPED is
    // left raw — the mapping UI parses its pipe-delimited payload).
    if (raw.includes("EXHIBITION_ID_REQUIRED")) { message = "Select an exhibition before mapping or deactivating a barcode."; status = 400; }
    else if (raw.includes("UNKNOWN_EXHIBITION")) { message = "That exhibition no longer exists — reload and try again."; status = 400; }
    else if (raw.includes("EXHIBITION_SLUG_LOCKED")) { message = "This exhibition's link is locked because it already has customers."; status = 400; }
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
