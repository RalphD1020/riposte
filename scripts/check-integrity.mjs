#!/usr/bin/env node

/**
 * Repository integrity: merge markers, large files, case-conflicting paths.
 *
 * @see ../docs/architecture/SECURITY.md
 */

import { spawnSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const MAX_BYTES = 500 * 1024;
const errors = [];

const tracked = spawnSync("git", ["ls-files", "-z"], {
  cwd: ROOT,
  encoding: "utf-8",
});

if (tracked.status !== 0) {
  console.error("integrity:check failed — git ls-files");
  process.exit(tracked.status ?? 1);
}

const files = tracked.stdout.split("\0").filter(Boolean);
const lowerMap = new Map();

for (const file of files) {
  const lower = file.toLowerCase();
  const existing = lowerMap.get(lower);
  if (existing && existing !== file) {
    errors.push(`case-conflict: ${existing} vs ${file}`);
  } else {
    lowerMap.set(lower, file);
  }

  let stats;
  try {
    stats = statSync(resolve(ROOT, file));
  } catch {
    continue;
  }
  if (stats.size > MAX_BYTES) {
    errors.push(
      `large-file (${Math.ceil(stats.size / 1024)} KB > 500 KB): ${file}`,
    );
  }

  if (stats.size === 0 || stats.size > 5 * 1024 * 1024) continue;
  const content = readFileSync(resolve(ROOT, file), "utf-8");
  const startMarker = `<${"<<<<<<"}`;
  const endMarker = `>${">>>>>>"}`;
  if (content.includes(startMarker) || content.includes(endMarker)) {
    errors.push(`merge-conflict marker: ${file}`);
  }
}

if (errors.length > 0) {
  console.error(`\n${errors.length} integrity issue(s) found:\n`);
  for (const error of errors) console.error(`  - ${error}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"integrity-check","failed":${errors.length},"passed":0}`,
  );
  process.exit(1);
}

console.log(`Integrity check passed (${files.length} tracked files).`);
console.log('RIPOSTE_RESULT {"kind":"integrity-check","failed":0,"passed":1}');
