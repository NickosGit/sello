"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { AiBanner, AiLabel } from "@/components/Labels";
import { OverclaimWarnings } from "@/components/OverclaimWarnings";
import { StatusBadge } from "@/components/StatusBadge";
import { FIELD_LABELS } from "@/lib/claim-copy";
import { normalize, ruleFlags } from "@/lib/overclaim";
import { CLAIM_FIELDS, LIMITS, type DraftClaim, type OverclaimFlag } from "@/lib/schemas";

import { approveDraft } from "./actions";
import { GenerateDraft } from "./GenerateDraft";

type Row = DraftClaim & { include: boolean };

const DETAIL_FIELDS = CLAIM_FIELDS.filter((f) => f !== "text");

export function DraftEditor({
  proofId,
  claims,
  aiFlags,
  simulated,
}: {
  proofId: string;
  claims: DraftClaim[];
  aiFlags: OverclaimFlag[];
  simulated: boolean;
}) {
  const router = useRouter();
  const [rows, setRows] = useState<Row[]>(() => claims.map((c) => ({ ...c, include: true })));
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function update(i: number, patch: Partial<Row>) {
    setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  }

  const included = rows.filter((r) => r.include);
  const tooLong = included.some((r) => r.text.trim().length < LIMITS.claimText.min || r.text.length > LIMITS.claimText.max);

  function onApprove() {
    setError(null);
    startTransition(async () => {
      const res = await approveDraft({
        proof_id: proofId,
        claims: included.map((r) => Object.fromEntries(CLAIM_FIELDS.map((f) => [f, r[f]]))),
      });
      if (!res.ok) setError(res.error);
      else router.refresh();
    });
  }

  return (
    <section className="flex flex-col gap-4">
      <AiBanner simulated={simulated} />
      <h2 className="text-xl font-extrabold">Revisa tus frases</h2>
      <p className="text-muted">
        Cambia lo que no suene a ti, quita lo que no sea cierto y luego aprueba. Al aprobar, cada frase queda como{" "}
        <strong>DECLARADO</strong>.
      </p>

      {rows.map((row, i) => {
        // Rule flags follow the current text; AI flags only while the flagged word is still there.
        const live = ruleFlags([row]).map((f) => ({ ...f, claim_index: i }));
        const fromAi = aiFlags.filter(
          (f) =>
            f.source === "ai" &&
            f.claim_index === i &&
            normalize(row.text + " " + (row.scope ?? "")).includes(normalize(f.term)) &&
            !live.some((l) => normalize(l.term) === normalize(f.term)),
        );
        const flags = [...live, ...fromAi];

        return (
          <article
            key={i}
            className={`flex flex-col gap-3 rounded-2xl border bg-card p-4 ${row.include ? "border-line" : "border-dashed border-line opacity-60"}`}
          >
            <div className="flex flex-wrap items-center justify-between gap-2">
              <StatusBadge status="DECLARED" />
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={row.include}
                  onChange={(e) => update(i, { include: e.target.checked })}
                />
                Incluir
              </label>
            </div>
            <AiLabel />

            <label className="flex flex-col gap-1">
              <span className="text-sm font-semibold">{FIELD_LABELS.text}</span>
              <textarea
                value={row.text}
                rows={3}
                onChange={(e) => update(i, { text: e.target.value })}
                className="rounded-xl border border-line px-3 py-2"
              />
              <span
                className={`self-end text-xs ${row.text.length > LIMITS.claimText.max ? "font-bold text-bad" : "text-muted"}`}
              >
                {row.text.length} / {LIMITS.claimText.max}
              </span>
            </label>

            <OverclaimWarnings flags={flags} />

            <details className="rounded-xl bg-background p-3">
              <summary className="cursor-pointer text-sm font-semibold">Detalles (qué cubre, qué no se puede concluir…)</summary>
              <div className="mt-3 flex flex-col gap-3">
                {DETAIL_FIELDS.map((f) => (
                  <label key={f} className="flex flex-col gap-1">
                    <span className="text-sm font-semibold">{FIELD_LABELS[f]}</span>
                    <textarea
                      value={row[f] ?? ""}
                      rows={2}
                      maxLength={LIMITS.claimField.max}
                      onChange={(e) => update(i, { [f]: e.target.value })}
                      className="rounded-xl border border-line px-3 py-2 text-sm"
                    />
                  </label>
                ))}
              </div>
            </details>
          </article>
        );
      })}

      {error && (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-bad">
          {error}
        </p>
      )}

      <button
        type="button"
        onClick={onApprove}
        disabled={pending || included.length === 0 || tooLong}
        className="rounded-2xl bg-ink py-4 text-lg font-bold text-white disabled:opacity-50"
      >
        {pending ? "Guardando…" : `Aprobar ${included.length} ${included.length === 1 ? "frase" : "frases"}`}
      </button>

      <GenerateDraft proofId={proofId} label="No me sirve: hacer otro borrador" />
    </section>
  );
}
