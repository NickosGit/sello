import { NextResponse } from "next/server";

import { draftClaims } from "@/lib/draft";
import { GENERIC_ERROR } from "@/lib/errors";
import { draftRequestSchema, LIMITS } from "@/lib/schemas";
import { getUser } from "@/lib/supabase/server";

/** Free-tier quota guard: a proof can be re-drafted a few times, not forever. */
const MAX_DRAFTS_PER_PROOF = 5;

/**
 * POST /api/draft { proof_id }
 * Loads the proof AS THE USER (RLS), asks Gemini (or the simulated fallback)
 * to organize it, and stores the result in `ai_drafts` only. This route never
 * writes to `claims`; the worker approves claims separately.
 */
export async function POST(request: Request) {
  const { supabase, user } = await getUser();
  if (!user) return NextResponse.json({ error: "Tu sesión terminó. Vuelve a entrar." }, { status: 401 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: GENERIC_ERROR }, { status: 400 });
  }
  const parsed = draftRequestSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: GENERIC_ERROR }, { status: 400 });

  const { data: proof } = await supabase
    .from("proofs")
    .select("id, owner_id, raw_evidence")
    .eq("id", parsed.data.proof_id)
    .maybeSingle();
  // Reviewers and vouchers can read some proofs; only the owner may draft.
  if (!proof || proof.owner_id !== user.id) {
    return NextResponse.json({ error: "No encontramos esa prueba." }, { status: 404 });
  }

  // The DB already enforces this; re-check so nothing oversized reaches the prompt.
  if (typeof proof.raw_evidence !== "string" || proof.raw_evidence.length > LIMITS.rawEvidence.max) {
    return NextResponse.json({ error: GENERIC_ERROR }, { status: 400 });
  }

  const { count } = await supabase
    .from("ai_drafts")
    .select("id", { count: "exact", head: true })
    .eq("proof_id", proof.id);
  if ((count ?? 0) >= MAX_DRAFTS_PER_PROOF) {
    return NextResponse.json(
      { error: "Ya pediste varios borradores para esta prueba. Edita el último a mano." },
      { status: 429 },
    );
  }

  const draft = await draftClaims(proof.raw_evidence);
  if (draft.fallback_reason) console.info("[draft] simulated:", draft.fallback_reason);

  const { error } = await supabase.from("ai_drafts").insert({
    proof_id: proof.id,
    payload: { claims: draft.claims },
    overclaim_flags: draft.overclaim_flags,
    simulated: draft.simulated,
  });
  if (error) {
    console.error("[draft] insert failed:", error.code);
    return NextResponse.json({ error: GENERIC_ERROR }, { status: 500 });
  }

  return NextResponse.json({ ok: true, simulated: draft.simulated });
}
