import "server-only";

import { cookies } from "next/headers";

import { createServerClient } from "@supabase/ssr";

import { requireSupabaseEnv } from "./env";

/**
 * Cliente de Supabase para Server Components, Route Handlers y Server Actions.
 * Las consultas llevan el JWT del usuario (o ninguno), así que RLS siempre aplica.
 */
export async function createClient() {
  // Leer cookies primero marca la ruta como dinámica (nunca prerenderizada).
  const cookieStore = await cookies();
  const { url, anonKey } = requireSupabaseEnv();

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Los Server Components no pueden escribir cookies; el proxy refresca la sesión.
        }
      },
    },
  });
}

/** Usuario actual validado contra Supabase Auth (no solo leyendo la cookie). */
export async function getUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
}
