export type ClaimStatus = "DECLARED" | "VOUCHED" | "VERIFIED";

/** Etiqueta corta + explicación de una línea. Nunca se muestra el estado sin explicarlo. */
export const STATUS_COPY: Record<ClaimStatus, { label: string; explain: string }> = {
  DECLARED: { label: "DECLARADO", explain: "Lo dices tú" },
  VOUCHED: { label: "RESPALDADO", explain: "Alguien que vio tu trabajo lo confirma" },
  VERIFIED: { label: "VERIFICADO", explain: "Una persona independiente revisó la evidencia" },
};

const STYLES: Record<ClaimStatus, string> = {
  DECLARED: "bg-declared-soft text-declared border-declared/30",
  VOUCHED: "bg-vouched-soft text-vouched border-vouched/30",
  VERIFIED: "bg-verified-soft text-verified border-verified/30",
};

export function StatusBadge({ status }: { status: ClaimStatus }) {
  const copy = STATUS_COPY[status];
  return (
    <span className="inline-flex flex-wrap items-baseline gap-x-2">
      <span
        className={`rounded-md border px-2 py-0.5 text-xs font-bold tracking-wide ${STYLES[status]}`}
      >
        {copy.label}
      </span>
      <span className="text-sm text-muted">{copy.explain}</span>
    </span>
  );
}

export function StatusLegend() {
  return (
    <ul className="flex flex-col gap-2 rounded-2xl border border-line bg-card p-4">
      {(Object.keys(STATUS_COPY) as ClaimStatus[]).map((s) => (
        <li key={s}>
          <StatusBadge status={s} />
        </li>
      ))}
    </ul>
  );
}
