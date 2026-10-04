#!/usr/bin/env node

/**
 * Clean-room Godot Web export to dist/game/web/.
 */

import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertGodotVersion,
  assertWebExportTemplates,
  parseEngineIssues,
  resolveGodot,
  spawnGodot,
  webExportPresetProblems,
  WEB_EXPORT_PRESET_NAME,
} from "../../scripts/godot-bin.mjs";

const GAME_ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const ROOT = resolve(GAME_ROOT, "..", "..");
const DIST_WEB = join(ROOT, "dist", "game", "web");
const EXPORT_PATH = join(DIST_WEB, "index.html");

console.log("Riposte Web Export");
console.log("==================");

// Validate Godot version
const godot = assertGodotVersion(resolveGodot());
console.log(`Godot: ${godot.normalized} (${godot.source})`);

// Validate export templates
const templates = assertWebExportTemplates(godot);
console.log(`Export templates: ${templates.dir}`);

// Validate export presets
const presetsPath = join(GAME_ROOT, "export_presets.cfg");
if (!existsSync(presetsPath)) {
  console.error("Missing export_presets.cfg — cannot export.");
  process.exit(1);
}
const presets = readFileSync(presetsPath, "utf8");
const problems = webExportPresetProblems(presets);
if (problems.length > 0) {
  console.error("Export preset problems:");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

// Clean output directory
if (existsSync(DIST_WEB)) {
  rmSync(DIST_WEB, { recursive: true, force: true });
}
mkdirSync(DIST_WEB, { recursive: true });

// Run export
console.log(`Exporting to ${DIST_WEB}...`);
const result = spawnGodot(
  [
    "--headless",
    "--path",
    GAME_ROOT,
    "--export-release",
    WEB_EXPORT_PRESET_NAME,
    EXPORT_PATH,
  ],
  { cwd: GAME_ROOT, resolved: godot, timeout: 300_000 },
);

process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");

const issues = parseEngineIssues(result.text);
if (issues.errors.length > 0 || issues.warnings.length > 0) {
  console.error("Export issues:");
  for (const error of [...issues.errors, ...issues.warnings]) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

if (result.status !== 0) {
  console.error(`Export failed with exit code ${result.status}`);
  process.exit(result.status ?? 1);
}

if (!existsSync(EXPORT_PATH)) {
  console.error(`Export succeeded but ${EXPORT_PATH} not found`);
  process.exit(1);
}

console.log("Export complete.");
console.log(
  `RIPOSTE_RESULT {"kind":"export-web","status":"PASS","path":"${DIST_WEB.replaceAll("\\", "/")}"}`,
);
