import type { User } from "npm:@supabase/supabase-js@2";
import { serviceClient } from "./supabase.ts";

export function bearerToken(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Error("AUTH_REQUIRED");
  return match[1].trim();
}

export async function requireUser(request: Request): Promise<User> {
  const token = bearerToken(request);
  const client = serviceClient();
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("INVALID_OR_EXPIRED_SESSION");
  return data.user;
}

export async function requireAdmin(request: Request): Promise<User> {
  const user = await requireUser(request);
  if (String(user.app_metadata?.role ?? "") !== "admin") {
    throw new Error("ADMIN_REQUIRED");
  }
  return user;
}
