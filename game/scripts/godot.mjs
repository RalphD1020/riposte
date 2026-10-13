#!/usr/bin/env node

/**
 * Atomic Godot CLI. Does not generate .godot/global_script_class_cache.cfg
 * by hand; `--import` (the editor scan) owns it.
 *
 * version | import | scripts:check (import + load) | test (gating suites) |
 * test:balance (CPU balance smoke) | test:balance:accept (held-out ladder) |
 * test:balance:audit (tuning-corpus report) | test:contact:ship (contact corpora) |
 * test:focused <area|suite>… | test:changed [files…] (TEST-TIER-001) |
 * test:perf (frame-cost report) | check (no harness)
 *
 * @see ../../docs/reference/tooling.md
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  loadManifest,
  suitesForAreas,
  suitesForFiles,
} from "./suite-select.mjs";
import {
  HARNESS_FIXED_FPS,
  assertGodotVersion,
  classifyGodotTestOutcome,
  godotHarnessFailed,
  parseEngineIssues,
  parseRiposteResult,
  resolveGodot,
  spawnGodot,
  spawnGodotWatched,
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

function runScriptsCheck({ refreshClassCache = true } = {}) {
  // Refresh the global class cache first so newly added `class_name` scripts
  // resolve; a stale cache would make the typecheck verdict meaningless.
  if (refreshClassCache) runImport();
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

// Progress guards, not budgets: a tier is killed only after this long with no
// output, and every case and every CPU duel prints when it finishes. A growing
// corpus never makes a progressing run look hung; a genuine hang is still
// caught. The CPU tiers each run in their own process.
const NO_PROGRESS_MS = 480_000;
const TIERS = {
  gate: { tier: "gate" },
  balance: { tier: "balance" },
  accept: { tier: "accept" },
  ship: { tier: "ship" },
};

// `suites` narrows the run to named suites (RIPOSTE_SUITE). The import is the
// slow, asset-wide step; the selective commands skip it unless asked
// (`--import`, or RIPOSTE_IMPORT=1) — import once per session or after adding
// assets or class_name scripts, not before every run.
async function runTest({ tier, suites = [], skipImport = false } = TIERS.gate) {
  const resolved = resolveGodot();
  if (!skipImport) {
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
  }
  const suiteEnv = suites.length > 0 ? { RIPOSTE_SUITE: suites.join(",") } : {};
  const result = await spawnGodotWatched(
    [
      "--headless",
      "--fixed-fps",
      String(HARNESS_FIXED_FPS),
      "--path",
      GAME_ROOT,
      "res://tests/harness/run_headless.tscn",
    ],
    {
      cwd: GAME_ROOT,
      resolved,
      idleTimeout: NO_PROGRESS_MS,
      env: { ...process.env, RIPOSTE_TIER: tier, ...suiteEnv },
    },
  );
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

const ARGS = process.argv.slice(3);
const wantsImport = () =>
  ARGS.includes("--import") || process.env.RIPOSTE_IMPORT === "1";

function runSelected(suites, what) {
  if (suites.length === 0) {
    console.log(`No suites selected (${what}).`);
    return;
  }
  console.log(`Selected (${what}): ${suites.join(", ")}`);
  return runTest({ ...TIERS.gate, suites, skipImport: !wantsImport() });
}

// The suites owning an area, or named directly: `test:focused contact MOVE`.
function runFocused() {
  const names = ARGS.filter((arg) => !arg.startsWith("--"));
  const { suites, unknown } = suitesForAreas(loadManifest(GAME_ROOT), names);
  if (unknown.length > 0) {
    console.error(`Unknown area or suite: ${unknown.join(", ")}`);
    process.exit(1);
  }
  return runSelected(suites, names.join(" "));
}

// The suites owning what changed: the files given, or the working tree's
// changes against HEAD (staged, unstaged and untracked). Docs select nothing.
function changedFiles() {
  const given = ARGS.filter((arg) => !arg.startsWith("--"));
  if (given.length > 0) return given.map((file) => file.replace(/^game\//, ""));
  const git = (args) =>
    spawnSync("git", args, { cwd: GAME_ROOT, encoding: "utf8" }).stdout ?? "";
  const listed =
    git(["diff", "--name-only", "--relative", "HEAD"]) +
    git(["ls-files", "--others", "--exclude-standard"]);
  return [...new Set(listed.split(/\r?\n/).filter(Boolean))];
}

function runChanged() {
  const files = changedFiles();
  const { suites, unowned } = suitesForFiles(loadManifest(GAME_ROOT), files);
  if (unowned.length > 0) {
    console.error(
      `No owning area in tests/suite_manifest.json: ${unowned.join(", ")}`,
    );
    process.exit(1);
  }
  return runSelected(suites, `${files.length} changed file(s)`);
}

// The frame-cost report (never a gate).
async function runPerf() {
  const result = await spawnGodotWatched(
    [
      "--headless",
      "--path",
      GAME_ROOT,
      "--script",
      "res://tools/perf_report.gd",
    ],
    { cwd: GAME_ROOT, idleTimeout: NO_PROGRESS_MS },
  );
  if (result.status !== 0) process.exit(1);
}

// The tuning corpus is a report, not a tier: a line per duel and the ladder
// table. Nothing in it is asserted, so it fails only on an engine problem or
// a stalled run.
async function runAudit() {
  runImport();
  const result = await spawnGodotWatched(
    [
      "--headless",
      "--path",
      GAME_ROOT,
      "--script",
      "res://tools/balance_report.gd",
      "--",
      "--ladder-only",
    ],
    { cwd: GAME_ROOT, idleTimeout: NO_PROGRESS_MS },
  );
  const issues = parseEngineIssues(result.text);
  if (
    result.status !== 0 ||
    issues.errors.length > 0 ||
    issues.warnings.length > 0
  ) {
    console.error(issues.errors.concat(issues.warnings).join("\n"));
    process.exit(1);
  }
}

function runTooling() {
  runToolingScript("scripts/test-suite-select.mjs");
  runToolingScript("scripts/test-exit-propagation.mjs");
}

function runToolingScript(script) {
  const result = spawnSync(process.execPath, [join(GAME_ROOT, script)], {
    cwd: GAME_ROOT,
    encoding: "utf8",
    env: process.env,
    shell: false,
  });
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
  runScriptsCheck({ refreshClassCache: false });
  runTooling();
}

const commands = {
  version: runVersion,
  import: runImport,
  "scripts:check": () => runScriptsCheck(),
  typecheck: () => runScriptsCheck(),
  test: () => runTest(TIERS.gate),
  "test:headless": () => runTest(TIERS.gate),
  "test:balance": () => runTest(TIERS.balance),
  "test:balance:accept": () => runTest(TIERS.accept),
  "test:balance:audit": runAudit,
  "test:contact:ship": () => runTest(TIERS.ship),
  "test:focused": runFocused,
  "test:changed": runChanged,
  "test:perf": runPerf,
  check: runCheck,
};

if (!commands[COMMAND]) {
  console.error(`Unknown Godot command: ${COMMAND}`);
  process.exit(1);
}

try {
  await commands[COMMAND]();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
