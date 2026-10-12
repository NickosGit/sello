/**
 * Qué rutas exigen sesión. Función pura para poder probarla sin levantar Next.
 * `/p/*` (vista del tomador de decisión) es pública a propósito: entra por token.
 */
const PROTECTED_PREFIXES = ["/app", "/review", "/vouch"];

export function isProtectedPath(pathname: string): boolean {
  return PROTECTED_PREFIXES.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

/** A dónde mandar a alguien sin sesión, recordando a dónde iba. */
export function loginRedirectPath(pathname: string, search = ""): string {
  return "/login?next=" + encodeURIComponent(pathname + search);
}

/** Solo aceptamos `next` relativo al sitio, para no abrir un redirect a otro dominio. */
export function safeNext(next: string | null | undefined, fallback = "/app"): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) {
    return fallback;
  }
  return next;
}
