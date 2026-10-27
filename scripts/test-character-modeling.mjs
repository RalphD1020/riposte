#!/usr/bin/env node

/**
 * Character-modeling diagnostics: the pure-Python scanner's unit tests.
 *
 * Synthetic meshes with known defects (step, corner, dent, asymmetry, face
 * ridge exception, crown hollow, joint protrusion, resolution stability).
 * No Blender. Not part of `pnpm test`; `pnpm lint` only runs the profile
 * self-check.
 *
 * Usage: pnpm test:character-modeling
 *
 * @see ../docs/concepts/character-modeling.md
 */

import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const cwd = join(ROOT, "tools", "character_modeling");
const result = spawnSync(
  "python",
  ["-m", "unittest", "discover", "-s", "tests", "-t", "tests", "-v"],
  { cwd, stdio: "inherit" },
);
if (result.error) {
  console.error(`python could not start: ${result.error.message}`);
  process.exit(1);
}
process.exit(result.status ?? 1);
