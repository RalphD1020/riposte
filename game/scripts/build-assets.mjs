#!/usr/bin/env node

/**
 * `pnpm game:assets` — rebuild every GLB from its Blender source, validated.
 *
 * Blender resolves from BLENDER_BIN, then `blender` on PATH (no machine-local
 * install paths). `--bootstrap` first regenerates the .blend sources from the
 * code-built bootstrap scripts, which overwrites hand edits; use it only to
 * start over.
 *
 * Generated GLBs are committed, so CI and the Web export never need Blender.
 *
 * @see ../../docs/reference/assets.md
 */

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { which } from "../../scripts/godot-bin.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const tools = join(root, "tools", "blender");

function resolveBlender() {
  if (process.env.BLENDER_BIN) {
    if (!existsSync(process.env.BLENDER_BIN)) {
      throw new Error(
        `BLENDER_BIN is set but not found: ${process.env.BLENDER_BIN}`,
      );
    }
    return process.env.BLENDER_BIN;
  }
  const found = which("blender");
  if (found) return found;
  throw new Error(
    "Blender not found. Set BLENDER_BIN or put `blender` on PATH.",
  );
}

function run(blender, script, extra = []) {
  const result = spawnSync(
    blender,
    ["--background", "--factory-startup", "--python", script, "--", ...extra],
    { stdio: "inherit" },
  );
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const blender = resolveBlender();
if (process.argv.includes("--bootstrap")) {
  for (const [script, variants] of [
    ["build_sword.py", [[], ["--variant", "training"]]],
    ["build_wolf.py", [[], ["--variant", "training"]]],
    ["build_arena.py", [[]]],
  ]) {
    for (const variant of variants) {
      run(blender, join(tools, "bootstrap", script), variant);
    }
  }
}
run(blender, join(tools, "export_assets.py"));
