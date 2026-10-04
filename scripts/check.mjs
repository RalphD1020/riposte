#!/usr/bin/env node

/**
 * Synchronous non-artifact correctness gate.
 * import → lint → typecheck → docs/arch → tooling. No behavior suites. No release artifacts.
 */

import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  EXPECTED_GODOT_VERSION,
  assertGodotVersion,
  classifyGodotTestOutcome,
  godotHarnessFailed,
  parseEngineIssues,
  parseRiposteResult,
  resolvePnpm,
} from "./godot-bin.mjs";
import { ROOT, writeReport } from "./reports.mjs";

const GAME = join(ROOT, "game");
const PNPM = resolvePnpm();

function nowId() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function stepSlug(name) {
  return String(name)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function spawnStep(name, command, args, cwd) {
  const started = Date.now();
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: process.env,
    shell: false,
  });
  return {
    name,
    command: [command, ...args].join(" "),
    cwd,
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    text: `${result.stdout ?? ""}\n${result.stderr ?? ""}`,
    durationMs: Date.now() - started,
    error: result.error ? String(result.error.message) : null,
  };
}

function classify(step) {
  const issues = parseEngineIssues(step.text);
  const riposte = parseRiposteResult(step.text);
  let ok = step.status === 0 && !step.error && issues.errors.length === 0;
  if (
    step.name.startsWith("Godot") ||
    step.name.includes("harness") ||
    step.name.includes("GDScript")
  ) {
    ok = ok && issues.warnings.length === 0;
  }
  if (riposte != null && godotHarnessFailed(riposte)) {
    ok = false;
  }
  return { ...step, ok, issues, riposte };
}

function firstDiagnostic(step) {
  if (step.error) return step.error;
  if (step.issues.errors[0]) return step.issues.errors[0];
  const failLine = step.text
    .split(/\r?\n/)
    .find((line) => /FAIL|error|Error/.test(line));
  return failLine || `exit ${step.status}`;
}

function likelyCategory(step) {
  if (step.name.includes("Tooling")) return "HARNESS_FAILURE";
  if (step.name.includes("import")) return "Godot import / filesystem scan";
  if (step.name.includes("GDScript") || step.name.includes("typecheck"))
    return "GDScript parse/dependency resolution";
  if (step.name.includes("harness") || step.name.includes("Tests")) {
    return classifyGodotTestOutcome({
      riposte: step.riposte,
      status: step.status,
      issues: step.issues,
    });
  }
  if (step.name.includes("lint")) return "static source policy";
  if (step.name.includes("Docs")) return "documentation consistency";
  if (step.name.includes("Architecture")) return "architecture invariant";
  return "command failed";
}

const runId = nowId();
const logDir = join(ROOT, ".reports", "logs", runId);
mkdirSync(logDir, { recursive: true });
const started = Date.now();
const steps = [];
let godotInfo = null;

function record(step) {
  const classified = classify(step);
  writeFileSync(
    join(logDir, `${stepSlug(classified.name)}.log`),
    classified.text,
  );
  process.stdout.write(classified.stdout);
  process.stderr.write(classified.stderr);
  steps.push(classified);
  return classified;
}

try {
  godotInfo = assertGodotVersion();
  record({
    name: "Environment / Godot version",
    command: `${godotInfo.binary} --version`,
    cwd: GAME,
    status: 0,
    stdout: `${godotInfo.raw}\n`,
    stderr: "",
    text: godotInfo.raw,
    durationMs: 0,
    error: null,
  });
} catch (error) {
  record({
    name: "Environment / Godot version",
    command: "godot --version",
    cwd: GAME,
    status: 1,
    stdout: "",
    stderr: String(error.message),
    text: String(error.message),
    durationMs: 0,
    error: String(error.message),
  });
}

const plan = [
  [
    "Godot import scan",
    process.execPath,
    [join(GAME, "scripts/godot.mjs"), "import"],
    GAME,
  ],
  ["Lint", PNPM.command, [...PNPM.prefix, "lint"], ROOT],
  ["Format check", PNPM.command, [...PNPM.prefix, "format:check"], ROOT],
  ["Typecheck", PNPM.command, [...PNPM.prefix, "typecheck"], ROOT],
  ["Docs", PNPM.command, [...PNPM.prefix, "docs:check"], ROOT],
  ["Architecture", PNPM.command, [...PNPM.prefix, "arch:check"], ROOT],
  ["Integrity", PNPM.command, [...PNPM.prefix, "integrity:check"], ROOT],
  ["Security", PNPM.command, [...PNPM.prefix, "security:check"], ROOT],
  [
    "Tooling / harness gate",
    process.execPath,
    [join(GAME, "scripts/test-exit-propagation.mjs")],
    GAME,
  ],
];

