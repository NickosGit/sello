import { NextResponse, type NextRequest } from "next/server";

import { createServerClient } from "@supabase/ssr";

import { isProtectedPath, loginRedirectPath } from "@/lib/routes";

/**
 * Refresca la sesión de Supabase y protege /app, /review y /vouch.
 * (Next 16 llama "proxy" a lo que antes era middleware.)
 * Las páginas vuelven a comprobar la sesión: esto es la primera barrera, no la única.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { pathname, search } = request.nextUrl;
  const needsAuth = isProtectedPath(pathname);

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Sin credenciales no hay sesión posible: las rutas privadas mandan al login,
  // que explica en pantalla qué falta configurar.
  if (!url || !anonKey) {
    if (!needsAuth) return response;
    return NextResponse.redirect(new URL(loginRedirectPath(pathname, search), request.url));
  }

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user && needsAuth) {
    return NextResponse.redirect(new URL(loginRedirectPath(pathname, search), request.url));
  }

  return response;
}

export const config = {
  // Todo menos estáticos, la vista pública por token y el cron (que se autentica con su secreto).
  matcher: ["/((?!_next/static|_next/image|favicon.ico|p/|api/cron/|.*\\.(?:png|jpg|svg|ico|webmanifest)$).*)"],
};
