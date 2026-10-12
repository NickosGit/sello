import { requireUser } from "@/lib/session";

export default async function Dashboard() {
  const { profile, name } = await requireUser("/app");

  return (
    <main className="flex flex-col gap-4 pt-6">
      <h1 className="text-2xl font-extrabold">Hola, {name}</h1>
      {profile ? (
        <p className="text-muted">Tu cuenta está lista.</p>
      ) : (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-bad">
          Tu perfil todavía no existe. Falta correr la migración de la base de datos.
        </p>
      )}
    </main>
  );
}
