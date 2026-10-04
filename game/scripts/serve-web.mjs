#!/usr/bin/env node

/**
 * Serve the Godot Web export on localhost for development.
 */

import { createServer } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const GAME_ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const DIST_WEB = join(GAME_ROOT, "..", "..", "dist", "game", "web");
const PORT = 8060;

const MIME_TYPES = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".pck": "application/octet-stream",
};

if (!existsSync(DIST_WEB)) {
  console.error(`Web export not found at ${DIST_WEB}`);
  console.error(
    "Run `pnpm game:export:web` to build the Godot Web export first.",
  );
  process.exit(1);
}

const server = createServer((req, res) => {
  let pathname = req.url?.split("?")[0] ?? "/";
  if (pathname === "/") pathname = "/index.html";

  const filePath = join(DIST_WEB, pathname);

  if (!existsSync(filePath) || !statSync(filePath).isFile()) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not Found");
    return;
  }

  const ext = extname(filePath);
  const contentType = MIME_TYPES[ext] ?? "application/octet-stream";

  // Required headers for SharedArrayBuffer (if threading is used)
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");

  res.writeHead(200, { "Content-Type": contentType });
  createReadStream(filePath).pipe(res);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Serving Godot Web export at http://127.0.0.1:${PORT}/`);
  console.log(`Source: ${DIST_WEB}`);
  console.log("Press Ctrl+C to stop.");
});
