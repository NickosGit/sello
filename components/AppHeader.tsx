import Link from "next/link";

export function AppHeader({ name }: { name: string }) {
  return (
    <header className="flex items-center justify-between gap-3 border-b border-line py-4">
      <Link href="/app" className="text-lg font-extrabold text-ink">
        Sello
      </Link>
      <div className="flex items-center gap-3 text-sm">
        <span className="max-w-40 truncate text-muted">{name}</span>
        <form action="/auth/signout" method="post">
          <button type="submit" className="rounded-lg border border-line px-3 py-1.5 font-semibold">
            Salir
          </button>
        </form>
      </div>
    </header>
  );
}