let failedName = null;
if (!steps[0]?.ok) {
  failedName = steps[0].name;
} else {
  for (const [name, command, args, cwd] of plan) {
    const classified = record(spawnStep(name, command, args, cwd));
    if (!classified.ok) {
      failedName = name;
      break;
    }
  }
}

const skipped = failedName
  ? plan
      .map(([name]) => name)
      .filter((name) => !steps.some((step) => step.name === name))
      .map((name) => ({ name, status: "SKIPPED" }))
  : [];

const ok = steps.every((step) => step.ok) && skipped.length === 0;
const duration = ((Date.now() - started) / 1000).toFixed(2);
const failed = steps.find((step) => !step.ok);

const markdownLines = [
  "# Riposte Check Report",
  "",
  `RESULT: ${ok ? "PASS" : "FAIL"}`,
  "",
  `Run ID: ${runId}`,
  `Duration: ${duration}s`,
  "",
  "Environment",
  `- Node: ${process.version}`,
  `- pnpm: ${PNPM.command} ${PNPM.prefix.join(" ")}`.trim(),
  `- Godot expected: ${EXPECTED_GODOT_VERSION}`,
  `- Godot actual: ${godotInfo?.normalized ?? "unresolved"}`,
  `- Godot source: ${godotInfo?.source ?? "none"}`,
  `- Godot binary: ${godotInfo?.binary ?? "none"}`,
  `- Renderer: Compatibility`,
  "",
  "## Summary",
  "",
];

for (const step of steps) {
  markdownLines.push(`${step.ok ? "PASS" : "FAIL"}  ${step.name}`);
  if (step.riposte) {
    markdownLines.push(`      ${JSON.stringify(step.riposte)}`);
  }
  if (!step.ok) {
    markdownLines.push(`      ${firstDiagnostic(step)}`);
  }
}
for (const skip of skipped) {
  markdownLines.push(`SKIP  ${skip.name}`);
}

if (failed) {
  const category = likelyCategory(failed);
  markdownLines.push(
    "",
    "## FAILED STEP",
    failed.name,
    "",
    "Command:",
    failed.command,
    "",
    `Exit code: ${failed.status}`,
    "",
    "Primary diagnostic:",
    firstDiagnostic(failed),
    "",
    "Category:",
    category === "TEST_FAILURE" ? "GAME TEST FAILURE" : category,
    "",
  );
  if (failed.riposte) {
    markdownLines.push(
      "Godot:",
      `${failed.riposte.suites ?? "?"} suites`,
      `${failed.riposte.passed ?? "?"} passed`,
      `${failed.riposte.failed ?? "?"} failed`,
      "",
      "Infrastructure:",
      category === "TEST_FAILURE"
        ? "PASS — harness produced a valid summary and propagated the exit code."
        : "FAIL — missing RIPOSTE_RESULT, parser/runner crash, or tooling gate.",
      "",
    );
  }
  markdownLines.push(
    "Raw log:",
    join(".reports/logs", runId, `${stepSlug(failed.name)}.log`).replaceAll(
      "\\",
      "/",
    ),
    "",
    "Subsequent steps:",
    skipped.length ? "SKIPPED because prerequisite failed." : "none",
  );
}

markdownLines.push("", `FINAL: ${ok ? "PASS" : "FAIL"}`, "");

const report = {
  result: ok ? "PASS" : "FAIL",
  runId,
  durationSec: Number(duration),
  environment: {
    node: process.version,
    godot: godotInfo,
    renderer: "Compatibility",
  },
  steps: steps.map((step) => ({
    name: step.name,
    ok: step.ok,
    status: step.status,
    durationMs: step.durationMs,
    riposte: step.riposte,
    errors: step.issues.errors.length,
    warnings: step.issues.warnings.length,
  })),
  skipped,
};

writeReport("check", report, markdownLines.join("\n"));
if (!ok) process.exit(1);
