import { createBrowserClient } from "@supabase/ssr";

import { requireSupabaseEnv } from "./env";

/** Cliente de Supabase para el navegador (anon key + sesión del usuario). */
export function createClient() {
  const { url, anonKey } = requireSupabaseEnv();
  return createBrowserClient(url, anonKey);
}
