#!/usr/bin/env node

/**
 * Download generated audio takes into the Godot project.
 *
 *   node tools/audio/fetch-takes.mjs <list.json>
 *
 * The list is `[{ "path": "res-relative/target.mp3", "url": "https://…" }]`.
 * ElevenLabs content URLs are signed and short-lived, so this runs right
 * after a generation; the committed files, not the URLs, are the asset.
 * A take that fails to download fails the run — no half-populated family.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const list = JSON.parse(readFileSync(process.argv[2], "utf8"));

/**
 * Compact entries `{ p, w, s, g, d, x }` (path, workspace, session,
 * generation, signing date, signature) expand to the signed storage URL.
 */
function urlOf(take) {
  if (take.url) return take.url;
  const credential =
    "xi-backend-prod%40xi-labs.iam.gserviceaccount.com%2F" +
    take.d.slice(0, 8) +
    "%2Fauto%2Fstorage%2Fgoog4_request";
  return (
    `https://storage.googleapis.com/xi-backend/database/workspace/${take.w}/content_generation/${take.s}/${take.g}/content.mp3` +
    `?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Credential=${credential}&X-Goog-Date=${take.d}` +
    `&X-Goog-Expires=7200&X-Goog-SignedHeaders=host&X-Goog-Signature=${take.x}`
  );
}

let failed = 0;
for (const take of list) {
  const path = take.path ?? take.p;
  const target = join(root, "game", path);
  const response = await fetch(urlOf(take));
  if (!response.ok) {
    console.error(`FAIL ${path}: HTTP ${response.status}`);
    failed += 1;
    continue;
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, bytes);
  console.log(`OK   ${path} (${bytes.length} bytes)`);
}
process.exit(failed === 0 ? 0 : 1);
