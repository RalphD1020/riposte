#!/usr/bin/env node

/**
 * Serve the canonical Godot Web export (`dist/game/web/`) the way itch will.
 * Loopback only. Next.js does not own this process (MONO-001).
 * The export is single-threaded (WEB-003), so no cross-origin isolation
 * headers are required.
 *
 * @see ../../spec/invariants.md#web-004
 * @see ../../docs/guides/local-dev.md
 */

import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const GAME_ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const WEB_ROOT = resolve(GAME_ROOT, "..", "dist", "game", "web");
const PORT = Number(process.env.RIPOSTE_GODOT_WEB_PORT ?? 8060);
const HOST = process.env.RIPOSTE_GODOT_WEB_HOST ?? "127.0.0.1";

const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".json": "application/json; charset=utf-8",
};

/** Resolve a request path inside WEB_ROOT, rejecting traversal. */
function safePath(urlPath) {
  let decoded;
  try {
    decoded = decodeURIComponent(urlPath.split("?")[0] || "/");
  } catch {
    return null;
  }
  const relative = decoded === "/" ? "/index.html" : decoded;
  const target = resolve(WEB_ROOT, `.${relative}`);
  if (target !== WEB_ROOT && !target.startsWith(`${WEB_ROOT}${sep}`)) {
    return null;
  }
  return target;
}

function missingExportPage() {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Riposte Godot Web</title></head><body><main><h1>Godot Web export not found</h1><p>Run <code>pnpm game:export:web</code> to build <code>dist/game/web/</code> (WEB-004), then reload.</p></main></body></html>`;
}

const server = createServer((request, response) => {
  const target = safePath(request.url ?? "/");
  if (target == null) {
    response.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Forbidden");
    return;
  }
  if (existsSync(target) && statSync(target).isFile()) {
    response.writeHead(200, {
      "Content-Type":
        CONTENT_TYPES[extname(target)] ?? "application/octet-stream",
      "Cache-Control": "no-store",
    });
    createReadStream(target).pipe(response);
    return;
  }
  const isRoot = target === resolve(WEB_ROOT, "index.html");
  response.writeHead(isRoot ? 200 : 404, {
    "Content-Type": "text/html; charset=utf-8",
  });
  response.end(
    isRoot ? missingExportPage() : "<!doctype html><title>Not found</title>",
  );
});

server.listen(PORT, HOST, () => {
  console.log(`Godot Web serve http://${HOST}:${PORT}/ <- ${WEB_ROOT}`);
});
