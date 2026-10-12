import Link from "next/link";

import { StatusLegend } from "@/components/StatusBadge";

export default function Home() {
  return (
    <main className="flex flex-1 flex-col gap-6 pt-10">
      <p className="text-sm font-semibold tracking-wide text-ink uppercase">Sello</p>
      <h1 className="text-3xl leading-tight font-extrabold">
        Tu trabajo, con la etiqueta honesta de qué tan comprobado está.
      </h1>
      <p className="text-lg text-muted">
        Pega lo que hiciste. Lo ordenamos en frases claras. Luego alguien que vio tu trabajo, o una
        persona que no te conoce, lo revisa. Y tú sabes si quien lo recibió lo abrió.
      </p>
      <StatusLegend />
      <Link
        href="/app"
        className="rounded-2xl bg-ink py-4 text-center text-lg font-bold text-white"
      >
        Empezar
      </Link>
    </main>
  );
}
