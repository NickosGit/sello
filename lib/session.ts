import "server-only";

import { redirect } from "next/navigation";
import { connection } from "next/server";

import { hasSupabaseEnv } from "@/lib/supabase/env";
import { getUser } from "@/lib/supabase/server";

export type Profile = {
  id: string;
  display_name: string | null;
  is_reviewer: boolean;
  reviewer_approved: boolean;
};

/**
 * Segunda barrera después del proxy: sin usuario válido, al login.
 * El perfil lo crea un trigger en `auth.users`; si aún no existe la tabla
 * (antes de correr la migración) se devuelve `profile: null` en vez de romper.
 */
export async function requireUser(next = "/app") {
  // Siempre por petición: nunca prerenderizar una pantalla con datos de alguien.
  await connection();
  if (!hasSupabaseEnv) redirect("/login");
  const { supabase, user } = await getUser();
  if (!user) redirect("/login?next=" + encodeURIComponent(next));

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, display_name, is_reviewer, reviewer_approved")
    .eq("id", user.id)
    .maybeSingle<Profile>();

  const name =
    profile?.display_name ||
    (user.user_metadata?.full_name as string | undefined) ||
    user.email ||
    "Tú";

  return { supabase, user, profile: profile ?? null, name };
}
