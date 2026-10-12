import { NextResponse } from "next/server";

import { safeNext } from "@/lib/routes";
import { createClient } from "@/lib/supabase/server";

/** Vuelta desde Google (PKCE): cambia el `code` por una sesión en cookies. */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = safeNext(searchParams.get("next"));

  // Detrás del proxy de Vercel, `origin` puede ser el host interno.
  const forwardedHost = request.headers.get("x-forwarded-host");
  const isLocal = process.env.NODE_ENV === "development";
  const base = isLocal || !forwardedHost ? origin : "https://" + forwardedHost;

  if (!code) return NextResponse.redirect(base + "/login?error=sin_codigo");

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) return NextResponse.redirect(base + "/login?error=enlace");

  return NextResponse.redirect(base + next);
}
