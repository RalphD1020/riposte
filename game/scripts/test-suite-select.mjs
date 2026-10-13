#!/usr/bin/env node

/**
 * Tooling gate (TEST-TIER-001): `test:changed` and `test:focused` select what
 * the manifest says, against the real manifest. Runs in `test:tooling`.
 *
 * @see ../../docs/reference/testing.md
 */

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadManifest,
  suitesForAreas,
  suitesForFiles,
} from "./suite-select.mjs";

const GAME_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = loadManifest(GAME_ROOT);

function assert(condition, message) {
  if (!condition) {
    console.error(`TOOL-TEST ${message}`);
    console.log('RIPOSTE_RESULT {"kind":"tool-test","passed":0,"failed":1}');
    process.exit(1);
  }
}

const movement = suitesForFiles(manifest, [
  "src/domain/combat/movement_system.gd",
]);
assert(
  movement.suites.includes("MOVE") && movement.suites.includes("MOTION-COMMIT"),
  "a footwork change selects its owners",
);
assert(
  !movement.suites.includes("FULL-E2E") &&
    !movement.suites.includes("CPU-BALANCE"),
  "and never the broad or statistical suites",
);
const testOnly = suitesForFiles(manifest, ["tests/domain/test_friction.gd"]);
assert(
  testOnly.suites.length === 1 && testOnly.suites[0] === "FRICTION",
  "a changed test runs only its own suite",
);
const docs = suitesForFiles(manifest, ["../docs/concepts/combat.md"]);
assert(
  docs.suites.length === 0 && docs.unowned.length === 0,
  "a docs change runs no suite",
);
const stray = suitesForFiles(manifest, ["src/nowhere/new_system.gd"]);
assert(
  stray.unowned.includes("src/nowhere/new_system.gd"),
  "an unowned production file is reported, never silently skipped",
);
const fast = suitesForAreas(manifest, ["fast"]);
assert(
  fast.suites.includes("MATH") && !fast.suites.includes("REPLAY"),
  "the fast area is the fast-size suites",
);
const named = suitesForAreas(manifest, ["contact", "REPLAY", "nonsense"]);
assert(
  named.suites.includes("FRICTION") &&
    named.suites.includes("REPLAY") &&
    named.unknown.includes("nonsense"),
  "areas and suite names both select, and unknown names are reported",
);
console.log('RIPOSTE_RESULT {"kind":"tool-test","passed":6,"failed":0}');
