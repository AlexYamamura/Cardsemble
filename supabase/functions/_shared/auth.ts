import { supabase } from "./supabase.ts";

export function getBearerToken(authorization: string | null): string {
  const parts = (authorization || "").split(" ");
  if (parts.length !== 2 || parts[0]?.toLowerCase() !== "bearer" || !parts[1]) {
    throw new Error("401: Bearer token required");
  }
  return parts[1]!;
}

export async function verifySupabaseUser(token: string): Promise<string> {
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    throw new Error("401: Invalid or expired Supabase session");
  }
  if (!user.id) {
    throw new Error("502: Supabase Auth returned an invalid user");
  }
  return user.id;
}

export async function authenticateRequest(
  authorization: string | null,
): Promise<{ userId: string | null; authSource: string }> {
  const token = getBearerToken(authorization);
  const testToken = Deno.env.get("CARD_EVENTS_API_TOKEN");
  if (testToken && token === testToken) {
    return { userId: null, authSource: "test_api_token" };
  }

  try {
    const userId = await verifySupabaseUser(token);
    return { userId, authSource: "supabase_auth" };
  } catch (error: unknown) {
    if (error instanceof Error && error.message.startsWith("401:")) {
      // fall through to device token check
    } else {
      throw error;
    }
  }

  const hashBuffer = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  const tokenHash = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const { data: rows, error: dbError } = await supabase
    .from("device_tokens")
    .select("user_id")
    .eq("token_hash", tokenHash)
    .is("revoked_at", null)
    .limit(1);

  if (dbError) {
    throw new Error(`502: ${dbError.message}`);
  }

  if (rows && rows.length > 0) {
    return { userId: rows[0]!.user_id as string, authSource: "device_token" };
  }

  throw new Error("401: Invalid, expired, or revoked bearer token");
}

export async function ensureDefaultPerson(userId: string): Promise<{
  person_id: string;
  display_name: string;
}> {
  const { data: existing, error } = await supabase
    .from("household_people")
    .select("*")
    .eq("user_id", userId)
    .eq("is_default", true)
    .limit(1);

  if (error) throw new Error(`502: ${error.message}`);

  if (existing && existing.length > 0) {
    return {
      person_id: existing[0]!.person_id,
      display_name: existing[0]!.display_name,
    };
  }

  const { data: profiles, error: profileError } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .limit(1);

  if (profileError) throw new Error(`502: ${profileError.message}`);

  const displayName =
    profiles && profiles[0]?.display_name
      ? profiles[0]!.display_name
      : "Primary member";

  const { data: inserted, error: insertError } = await supabase
    .from("household_people")
    .insert({
      user_id: userId,
      display_name: displayName,
      is_default: true,
    })
    .select();

  if (insertError || !inserted || inserted.length === 0) {
    throw new Error("503: Could not initialize the household's primary member");
  }

  return {
    person_id: inserted[0]!.person_id,
    display_name: inserted[0]!.display_name,
  };
}

export async function getHouseholdPerson(
  userId: string,
  personId: string,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabase
    .from("household_people")
    .select("*")
    .eq("user_id", userId)
    .eq("person_id", personId)
    .limit(1);

  if (error) throw new Error(`502: ${error.message}`);
  return data && data.length > 0 ? data[0] as Record<string, unknown> : null;
}

let _defaultPersonCache = new Map<string, { person_id: string; display_name: string }>();

export function clearDefaultPersonCache(userId: string): void {
  _defaultPersonCache.delete(userId);
}

export async function getDefaultPerson(
  userId: string,
  useCache = true,
): Promise<{ person_id: string; display_name: string }> {
  if (useCache && _defaultPersonCache.has(userId)) {
    return _defaultPersonCache.get(userId)!;
  }
  const person = await ensureDefaultPerson(userId);
  if (useCache) {
    _defaultPersonCache.set(userId, person);
  }
  return person;
}

export function genericError(message: string): {
  statusCode: number;
  error: string;
} {
  return { statusCode: 502, error: message };
}

export function badRequest(message: string): {
  statusCode: number;
  error: string;
} {
  return { statusCode: 400, error: message };
}

export function notFound(message: string): {
  statusCode: number;
  error: string;
} {
  return { statusCode: 404, error: message };
}

export function forbidden(message: string): {
  statusCode: number;
  error: string;
} {
  return { statusCode: 403, error: message };
}

export class ApiError extends Error {
  constructor(public statusCode: number, message: string) {
    super(message);
    this.name = "ApiError";
  }
}

export async function addHouseholdMember(householdId, userId, role = "member") { const { error } = await supabase.from("household_members").insert({ household_id: householdId, user_id: userId, role }); if (error) throw new Error("502:" + error.message); }
