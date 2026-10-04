#!/usr/bin/env node

/**
 * Fail-closed, clean-room Godot Web export to `dist/game/web/`.
 * Committed `game/export_presets.cfg` is canonical; this script never invents
 * presets or templates.
 *
 * @see ../../spec/invariants.md#web-003
 * @see ../../spec/invariants.md#web-004
 * @see ../../docs/reference/tooling.md
 */

import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  WEB_EXPORT_PRESET_NAME,
  WEB_SAFE_AREA_JSON_TOKEN,
  WEB_SAFE_AREA_TOKEN,
  assertGodotVersion,
  assertWebExportTemplates,
  parseEngineIssues,
  resolveGodot,
  spawnGodot,
  webExportPresetProblems,
} from "../../scripts/godot-bin.mjs";

const GAME_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = resolve(GAME_ROOT, "..");
const PRESET_PATH = join(GAME_ROOT, "export_presets.cfg");
const ARTIFACT_DIR = join(REPO_ROOT, "dist", "game", "web");
const ARTIFACT_HTML = join(ARTIFACT_DIR, "index.html");
const EXPORT_RELATIVE = "../dist/game/web/index.html";
const REQUIRED_ARTIFACTS = [
  "index.html",
  "index.wasm",
  "index.pck",
  "index.js",
];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function assertPreset() {
  if (!existsSync(PRESET_PATH)) {
    fail("Missing committed game/export_presets.cfg (canonical Web preset).");
  }
  const problems = webExportPresetProblems(readFileSync(PRESET_PATH, "utf8"));
  if (problems.length > 0) {
    fail(problems.join("\n"));
  }
}

function assertArtifacts() {
  for (const name of REQUIRED_ARTIFACTS) {
    if (!existsSync(join(ARTIFACT_DIR, name))) {
      fail(`WEB-004 missing exported artifact: dist/game/web/${name}`);
    }
  }
  const html = readFileSync(ARTIFACT_HTML, "utf8");
  if (
    !html.includes(WEB_SAFE_AREA_TOKEN) &&
    !html.includes(WEB_SAFE_AREA_JSON_TOKEN)
  ) {
    fail(
      "Exported index.html is missing the Head Include safe-area publisher.",
    );
  }
  if (!html.includes("GODOT_THREADS_ENABLED = false")) {
    fail(
      "WEB-003: exported index.html must keep GODOT_THREADS_ENABLED = false.",
    );
  }
}

try {
  const resolved = resolveGodot();
  const godot = assertGodotVersion(resolved);
  assertPreset();
  const templates = assertWebExportTemplates(resolved);
  rmSync(ARTIFACT_DIR, { recursive: true, force: true });
  mkdirSync(ARTIFACT_DIR, { recursive: true });
  const result = spawnGodot(
    [
      "--headless",
      "--path",
      GAME_ROOT,
      "--export-release",
      WEB_EXPORT_PRESET_NAME,
      EXPORT_RELATIVE,
    ],
    { cwd: GAME_ROOT, resolved, timeout: 900_000 },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.timed_out) {
    fail("Godot --export-release timed out.");
  }
  if (result.status !== 0 && result.status !== null) {
    process.exit(result.status);
  }
  const issues = parseEngineIssues(result.text);
  if (issues.errors.length > 0 || issues.warnings.length > 0) {
    console.error(issues.errors.concat(issues.warnings).join("\n"));
    fail("Godot --export-release reported ERROR or WARNING lines.");
  }
  assertArtifacts();
  console.log(
    `RIPOSTE_RESULT ${JSON.stringify({
      kind: "godot-web-export",
      status: "PASS",
      godot: godot.normalized,
      preset: WEB_EXPORT_PRESET_NAME,
      artifact: "dist/game/web/index.html",
      templates: templates.dir,
      thread_support: false,
      vram_mobile: true,
    })}`,
  );
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
