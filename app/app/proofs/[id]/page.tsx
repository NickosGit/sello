import Link from "next/link";
import { notFound } from "next/navigation";

import { ClaimCard, type ClaimView, type EventView } from "@/components/ClaimCard";
import { DemoLabel } from "@/components/Labels";
import { requireUser } from "@/lib/session";
import { aiDraftSchema, type OverclaimFlag } from "@/lib/schemas";

import { DraftEditor } from "./DraftEditor";
import { GenerateDraft } from "./GenerateDraft";

export default async function ProofPage({ params }: PageProps<"/app/proofs/[id]">) {
  const { id } = await params;
  const { supabase, user } = await requireUser(`/app/proofs/${id}`);

  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const { data: proof } = await supabase
    .from("proofs")
    .select("id, owner_id, title, raw_evidence, evidence_link, is_demo, created_at")
    .eq("id", id)
    .maybeSingle();
  if (!proof || proof.owner_id !== user.id) notFound();

  const [{ data: claims }, { data: drafts }] = await Promise.all([
    supabase
      .from("claims")
      .select("id, text, status, scope, conditions, ai_assistance, revisions, missing_info, cannot_infer, created_at")
      .eq("proof_id", id)
      .order("created_at"),
    supabase
      .from("ai_drafts")
      .select("id, payload, overclaim_flags, simulated, created_at")
      .eq("proof_id", id)
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  const draft = drafts?.[0];
  const hasClaims = (claims?.length ?? 0) > 0;

  let events: Record<string, EventView[]> = {};
  if (hasClaims) {
    const { data: ev } = await supabase
      .from("status_events")
      .select("claim_id, from_status, to_status, actor_role, reason, created_at")
      .in(
        "claim_id",
        claims!.map((c) => c.id),
      )
      .order("created_at");
    events = (ev ?? []).reduce<Record<string, EventView[]>>((acc, e) => {
      (acc[e.claim_id] ??= []).push({
        from: e.from_status,
        to: e.to_status,
        actor_role: e.actor_role,
        reason: e.reason,
        at: e.created_at,
      });
      return acc;
    }, {});
  }

  const parsedDraft = draft ? aiDraftSchema.safeParse(draft.payload) : null;

  return (
    <main className="flex flex-col gap-5 pt-6">
      <Link href="/app" className="text-sm text-ink underline">
        ← Mis pruebas
      </Link>
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-extrabold">{proof.title}</h1>
        {proof.is_demo && <DemoLabel />}
      </div>

      <details className="rounded-2xl border border-line bg-card p-4">
        <summary className="cursor-pointer font-semibold">Tu evidencia original</summary>
        <p className="mt-2 whitespace-pre-wrap text-sm">{proof.raw_evidence}</p>
        {proof.evidence_link && (
          <a href={proof.evidence_link} target="_blank" rel="noopener noreferrer nofollow" className="mt-2 block text-sm text-ink underline">
            {proof.evidence_link}
          </a>
        )}
      </details>

      {hasClaims ? (
        <section className="flex flex-col gap-4">
          <h2 className="text-xl font-extrabold">Tus frases</h2>
          {claims!.map((c) => (
            <ClaimCard
              key={c.id}
              claim={c as ClaimView}
              events={events[c.id] ?? []}
              aiOrganized={Boolean(draft)}
              showWarnings
            />
          ))}
        </section>
      ) : parsedDraft?.success ? (
        <DraftEditor
          key={draft!.id}
          proofId={proof.id}
          claims={parsedDraft.data.claims}
          aiFlags={(draft!.overclaim_flags as OverclaimFlag[]) ?? []}
          simulated={draft!.simulated}
        />
      ) : (
        <GenerateDraft proofId={proof.id} auto />
      )}
    </main>
  );
}
