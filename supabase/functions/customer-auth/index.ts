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
