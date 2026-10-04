#!/usr/bin/env node

/**
 * Atomic Godot CLI. Does not generate .godot/global_script_class_cache.cfg.
 *
 * version | import | scripts:check | test | check (no harness)
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  HARNESS_FIXED_FPS,
  assertGodotVersion,
  classifyGodotTestOutcome,
  godotHarnessFailed,
  parseEngineIssues,
  parseRiposteResult,
  resolveGodot,
  spawnGodot,
} from "../../scripts/godot-bin.mjs";

const GAME_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const COMMAND = process.argv[2] ?? "test";

function printAndMaybeFail(result, { failOnWarning = false } = {}) {
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  const issues = parseEngineIssues(result.text);
  if (result.status !== 0 && result.status !== null) {
    process.exit(result.status);
  }
  if (
    issues.errors.length > 0 ||
    (failOnWarning && issues.warnings.length > 0)
  ) {
    console.error(
      issues.errors.concat(failOnWarning ? issues.warnings : []).join("\n"),
    );
    process.exit(1);
  }
  return { issues, riposte: parseRiposteResult(result.text) };
}

function runVersion() {
  const info = assertGodotVersion(resolveGodot());
  console.log(
    `RIPOSTE_RESULT ${JSON.stringify({
      kind: "godot-version",
      resolved_binary: info.binary,
      source: info.source,
      expected: info.expected,
      actual: info.normalized,
      version_match: true,
    })}`,
  );
  return info;
}

function runImport() {
  const resolved = resolveGodot();
  const result = spawnGodot(["--headless", "--path", GAME_ROOT, "--import"], {
    cwd: GAME_ROOT,
    resolved,
  });
  return printAndMaybeFail(result, { failOnWarning: true });
}

function runScriptsCheck() {
  const resolved = resolveGodot();
  const result = spawnGodot(
    [
      "--headless",
      "--path",
      GAME_ROOT,
      "--script",
      "res://tools/check_scripts.gd",
    ],
    { cwd: GAME_ROOT, resolved },
  );
  return printAndMaybeFail(result, { failOnWarning: true });
}

function runTest() {
  const resolved = resolveGodot();
  const importResult = spawnGodot(
    ["--headless", "--path", GAME_ROOT, "--import"],
    {
      cwd: GAME_ROOT,
      resolved,
    },
  );
  if (importResult.status !== 0 && importResult.status !== null) {
    process.stdout.write(importResult.stdout ?? "");
    process.stderr.write(importResult.stderr ?? "");
    process.exit(importResult.status);
  }
  const result = spawnGodot(
    [
      "--headless",
      "--fixed-fps",
      String(HARNESS_FIXED_FPS),
      "--path",
      GAME_ROOT,
      "res://tests/harness/run_headless.tscn",
    ],
    { cwd: GAME_ROOT, resolved, timeout: 240_000 },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  const issues = parseEngineIssues(result.text);
  const riposte = parseRiposteResult(result.text);
  const category = classifyGodotTestOutcome({
    riposte,
    status: result.status,
    issues,
  });
  const dir = join(GAME_ROOT, "coverage");
  mkdirSync(dir, { recursive: true });
  const summary = riposte
    ? `${riposte.passed} passed, ${riposte.failed} failed`
    : "harness completed";
  writeFileSync(join(dir, "godot-harness.txt"), `${summary}\n`);
  const engineProblems = issues.errors.length > 0 || issues.warnings.length > 0;
  if (category !== "PASS" || godotHarnessFailed(riposte) || engineProblems) {
    if (riposte == null) {
      console.error(
        `RIPOSTE_RESULT ${JSON.stringify({
          kind: "godot-test",
          status: "FAIL",
          failure_category: "HARNESS_FAILURE",
          reason: "No RIPOSTE_RESULT produced",
        })}`,
      );
    }
    console.error(`Category: ${category}`);
    if (engineProblems) {
      console.error(issues.errors.concat(issues.warnings).join("\n"));
    }
    process.exit(1);
  }
  return { issues, riposte };
}

function runTooling() {
  const result = spawnSync(
    process.execPath,
    [join(GAME_ROOT, "scripts/test-exit-propagation.mjs")],
    {
      cwd: GAME_ROOT,
      encoding: "utf8",
      env: process.env,
      shell: false,
    },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.status !== 0 && result.status !== null)
    process.exit(result.status);
}

function runLint() {
  const result = spawnSync(
    process.execPath,
    [join(GAME_ROOT, "scripts/lint.mjs")],
    {
      cwd: GAME_ROOT,
      encoding: "utf8",
      env: process.env,
      shell: false,
    },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.status !== 0 && result.status !== null)
    process.exit(result.status);
}

function runCheck() {
  runVersion();
  runImport();
  runLint();
  runScriptsCheck();
  runTooling();
}

const commands = {
  version: runVersion,
  import: runImport,
  "scripts:check": runScriptsCheck,
  typecheck: runScriptsCheck,
  test: runTest,
  "test:headless": runTest,
  check: runCheck,
};

if (!commands[COMMAND]) {
  console.error(`Unknown Godot command: ${COMMAND}`);
  process.exit(1);
}

try {
  commands[COMMAND]();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
