import { AiLabel } from "@/components/Labels";
import { OverclaimWarnings } from "@/components/OverclaimWarnings";
import { StatusBadge, type ClaimStatus } from "@/components/StatusBadge";
import { FIELD_LABELS } from "@/lib/claim-copy";
import { ruleFlags } from "@/lib/overclaim";

export type ClaimView = {
  id: string;
  text: string;
  status: ClaimStatus;
  scope: string | null;
  conditions?: string | null;
  ai_assistance?: string | null;
  revisions?: string | null;
  missing_info?: string | null;
  cannot_infer: string | null;
};

export type EventView = {
  from: ClaimStatus | null;
  to: ClaimStatus;
  actor_role: "worker" | "voucher" | "reviewer" | "system";
  reason: string | null;
  at: string;
};

const ROLE_COPY: Record<EventView["actor_role"], string> = {
  worker: "Lo declaró quien hizo el trabajo",
  voucher: "Lo respaldó alguien que vio el trabajo",
  reviewer: "Revisor independiente",
  system: "Sistema",
};

function eventLine(e: EventView): string {
  if (e.actor_role === "reviewer") {
    if (e.from === e.to) return "Un revisor independiente lo revisó y no lo verificó";
    if (e.to === "VERIFIED") return "Lo verificó un revisor independiente";
    if (e.from === "VERIFIED") return "Un revisor independiente retiró la verificación";
  }
  return ROLE_COPY[e.actor_role];
}

const fmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", year: "numeric" });

export function ClaimCard({
  claim,
  events,
  aiOrganized,
  showWarnings = false,
  showDetails = true,
  children,
}: {
  claim: ClaimView;
  events: EventView[];
  aiOrganized: boolean;
  showWarnings?: boolean;
  showDetails?: boolean;
  children?: React.ReactNode;
}) {
  const declared = events.find((e) => e.from === null);
  const later = events.filter((e) => e !== declared);
  const extra = (["conditions", "ai_assistance", "revisions", "missing_info"] as const).filter((f) => claim[f]);

  return (
    <article className="flex flex-col gap-3 rounded-2xl border border-line bg-card p-4">
      <StatusBadge status={claim.status} />
      <p className="text-lg leading-snug font-semibold">{claim.text}</p>

      {showWarnings && <OverclaimWarnings flags={ruleFlags([claim])} />}

      {claim.scope && (
        <p className="text-sm">
          <span className="font-semibold">{claim.status === "VERIFIED" ? "Qué revisó el revisor: " : "Qué cubre: "}</span>
          {claim.scope}
        </p>
      )}
      {claim.cannot_infer && (
        <div className="rounded-xl bg-declared-soft p-3 text-sm">
          <span className="font-semibold">No se puede concluir: </span>
          {claim.cannot_infer}
        </div>
      )}

      {showDetails && extra.length > 0 && (
        <details className="text-sm">
          <summary className="cursor-pointer text-muted">Más detalles</summary>
          <dl className="mt-2 flex flex-col gap-2">
            {extra.map((f) => (
              <div key={f}>
                <dt className="font-semibold">{FIELD_LABELS[f]}</dt>
                <dd>{claim[f]}</dd>
              </div>
            ))}
          </dl>
        </details>
      )}

      {aiOrganized && <AiLabel />}

      <ol className="flex flex-col gap-1.5 border-l-2 border-line pl-3 text-sm" aria-label="Historial">
        {declared && (
          <li>
            <span className="font-semibold">{eventLine(declared)}</span>{" "}
            <span className="text-muted">· {fmt.format(new Date(declared.at))}</span>
          </li>
        )}
        {aiOrganized && <li className="text-ai">La IA ordenó el texto (no cambió el estado)</li>}
        {later.map((e, i) => (
          <li key={i}>
            <span className="font-semibold">{eventLine(e)}</span>{" "}
            <span className="text-muted">· {fmt.format(new Date(e.at))}</span>
            {e.reason && <span className="block text-muted">«{e.reason}»</span>}
          </li>
        ))}
      </ol>

      {children}
    </article>
  );
}
