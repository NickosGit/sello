"use server";

import { revalidatePath } from "next/cache";

import { GENERIC_ERROR } from "@/lib/errors";
import { approveInputSchema } from "@/lib/schemas";
import { getUser } from "@/lib/supabase/server";

export type ActionResult = { ok: true } | { ok: false; error: string };

/**
 * The worker approves the (edited) draft. Claims are inserted WITHOUT a status:
 * the DB trigger forces DECLARED and logs one event per claim.
 */
export async function approveDraft(input: unknown): Promise<ActionResult> {
  const { supabase, user } = await getUser();
  if (!user) return { ok: false, error: "Tu sesión terminó. Vuelve a entrar." };

  const parsed = approveInputSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: "Cada frase necesita de 3 a 400 caracteres, y los detalles máximo 800." };
  }
  const { proof_id, claims } = parsed.data;

  const { data: proof } = await supabase.from("proofs").select("id, owner_id").eq("id", proof_id).maybeSingle();
  if (!proof || proof.owner_id !== user.id) return { ok: false, error: "No encontramos esa prueba." };

  const { count } = await supabase
    .from("claims")
    .select("id", { count: "exact", head: true })
    .eq("proof_id", proof_id);
  if ((count ?? 0) > 0) return { ok: false, error: "Esta prueba ya tiene frases guardadas." };

  const { error } = await supabase.from("claims").insert(claims.map((c) => ({ ...c, proof_id })));
  if (error) {
    console.error("[approveDraft] insert failed:", error.code);
    return { ok: false, error: GENERIC_ERROR };
  }

  revalidatePath(`/app/proofs/${proof_id}`);
  return { ok: true };
}
