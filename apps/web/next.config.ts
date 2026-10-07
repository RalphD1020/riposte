import type { NextConfig } from "next";
import { existsSync, readFileSync } from "node:fs";

/**
 * Security headers for the site, plus the hosting contract for the staged
 * Godot Web export (WEB-004, WEB-005).
 *
 * The site itself gets no `'unsafe-eval'` — it does not compile shaders — and
 * embeds nothing, so frames are refused in both directions. `/game/*` is the
 * one place that needs more, and gets it **path-scoped**: WebAssembly needs
 * `'wasm-unsafe-eval'` and the audio worklet needs `worker-src blob:`.
 * Widening the site-wide policy to cover one directory would hand those
 * capabilities to every page that does not need them.
 *
 * The export is single-threaded Compatibility (`thread_support=false`), so
 * there is no `SharedArrayBuffer` and therefore no COOP/COEP requirement —
 * which is the whole reason this can be served from our own origin next to
 * ordinary pages rather than from an isolated one.
 *
 * `/play` rewrites to the staged shell **only when the artifact is present**.
 * An unconditional rewrite is the worst of the options: with no export staged
 * it turns `/play` into a 404 instead of the page that explains where the
 * game is. Staging is a build-time fact, so it is read once, here.
 *
 * When `STATIC_EXPORT=true`, produces a static site (`out/`). `async
 * headers()` and `async rewrites()` are unsupported by `output: 'export'`;
 * static hosts set their own headers and `PlayGateway` performs the hop in
 * the browser.
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

/**
 * Kept as a literal rather than imported from `src/`: this file is loaded
 * before the app's module aliases exist. `runtimeConfig.test.ts` asserts it
 * stays equal to `HOSTED_PLAY_PATH`.
 */
const HOSTED_PLAY_PATH = "/game/index.html";
const hasStagedGame = existsSync(`./public${HOSTED_PLAY_PATH}`);

/**
 * Stated once, so hardening the site can never silently skip `/game`. The two
 * policies below differ *only* in what the engine needs; everything a visitor
 * is protected from is shared.
 */
const sharedCspDirectives = [
  "default-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self'",
  "connect-src 'self'",
  "frame-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "object-src 'none'",
  "base-uri 'self'",
];

const cspDirectives = [
  ...sharedCspDirectives,
  "script-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
].join("; ");

const gameCspDirectives = [
  ...sharedCspDirectives,
  // WebAssembly compilation, the audio worklet, and the blob-backed textures
  // and samples the engine decodes at runtime.
  "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'",
  "worker-src 'self' blob:",
  "img-src 'self' data: blob:",
  "media-src 'self' data: blob:",
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: cspDirectives },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  {
    key: "Strict-Transport-Security",
    value: "max-age=63072000; includeSubDomains",
  },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=()",
  },
];

const gameHeaders = securityHeaders
  .filter((header) => header.key !== "Content-Security-Policy")
  .concat({ key: "Content-Security-Policy", value: gameCspDirectives });

/**
 * The engine files are rebuilt on every export and are not content-hashed, so
 * the shell must not be cached — a stale `index.html` beside a fresh
 * `index.pck` is a crash with no useful message. The payload is large and
 * revalidation is cheap, so it is cached but always revalidated.
 */
const SHELL_CACHE = "no-cache";
const PAYLOAD_CACHE = "public, max-age=0, must-revalidate";

const nextConfig: NextConfig = {
  productionBrowserSourceMaps: false,
  env: {
    NEXT_PUBLIC_APP_VERSION: version,
    NEXT_PUBLIC_HOSTED_PLAY: hasStagedGame ? HOSTED_PLAY_PATH : "",
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
          return [
            { source: "/(.*)", headers: securityHeaders },
            { source: "/game/:path*", headers: gameHeaders },
            {
              source: "/game/index.html",
              headers: [{ key: "Cache-Control", value: SHELL_CACHE }],
            },
            {
              source: "/game/:path*.(wasm|pck|js|png|svg|webp|ogg|wav)",
              headers: [{ key: "Cache-Control", value: PAYLOAD_CACHE }],
            },
          ];
        },
        /**
         * `beforeFiles`, not the bare array. A bare array is `afterFiles`,
         * which loses to the `/play` page that exists precisely as the
         * fallback — so the rewrite would never fire and every visitor would
         * take a needless client-side hop through it.
         */
        async rewrites() {
          return {
            beforeFiles: hasStagedGame
              ? [{ source: "/play", destination: HOSTED_PLAY_PATH }]
              : [],
            afterFiles: [],
            fallback: [],
          };
        },
      }),
};

export default nextConfig;
