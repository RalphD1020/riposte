#!/usr/bin/env node

/**
 * Clean generated output and node_modules, then install with the committed lockfile.
 *
 * Does not delete pnpm-lock.yaml. Use `pnpm dependencies:refresh` to resolve a new lockfile.
 *
 * @see ./cleanup-paths.mjs
 * @see ../docs/guides/local-dev.md
 */

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, rmSync } from "node:fs";
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

function walk(dir, onFile, onDir) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIR_NAMES.has(entry.name)) continue;
      onDir(fullPath, entry.name);
      if (entry.name !== "node_modules") walk(fullPath, onFile, onDir);
      continue;
    }
    onFile(fullPath, entry.name);
  }
}

for (const relativePath of GENERATED_PATHS) {
  removePath(relativePath);
}

walk(
  ROOT,
  (fullPath, name) => {
    if (GENERATED_GLOBS.some((glob) => name.endsWith(glob.slice(1)))) {
      rmSync(fullPath, { force: true });
      console.log(
        "Removed",
        fullPath.slice(ROOT.length + 1).replaceAll("\\", "/"),
      );
    }
  },
  (fullPath, name) => {
    if (name === "node_modules") {
      rmSync(fullPath, { recursive: true, force: true });
      console.log(
        "Removed",
        fullPath.slice(ROOT.length + 1).replaceAll("\\", "/"),
      );
    }
  },
);

console.log("Installing with frozen lockfile...");
const result = spawnSync("pnpm", ["install", "--frozen-lockfile"], {
  cwd: ROOT,
  stdio: "inherit",
  shell: true,
});

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
