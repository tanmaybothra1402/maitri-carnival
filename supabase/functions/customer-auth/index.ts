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

// Hidden email is scoped by the exhibition slug so the same phone can hold a
// separate account per exhibition: c<phone>.<slug>@domain.
function hiddenEmail(phone: string, slug: string): string {
  return `c${phone}.${slug}@${CUSTOMER_DOMAIN}`;
}

// Pre-slug accounts (the original Carnival customers) used c<phone>@domain. Used
// only as a login fallback on the current exhibition — see LOGIN below.
function legacyEmail(phone: string): string {
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

type ExhibitionRow = {
  id: string;
  slug: string;
  name: string;
  start_date: string;
  end_date: string;
  registration_enabled: boolean;
  is_current: boolean;
};

// Resolve the exhibition from the URL slug. An unknown or empty slug falls back
// to is_current (the bare-URL rule from blueprint §5).
async function resolveExhibition(slugRaw: unknown): Promise<ExhibitionRow> {
  const slug = clean(slugRaw).toLowerCase();
  const admin = serviceClient();
  const cols = "id,slug,name,start_date,end_date,registration_enabled,is_current";

  if (slug) {
    const { data } = await admin.from("exhibitions").select(cols).eq("slug", slug).maybeSingle();
    if (data) return data as ExhibitionRow;
  }
  const { data: current } = await admin.from("exhibitions").select(cols).eq("is_current", true).maybeSingle();
  if (current) return current as ExhibitionRow;
  throw new Error("NO_EXHIBITION");
}

function isEnded(ex: ExhibitionRow): boolean {
  const today = new Date().toISOString().slice(0, 10);
  return !ex.registration_enabled && String(ex.end_date) < today;
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
    return { message: "Registration for this exhibition is closed.", status: 403 };
  }
  if (raw.includes("INVALID_EXHIBITION_ACCESS_CODE")) {
    return { message: "The exhibition access code is incorrect.", status: 403 };
  }
  if (raw.includes("EXHIBITION_SLUG_REQUIRED") || raw.includes("UNKNOWN_EXHIBITION_SLUG") || raw.includes("NO_EXHIBITION")) {
    return { message: "This exhibition link is not valid. Please use the link for your event.", status: 400 };
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

async function signInWithUser(
  email: string,
  password: string,
): Promise<{ session: AuthSessionPayload; userId: string }> {
  const client = authClient();
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return { session: sessionPayload(data.session), userId: String(data.user?.id ?? "") };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") {
    return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);
  }

  try {
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action).toLowerCase();

    // Pre-login: resolve the exhibition named by ?e= so the app can show its
    // name/dates and the "has ended" state. No phone/password required.
    if (action === "getexhibition") {
      const ex = await resolveExhibition(body.slug);
      return jsonResponse(request, {
        ok: true,
        data: {
          slug: ex.slug,
          name: ex.name,
          startDate: ex.start_date,
          endDate: ex.end_date,
          registrationEnabled: ex.registration_enabled,
          ended: isEnded(ex),
        },
      });
    }

    const phone = normalizePhone(body.phone);
    const password = validatePassword(body.password);
    const exhibition = await resolveExhibition(body.slug);
    const email = hiddenEmail(phone, exhibition.slug);

    if (action === "login") {
      try {
        const session = await signIn(email, password);
        return jsonResponse(request, { ok: true, data: { session } });
      } catch (loginError) {
        // Pre-slug accounts (original Carnival customers) use c<phone>@domain.
        // Fall back to that email, but honour it ONLY if the account actually
        // belongs to the resolved exhibition. Gating on the account (not
        // is_current) keeps existing Carnival accounts working on the Carnival
        // link while making the fallback inert on every other exhibition's link
        // — otherwise a Carnival account would resolve on the Surat link and the
        // customer would see Carnival data (and write orders into Carnival).
        const lower = errorMessage(loginError).toLowerCase();
        const badCreds = lower.includes("invalid login credentials") || lower.includes("invalid_credentials");
        if (!badCreds) throw loginError;

        const legacy = await signInWithUser(legacyEmail(phone), password);
        const admin = serviceClient();
        const { data: cust } = await admin
          .from("customers")
          .select("exhibition_id")
          .eq("id", legacy.userId)
          .maybeSingle();
        if (!cust || cust.exhibition_id !== exhibition.id) {
          // Right password, wrong exhibition — reject as if no account existed.
          throw new Error("Invalid login credentials");
        }
        return jsonResponse(request, { ok: true, data: { session: legacy.session } });
      }
    }

    if (action === "register") {
      if (!exhibition.registration_enabled) throw new Error("REGISTRATION_CLOSED");

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
          exhibition_slug: exhibition.slug,
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
