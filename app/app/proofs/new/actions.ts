"use server";

import { redirect } from "next/navigation";

import { GENERIC_ERROR } from "@/lib/errors";
import { proofInputSchema } from "@/lib/schemas";
import { getUser } from "@/lib/supabase/server";

export type NewProofState = { error: string | null; fields?: Record<string, string> };

const FIELD_ERRORS: Record<string, string> = {
  title: "El título debe tener de 3 a 120 caracteres.",
  raw_evidence: "Cuenta lo que hiciste con 20 a 4,000 caracteres.",
  evidence_link: "El enlace debe empezar con http:// o https:// (máximo 500 caracteres).",
  intended_decision_maker: "Máximo 120 caracteres.",
  intended_decision: "Máximo 200 caracteres.",
};

export async function createProof(_prev: NewProofState, formData: FormData): Promise<NewProofState> {
  const { supabase, user } = await getUser();
  if (!user) return { error: "Tu sesión terminó. Vuelve a entrar." };

  const raw = {
    title: String(formData.get("title") ?? ""),
    raw_evidence: String(formData.get("raw_evidence") ?? ""),
    evidence_link: String(formData.get("evidence_link") ?? ""),
    intended_decision_maker: String(formData.get("intended_decision_maker") ?? ""),
    intended_decision: String(formData.get("intended_decision") ?? ""),
  };

  // Rejected here, before the DB or the prompt ever see it (packet test 12).
  const parsed = proofInputSchema.safeParse(raw);
  if (!parsed.success) {
    const fields: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = String(issue.path[0]);
      fields[key] = FIELD_ERRORS[key] ?? GENERIC_ERROR;
    }
    return { error: "Revisa los campos marcados.", fields };
  }

  const { data, error } = await supabase.from("proofs").insert(parsed.data).select("id").single();
  if (error || !data) {
    console.error("[createProof] insert failed:", error?.code);
    return { error: GENERIC_ERROR };
  }

  redirect(`/app/proofs/${data.id}`);
}
