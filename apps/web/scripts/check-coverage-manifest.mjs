#!/usr/bin/env node

/**
 * COVERAGE-001 manifest completeness check.
 *
 * Verifies that every in-scope production source file appears in the
 * coverage report. Catches the case where a new file is added but no
 * test imports it, causing it to silently disappear from coverage.
 *
 * Usage: node scripts/check-coverage-manifest.mjs
 * Requires: coverage/coverage-final.json (run vitest --coverage first)
 */

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const SRC = join(ROOT, "src");
const COVERAGE_JSON = join(ROOT, "coverage", "coverage-final.json");

const EXCLUDE_PATTERNS = [
  /\.test\.(ts|tsx)$/,
  /\.d\.ts$/,
  /[\\/]test[\\/]/,
  // Pure UI layout/routing - excluded per COVERAGE-001
  /[\\/]app[\\/]layout\.tsx$/,
  /[\\/]app[\\/]page\.tsx$/,
  /[\\/]app[\\/]error\.tsx$/,
  /[\\/]app[\\/]global-error\.tsx$/,
  /[\\/]app[\\/]not-found\.tsx$/,
  /[\\/]app[\\/][^/]+[\\/]page\.tsx$/,
];

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
const extra = coveredFiles.filter((f) => !expectedFiles.includes(f));

if (missing.length > 0) {
  console.error(
    `COVERAGE-001 FAIL: ${missing.length} in-scope file(s) missing from coverage report:`,
  );
  for (const f of missing) {
    console.error(`  - ${relative(ROOT, f)}`);
  }
}

if (extra.length > 0) {
  console.warn(
    `NOTE: ${extra.length} file(s) in coverage report not in expected manifest:`,
  );
  for (const f of extra) {
    console.warn(`  + ${relative(ROOT, f)}`);
  }
}

if (missing.length === 0) {
  console.log(
    `COVERAGE-001 manifest: ${expectedFiles.length} files expected, ${coveredFiles.length} covered. OK.`,
  );
  process.exit(0);
} else {
  process.exit(1);
}
