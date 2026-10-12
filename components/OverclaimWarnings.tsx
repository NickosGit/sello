import type { OverclaimFlag } from "@/lib/schemas";

export function OverclaimWarnings({ flags }: { flags: Pick<OverclaimFlag, "term" | "message" | "source">[] }) {
  if (flags.length === 0) return null;
  return (
    <ul className="flex flex-col gap-1.5" aria-label="Avisos de exageración">
      {flags.map((f, i) => (
        <li key={i} className="rounded-lg border border-vouched/40 bg-vouched-soft px-3 py-2 text-sm text-vouched">
          <strong>⚠ «{f.term}»</strong> {f.message}
          {f.source === "ai" && <span className="ml-1 text-xs opacity-80">(aviso de la IA)</span>}
        </li>
      ))}
    </ul>
  );
}
