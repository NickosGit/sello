import Link from "next/link";

import { DemoLabel } from "@/components/Labels";
import { requireUser } from "@/lib/session";

export default async function Dashboard() {
  const { supabase, profile, name } = await requireUser("/app");

  const { data: proofs } = await supabase
    .from("proofs")
    .select("id, title, is_demo, created_at, claims(count)")
    .order("created_at", { ascending: false });

  return (
    <main className="flex flex-col gap-5 pt-6">
      <h1 className="text-2xl font-extrabold">Hola, {name}</h1>
      {!profile && (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-bad">
          Tu perfil todavía no existe. Falta correr la migración de la base de datos.
        </p>
      )}

      <Link href="/app/proofs/new" className="rounded-2xl bg-ink py-4 text-center text-lg font-bold text-white">
        + Nueva prueba de tu trabajo
      </Link>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-muted">Tus pruebas ({proofs?.length ?? 0})</h2>
        {(proofs ?? []).length === 0 && (
          <p className="text-muted">Todavía no tienes pruebas. Empieza con algo que ya hiciste.</p>
        )}
        {(proofs ?? []).map((p) => {
          const n = (p.claims as unknown as { count: number }[])?.[0]?.count ?? 0;
          return (
            <Link
              key={p.id}
              href={`/app/proofs/${p.id}`}
              className="flex flex-col gap-1 rounded-2xl border border-line bg-card p-4"
            >
              <span className="font-semibold">{p.title}</span>
              <span className="text-sm text-muted">
                {n === 0 ? "Borrador sin aprobar" : `${n} ${n === 1 ? "frase" : "frases"}`}
              </span>
              {p.is_demo && <DemoLabel />}
            </Link>
          );
        })}
      </section>
    </main>
  );
}
