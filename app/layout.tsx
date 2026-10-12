import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";

import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Sello · Pruebas de tu trabajo",
  description:
    "Ordena la evidencia de tu trabajo, muestra qué tan comprobada está y sabe si alguien la abrió.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#1f3a5f",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es-MX" className={`${geistSans.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col">
        <div className="mx-auto flex w-full max-w-xl flex-1 flex-col px-4 pb-10">{children}</div>
      </body>
    </html>
  );
}
