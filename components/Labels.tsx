/** Required on-screen labels (prompt §0.6 and §0.7). Exact English string + plain Spanish. */

export function AiLabel() {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-2 gap-y-0.5 rounded-md bg-ai-soft px-2 py-0.5 text-xs text-ai">
      <span className="font-bold">AI-organized · status unchanged by AI</span>
      <span>Lo ordenó la IA. La IA no puede cambiar ningún estado.</span>
    </span>
  );
}

export function SimulatedLabel() {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-2 gap-y-0.5 rounded-md border border-ai/40 bg-card px-2 py-0.5 text-xs text-ai">
      <span className="font-bold">SIMULATED AI OUTPUT</span>
      <span>Borrador de prueba: no lo hizo una IA real.</span>
    </span>
  );
}

export function DemoLabel() {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-2 rounded-md bg-declared-soft px-2 py-0.5 text-xs text-declared">
      <span className="font-bold">Invented demo data</span>
      <span>Datos inventados para la demo</span>
    </span>
  );
}

export function AiBanner({ simulated }: { simulated: boolean }) {
  return (
    <div className="flex flex-col gap-2 rounded-2xl border border-ai/30 bg-ai-soft p-4 text-ai">
      <p className="font-bold">La IA ordenó este texto. La IA no puede cambiar ningún estado.</p>
      <p className="text-sm">
        Todo empieza como <strong>DECLARADO</strong> (lo dices tú). Solo una persona que vio tu trabajo, o una
        persona independiente, puede subirlo de nivel.
      </p>
      <div className="flex flex-wrap gap-2">
        <AiLabel />
        {simulated && <SimulatedLabel />}
      </div>
    </div>
  );
}
