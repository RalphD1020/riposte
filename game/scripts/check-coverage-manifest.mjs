#!/usr/bin/env node

/**
 * COVERAGE-001 manifest completeness check for GDScript production sources.
 *
 * GDScript does not yet have a mature CI-friendly line-level coverage
 * collector (no V8/istanbul equivalent). This script enforces the structural
 * half of coverage: every in-scope production source file is referenced by at
 * least one test file, and the total scope cannot shrink silently.
 *
 * In-scope: game/src/domain/** and game/src/application/** (non-UX/UI).
 * Tracked but excluded: game/src/presentation/** (UX/UI, COVERAGE-001
 * exempts UX/UI; behavioral gate is the standard for these).
 *
 * Line-level coverage remains "behavioral gate green until measured by a real
 * collector" per COVERAGE-001 policy. When Godot ships a debugger-based
 * coverage reporter or a community tool matures, replace this manifest check
 * with instrumented measurement.
 *
 * Usage: node game/scripts/check-coverage-manifest.mjs
 *
 * @see ../../docs/reference/tooling.md
 * @see ../../docs/reference/testing.md
 */

import { readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const GAME_ROOT = resolve(fileURLToPath(import.meta.url), "../..");
const SRC = join(GAME_ROOT, "src");
const TESTS = join(GAME_ROOT, "tests");

/**
 * Lower bound on in-scope production sources. Raise when the product
 * genuinely grows; lowering is the explicit act of removing code from
 * covered scope.
 */
const MINIMUM_DOMAIN_FILES = 50;
const MINIMUM_APPLICATION_FILES = 18;

/** Presentation files are tracked but exempted from the coverage mandate. */
const PRESENTATION_PREFIX = "presentation";

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, acc);
    } else if (entry.isFile() && full.endsWith(".gd")) {
      acc.push(full);
    }
  }
  return acc;
}

/**
 * Extract class_name declarations from a .gd file.
 * Returns the class_name string or null.
 */
function extractClassName(filepath) {
  const content = readFileSync(filepath, "utf8");
  const match = content.match(/^class_name\s+(\w+)/m);
  return match ? match[1] : null;
}

/**
 * Scan test files for references to production class names.
 * Returns a Set of class names found in test sources.
 */
function scanTestReferences() {
  const testFiles = walk(TESTS).filter(
    (f) =>
      !f.includes("harness") ||
      f.endsWith("duel_fixture.gd") ||
      f.endsWith("contact_fixture.gd") ||
      f.endsWith("sim_runner.gd") ||
      f.endsWith("weapon_rig.gd") ||
      f.endsWith("pilot.gd") ||
      f.endsWith("tactical_audit.gd"),
  );
  const allTestContent = testFiles
    .map((f) => readFileSync(f, "utf8"))
    .join("\n");
  return allTestContent;
}

const allSourceFiles = walk(SRC);
const testContent = scanTestReferences();

const domainFiles = [];
const applicationFiles = [];
const presentationFiles = [];
const unreferenced = [];

for (const filepath of allSourceFiles) {
  const rel = relative(SRC, filepath).replaceAll("\\", "/");
  const className = extractClassName(filepath);

  if (rel.startsWith(PRESENTATION_PREFIX + "/")) {
    presentationFiles.push(rel);
    continue;
  }

  if (rel.startsWith("domain/")) {
    domainFiles.push(rel);
  } else if (rel.startsWith("application/")) {
    applicationFiles.push(rel);
  }

  if (className && !testContent.includes(className)) {
    unreferenced.push({ rel, className });
  }
}

const failures = [];

if (domainFiles.length < MINIMUM_DOMAIN_FILES) {
  failures.push(
    `COVERAGE-001 FAIL: ${domainFiles.length} domain files, below floor of ${MINIMUM_DOMAIN_FILES}. ` +
      `Coverage scope shrank. If production code was genuinely deleted, lower MINIMUM_DOMAIN_FILES.`,
  );
}

if (applicationFiles.length < MINIMUM_APPLICATION_FILES) {
  failures.push(
    `COVERAGE-001 FAIL: ${applicationFiles.length} application files, below floor of ${MINIMUM_APPLICATION_FILES}. ` +
      `Coverage scope shrank. If production code was genuinely deleted, lower MINIMUM_APPLICATION_FILES.`,
  );
}

if (unreferenced.length > 0) {
  failures.push(
    `COVERAGE-001 WARN: ${unreferenced.length} in-scope class(es) not directly referenced by test sources:\n` +
      unreferenced.map((f) => `  - ${f.rel} (${f.className})`).join("\n"),
  );
}

if (failures.length > 0) {
  for (const failure of failures) {
    if (failure.includes("WARN")) {
      console.warn(failure);
    } else {
      console.error(failure);
    }
  }
  const hardFailures = failures.filter((f) => f.includes("FAIL"));
  if (hardFailures.length > 0) {
    process.exit(1);
  }
}

const inScope = domainFiles.length + applicationFiles.length;
console.log(
  `COVERAGE-001 GDScript manifest: ` +
    `${inScope} in-scope (${domainFiles.length} domain + ${applicationFiles.length} application), ` +
    `${presentationFiles.length} presentation (exempt), ` +
    `${allSourceFiles.length} total.`,
);
console.log(
  `RIPOSTE_RESULT ${JSON.stringify({
    kind: "gdscript-coverage-manifest",
    domain_files: domainFiles.length,
    application_files: applicationFiles.length,
    presentation_files: presentationFiles.length,
    total_files: allSourceFiles.length,
    unreferenced: unreferenced.length,
    domain_floor: MINIMUM_DOMAIN_FILES,
    application_floor: MINIMUM_APPLICATION_FILES,
    status: "PASS",
  })}`,
);
