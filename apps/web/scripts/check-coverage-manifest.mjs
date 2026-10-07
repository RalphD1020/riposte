#!/usr/bin/env node

/**
 * COVERAGE-001 manifest completeness check.
 *
 * Three different ways coverage scope can rot, and this catches all three.
 * Vitest's own thresholds catch none of them: a file nothing imports is not
 * a failing file, it is an absent one, and 100% of nothing is 100%.
 *
 *   1. A new in-scope file no test imports. It silently vanishes from the
 *      report instead of failing it.
 *   2. Scope shrinking. The expected set is derived from the tree, so
 *      deleting production code also deletes the expectation that it was
 *      covered. `MINIMUM_SOURCE_FILES` is the floor that makes a real
 *      deletion a deliberate edit rather than a quiet one.
 *   3. Scope escape. Vitest measures `src/**`, so a module placed beside it
 *      is invisible to the coverage run *and* to a walk of `src`. Every
 *      tracked TypeScript file must therefore be under `src/` or be a
 *      package-root config file.
 *
 * Usage: node scripts/check-coverage-manifest.mjs
 * Requires: coverage/coverage-final.json (run vitest --coverage first)
 *
 * See also: ../../../README.md#coverage, ../../../docs/reference/testing.md
 */

import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const SRC = join(ROOT, "src");
const COVERAGE_JSON = join(ROOT, "coverage", "coverage-final.json");

/**
 * Lower bound on in-scope production sources, not a target. Raise it when
 * the product genuinely grows; lowering it is the explicit act of removing
 * code from covered scope, which is exactly what should require a diff
 * somebody reads.
 */
const MINIMUM_SOURCE_FILES = 21;

/** Not production sources: tests, ambient types, and the test harness. */
const EXCLUDE_PATTERNS = [
  /\.test\.(ts|tsx)$/,
  /\.d\.ts$/,
  /(^|[\\/])src[\\/]test[\\/]/,
];

/** TypeScript that legitimately lives outside `src` because Next and Vitest load it directly. */
const ROOT_CONFIG = /^[\w.-]+\.config\.ts$/;

function walkSourceFiles(dir, acc = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSourceFiles(full, acc);
    } else if (entry.isFile() && /\.(ts|tsx)$/.test(entry.name)) {
      const rel = relative(ROOT, full).replaceAll("\\", "/");
      if (!EXCLUDE_PATTERNS.some((p) => p.test(rel))) {
        acc.push(full.replaceAll("\\", "/"));
      }
    }
  }
  return acc;
}

/**
 * Tracked TypeScript, minus anything deleted in the working tree. Git still
 * lists a staged deletion, and a file that is gone is not a scope hole.
 */
function trackedTypeScript() {
  return execFileSync("git", ["ls-files", "*.ts", "*.tsx"], {
    cwd: ROOT,
    encoding: "utf8",
  })
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && existsSync(join(ROOT, line)));
}

const failures = [];

const escaped = trackedTypeScript().filter(
  (rel) => !rel.startsWith("src/") && !ROOT_CONFIG.test(rel),
);
if (escaped.length > 0) {
  failures.push(
    `COVERAGE-001 FAIL: ${escaped.length} tracked TypeScript file(s) outside measured scope (\`src/\`):\n` +
      escaped.map((f) => `  - ${f}`).join("\n"),
  );
}

if (!existsSync(COVERAGE_JSON)) {
  console.error(
    "ERROR: coverage/coverage-final.json not found. Run vitest --coverage first.",
  );
  process.exit(1);
}

const expectedFiles = walkSourceFiles(SRC).sort();
const coverageData = JSON.parse(readFileSync(COVERAGE_JSON, "utf8"));
const coveredFiles = Object.keys(coverageData)
  .map((f) => f.replaceAll("\\", "/"))
  .sort();

const missing = expectedFiles.filter((f) => !coveredFiles.includes(f));
if (missing.length > 0) {
  failures.push(
    `COVERAGE-001 FAIL: ${missing.length} in-scope file(s) missing from coverage report:\n` +
      missing.map((f) => `  - ${relative(ROOT, f)}`).join("\n"),
  );
}

if (expectedFiles.length < MINIMUM_SOURCE_FILES) {
  failures.push(
    `COVERAGE-001 FAIL: ${expectedFiles.length} in-scope file(s), below the floor of ${MINIMUM_SOURCE_FILES}. ` +
      `Coverage scope shrank. If production code was genuinely deleted, lower MINIMUM_SOURCE_FILES in the same commit.`,
  );
}

const extra = coveredFiles.filter((f) => !expectedFiles.includes(f));
if (extra.length > 0) {
  console.warn(
    `NOTE: ${extra.length} file(s) in coverage report not in expected manifest:`,
  );
  for (const f of extra) {
    console.warn(`  + ${relative(ROOT, f)}`);
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log(
  `COVERAGE-001 manifest: ${expectedFiles.length} files expected (floor ${MINIMUM_SOURCE_FILES}), ` +
    `${coveredFiles.length} covered, 0 outside scope. OK.`,
);
