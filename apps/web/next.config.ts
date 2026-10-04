import type { NextConfig } from "next";
import { readFileSync } from "node:fs";

/**
 * Security headers for the informational site.
 * No `'unsafe-eval'` — this app does not compile shaders.
 *
 * When `STATIC_EXPORT=true`, produces a static site (`out/`) for static
 * hosts. `async headers()` is incompatible with `output: 'export'`.
 *
 * itch.io does **not** receive this Next.js app. The canonical itch artifact
 * is the Godot Web export at `dist/game/web/`.
 *
 * @see ../../docs/architecture/SECURITY.md
 * @see ../../docs/concepts/web.md
 */

const isStaticExport = process.env.STATIC_EXPORT === "true";

const { version } = JSON.parse(readFileSync("./package.json", "utf-8")) as {
  version: string;
};

const cspDirectives = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "connect-src 'self'",
  "frame-src 'self'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "object-src 'none'",
  "base-uri 'self'",
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: cspDirectives },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=()",
  },
];

const nextConfig: NextConfig = {
  productionBrowserSourceMaps: false,
  env: {
    NEXT_PUBLIC_APP_VERSION: version,
  },
  allowedDevOrigins: ["127.0.0.1"],
  ...(isStaticExport
    ? {
        output: "export" as const,
        trailingSlash: true,
        images: { unoptimized: true },
      }
    : {
        async headers() {
          return [{ source: "/(.*)", headers: securityHeaders }];
        },
      }),
};

export default nextConfig;
