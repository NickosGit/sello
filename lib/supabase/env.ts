/**
 * Variables públicas de Supabase, validadas en un solo lugar.
 *
 * Solo la anon key llega al navegador. Es pública a propósito: quien separa los
 * datos de cada usuario es Row Level Security en Postgres. La app nunca usa la
 * service-role key.
 */

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const hasSupabaseEnv = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

/** Devuelve las credenciales o lanza. Llamar justo antes de crear un cliente. */
export function requireSupabaseEnv() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error(
      "Faltan NEXT_PUBLIC_SUPABASE_URL y/o NEXT_PUBLIC_SUPABASE_ANON_KEY. " +
        "Copia .env.example a .env.local (local) o añádelas en Vercel -> Settings -> Environment Variables.",
    );
  }
  return { url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY };
}
