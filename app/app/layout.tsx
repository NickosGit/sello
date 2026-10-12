import { AppHeader } from "@/components/AppHeader";
import { requireUser } from "@/lib/session";

export default async function AppLayout({ children }: LayoutProps<"/app">) {
  const { name } = await requireUser("/app");
  return (
    <>
      <AppHeader name={name} />
      {children}
    </>
  );
}
