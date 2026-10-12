import { createClient } from "jsr:@supabase/supabase-js@2";

export function createSupabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  }
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

let _supabase: any = null;

export function getSupabase(): any {
  if (!_supabase) {
    _supabase = createSupabaseAdmin();
  }
  return _supabase;
}

export const supabase = new Proxy({} as any, {
  get(_target, prop) {
    return getSupabase()[prop as string];
  },
});
