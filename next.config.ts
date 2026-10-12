import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Todo lo que muestra Sello depende de quién pregunta (RLS) o de un token.
  // Nada se debe cachear entre peticiones, así que se apaga Cache Components
  // (ver DECISIONS.md, 2026-10-11).
  cacheComponents: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "X-Frame-Options", value: "DENY" },
        ],
      },
    ];
  },
};

export default nextConfig;
