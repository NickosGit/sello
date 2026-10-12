import { safeNext } from "@/lib/routes";
import { hasSupabaseEnv } from "@/lib/supabase/env";

import { GoogleButton } from "./GoogleButton";

const ERRORS: Record<string, string> = {
  enlace: "No se pudo terminar de entrar. Intenta otra vez.",
  sin_codigo: "Google no regresó la información completa. Intenta otra vez.",
};

export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const params = await searchParams;
  const next = safeNext(typeof params.next === "string" ? params.next : null);
  const error = typeof params.error === "string" ? ERRORS[params.error] : undefined;

  return (
    <main className="flex flex-1 flex-col gap-5 pt-10">
      <h1 className="text-3xl font-extrabold">Entrar a Sello</h1>
      <p className="text-lg text-muted">
        Usamos tu cuenta de Google solo para saber que eres tú. No publicamos nada ni te cobramos.
      </p>
      {error && (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-base text-bad">
          {error}
        </p>
      )}
      {hasSupabaseEnv ? (
        <GoogleButton next={next} />
      ) : (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-base text-bad">
          Falta configurar Supabase en este despliegue.
        </p>
      )}
    </main>
  );
}
