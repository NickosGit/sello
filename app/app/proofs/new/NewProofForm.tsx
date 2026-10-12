"use client";

import { useActionState, useState } from "react";

import { LIMITS } from "@/lib/schemas";

import { createProof, type NewProofState } from "./actions";

const initial: NewProofState = { error: null };

const input = "rounded-xl border border-line bg-card px-3 py-2.5 text-base";

export function NewProofForm() {
  const [state, action, pending] = useActionState(createProof, initial);
  const [evidence, setEvidence] = useState("");
  const len = evidence.length;
  const over = len > LIMITS.rawEvidence.max;

  return (
    <form action={action} className="flex flex-col gap-5">
      <Field label="Ponle un nombre corto" hint="Ej. «Pedidos e inventario de la taquería»" error={state.fields?.title}>
        <input name="title" required minLength={3} maxLength={LIMITS.title.max} className={input} />
      </Field>

      <Field
        label="¿Qué hiciste? Cuéntalo con tus palabras"
        hint="Qué hacías, desde cuándo, cuánto (pedidos, clientes, horas). No tiene que sonar elegante."
        error={state.fields?.raw_evidence}
      >
        <textarea
          name="raw_evidence"
          required
          rows={8}
          value={evidence}
          onChange={(e) => setEvidence(e.target.value)}
          className={input}
        />
        <span className={`self-end text-sm ${over ? "font-bold text-bad" : "text-muted"}`} aria-live="polite">
          {len.toLocaleString("es-MX")} / {LIMITS.rawEvidence.max.toLocaleString("es-MX")}
          {over && " · es demasiado largo"}
        </span>
      </Field>

      <Field
        label="Enlace a tu trabajo (opcional)"
        hint="Una foto en Drive, una hoja de cálculo, un post. Solo enlaces, no subimos archivos."
        error={state.fields?.evidence_link}
      >
        <input name="evidence_link" type="url" inputMode="url" maxLength={LIMITS.evidenceLink.max} className={input} />
      </Field>

      <Field
        label="¿A quién se lo vas a mandar? (opcional)"
        hint="Ej. «Roberto, jefe de operaciones»"
        error={state.fields?.intended_decision_maker}
      >
        <input name="intended_decision_maker" maxLength={LIMITS.decisionMaker.max} className={input} />
      </Field>

      <Field
        label="¿Qué quieres que decida? (opcional)"
        hint="Ej. «Que me llame a entrevista»"
        error={state.fields?.intended_decision}
      >
        <input name="intended_decision" maxLength={LIMITS.intendedDecision.max} className={input} />
      </Field>

      {state.error && (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-bad">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending || over}
        className="rounded-2xl bg-ink py-4 text-lg font-bold text-white disabled:opacity-50"
      >
        {pending ? "Guardando…" : "Guardar y ordenar con IA"}
      </button>
      <p className="text-sm text-muted">
        La IA solo ordena tu texto en frases. No decide nada ni marca nada como comprobado.
      </p>
    </form>
  );
}

function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="font-semibold">{label}</span>
      {hint && <span className="text-sm text-muted">{hint}</span>}
      {children}
      {error && (
        <span role="alert" className="text-sm text-bad">
          {error}
        </span>
      )}
    </label>
  );
}
