#!/usr/bin/env node

/**
 * Remove generated build caches. Does not remove node_modules or the lockfile.
 *
 * @see ./cleanup-paths.mjs
 * @see ../docs/guides/local-dev.md
 */

import { rmSync, existsSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import {
  GENERATED_GLOBS,
  GENERATED_PATHS,
  SKIP_DIR_NAMES,
} from "./cleanup-paths.mjs";

const ROOT = resolve(import.meta.dirname, "..");

function removePath(relativePath) {
  const fullPath = join(ROOT, relativePath);
  if (!existsSync(fullPath)) return;
  rmSync(fullPath, { recursive: true, force: true });
  console.log("Removed", relativePath);
}

function walkTsbuildinfo(dir) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIR_NAMES.has(entry.name) || entry.name === "node_modules")
        continue;
      walkTsbuildinfo(fullPath);
      continue;
    }
    if (GENERATED_GLOBS.some((glob) => entry.name.endsWith(glob.slice(1)))) {
      rmSync(fullPath, { force: true });
      console.log(
        "Removed",
        fullPath.slice(ROOT.length + 1).replaceAll("\\", "/"),
      );
    }
  }
}

for (const relativePath of GENERATED_PATHS) {
  removePath(relativePath);
}

walkTsbuildinfo(ROOT);
console.log("Clean complete (lockfile and node_modules preserved).");
