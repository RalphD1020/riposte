#!/usr/bin/env node

/**
 * Turn a saved ElevenLabs flow run-status response into a fetch list.
 *
 *   node tools/audio/takes-from-status.mjs -o list.json <status.json|txt> <family-dir> <stem> <session…>
 *
 * Sessions are numbered in the order given (`<stem>_01.mp3`, `_02`, …), so
 * the takes keep the order they were generated in. Only completed takes
 * with a content URL are listed; anything still pending is reported on
 * stderr so the family can be fetched again once it lands.
 */

import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const outIndex = args.indexOf("-o");
const outPath = outIndex >= 0 ? args.splice(outIndex, 2)[1] : null;
const [statusPath, familyDir, stem, ...sessions] = args;
const text = readFileSync(statusPath, "utf8");
const status = JSON.parse(text.slice(text.indexOf("{")));
const bySession = new Map();
for (const generation of status.generations ?? []) {
  const match = /content_generation\/([^/]+)\//.exec(
    generation.content_url ?? "",
  );
  if (generation.status === "completed" && match) {
    bySession.set(match[1], generation.content_url);
  }
}
const list = [];
sessions.forEach((session, index) => {
  const url = bySession.get(session);
  if (!url) {
    console.error(`PENDING ${stem} take ${index + 1} (${session})`);
    return;
  }
  list.push({
    path: `${familyDir}/${stem}_${String(index + 1).padStart(2, "0")}.mp3`,
    url,
  });
});
const json = JSON.stringify(list, null, 1) + "\n";
if (outPath) {
  writeFileSync(outPath, json, "utf8");
} else {
  process.stdout.write(json);
}
