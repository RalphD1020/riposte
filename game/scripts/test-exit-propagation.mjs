#!/usr/bin/env node

/**
 * Tooling gate (TOOL-TEST-001/002/003): failing Godot fixtures MUST make the
 * test gate fail. Runs real Godot processes; not part of `pnpm test`.
 *
 * TOOL-TEST-001 — a FAIL harness result with exit 1 is classified as failure.
 * TOOL-TEST-002 — a SCRIPT ERROR followed by a fake PASS + exit 0 is still a
 *                 failure (engine errors outrank self-reported success).
 * TOOL-TEST-003 — the missing-theme `ERROR:` is dropped only as that exact
 *                 line; any other engine error still fails; unfiltered
 *                 parseEngineIssues still reports it.
 *
 * @see ../../docs/reference/testing.md
 * @see ../../spec/invariants.md#test-truth-001
 */

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  classifyGodotTestOutcome,
  godotHarnessFailed,
  parseEngineIssues,
  unexpectedEngineIssues,
  EXPECTED_TEST_ENGINE_ERROR,
  parseRiposteResult,
  resolveGodot,
  spawnGodot,
} from "../../scripts/godot-bin.mjs";

const GAME_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURE_TIMEOUT_MS = 60_000;

function assert(condition, message) {
  if (!condition) {
    console.error(`TOOL-TEST ${message}`);
    console.log('RIPOSTE_RESULT {"kind":"tool-test","passed":0,"failed":1}');
    process.exit(1);
  }
}

function runFixture(script, resolved) {
  return spawnGodot(["--headless", "--path", GAME_ROOT, "--script", script], {
    cwd: GAME_ROOT,
    resolved,
    timeout: FIXTURE_TIMEOUT_MS,
  });
}

assert(godotHarnessFailed(null), "missing RIPOSTE_RESULT must be a failure");
assert(godotHarnessFailed({ failed: 1, errors: 0 }), "failed>0 must fail");
assert(godotHarnessFailed({ failed: 0, errors: 1 }), "errors>0 must fail");
assert(!godotHarnessFailed({ failed: 0, errors: 0 }), "0/0 must pass");

const resolved = resolveGodot();

const failing = runFixture("res://tests/harness/fail_fixture.gd", resolved);
const failingResult = parseRiposteResult(failing.text);
assert(!failing.timed_out, "TOOL-TEST-001 fixture timed out");
assert(
  (failing.status !== 0 && failing.status !== null) || failing.signal != null,
  `TOOL-TEST-001 fixture exit was ${failing.status} (signal ${failing.signal})`,
);
assert(godotHarnessFailed(failingResult), "TOOL-TEST-001 result not failed");
assert(
  classifyGodotTestOutcome({
    riposte: failingResult,
    status: failing.status,
    issues: parseEngineIssues(failing.text),
  }) === "TEST_FAILURE",
  "TOOL-TEST-001 must classify as TEST_FAILURE",
);

const scriptError = runFixture(
  "res://tests/harness/script_error_fixture.gd",
  resolved,
);
const scriptIssues = parseEngineIssues(scriptError.text);
assert(!scriptError.timed_out, "TOOL-TEST-002 fixture timed out");
assert(
  scriptIssues.errors.length > 0,
  "TOOL-TEST-002 fixture must emit a SCRIPT ERROR",
);
assert(
  classifyGodotTestOutcome({
    riposte: parseRiposteResult(scriptError.text),
    status: scriptError.status,
    issues: scriptIssues,
  }) !== "PASS",
  "TOOL-TEST-002 SCRIPT ERROR must not classify as PASS",
);

const onlyExpected = unexpectedEngineIssues({
  errors: [EXPECTED_TEST_ENGINE_ERROR],
  warnings: [],
});
assert(
  onlyExpected.errors.length === 0,
  "TOOL-TEST-003 must drop only the missing-theme diagnostic",
);
const mixed = unexpectedEngineIssues({
  errors: [EXPECTED_TEST_ENGINE_ERROR, "ERROR: unrelated engine fault"],
  warnings: [],
});
assert(
  mixed.errors.length === 1 &&
    mixed.errors[0] === "ERROR: unrelated engine fault",
  "TOOL-TEST-003 must keep any other ERROR line",
);
assert(
  classifyGodotTestOutcome({
    riposte: { failed: 0, errors: 0, status: "PASS" },
    status: 0,
    issues: mixed,
  }) === "HARNESS_FAILURE",
  "TOOL-TEST-003 an unexpected ERROR must still fail the run",
);
assert(
  classifyGodotTestOutcome({
    riposte: { failed: 0, errors: 0, status: "PASS" },
    status: 0,
    issues: onlyExpected,
  }) === "PASS",
  "TOOL-TEST-003 the expected diagnostic alone must not fail classification",
);
assert(
  classifyGodotTestOutcome({
    riposte: { failed: 0, errors: 0, status: "PASS" },
    status: 0,
    issues: parseEngineIssues(`${EXPECTED_TEST_ENGINE_ERROR}\n`),
  }) === "HARNESS_FAILURE",
  "TOOL-TEST-003 parseEngineIssues must still report the diagnostic",
);

console.log("TOOL-TEST-001 passed");
console.log("TOOL-TEST-002 passed");
console.log("TOOL-TEST-003 passed");
console.log('RIPOSTE_RESULT {"kind":"tool-test","passed":3,"failed":0}');
