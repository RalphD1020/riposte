#!/usr/bin/env node

/**
 * check → test → build. Release/admin command.
 *
 * @see ../docs/reference/tooling.md
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { resolvePnpm } from "./godot-bin.mjs";
import { ROOT, runEchoed, writeReport } from "./reports.mjs";

const started = Date.now();
const PNPM = resolvePnpm();

const runNode = (script) =>
  runEchoed(process.execPath, [join(ROOT, "scripts", script)]) === 0;
const runPnpm = (scriptName) =>
  runEchoed(PNPM.command, [...PNPM.prefix, scriptName]) === 0;
const readReport = (name) => {
  const path = join(ROOT, ".reports", name, "latest.json");
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : null;
};

const checkOk = runNode("check.mjs");
const testOk = checkOk ? runPnpm("test") : false;
const buildOk = testOk ? runNode("build.mjs") : false;
const duration = ((Date.now() - started) / 1000).toFixed(2);
const checkReport = readReport("check");
const buildReport = readReport("build");

const markdown = [
  "# RIPOSTE VERIFY",
  "",
  `CHECK: ${checkOk ? "PASS" : "FAIL"}`,
  `TEST: ${testOk ? "PASS" : checkOk ? "FAIL" : "SKIPPED"}`,
  `BUILD: ${buildOk ? "PASS" : testOk ? "FAIL" : "SKIPPED"}`,
  "",
  `Duration: ${duration}s`,
  checkReport?.environment?.godot
    ? `Godot: ${checkReport.environment.godot.normalized} (${checkReport.environment.godot.source})`
    : "Godot: unresolved",
  "",
  "Source quality: " + (checkOk ? "verified" : "failed"),
  "Behavior: " + (testOk ? "verified" : "not verified"),
  "Artifacts: " + (buildOk ? "produced" : "not produced"),
  "",
  `FINAL: ${checkOk && testOk && buildOk ? "PASS" : "FAIL"}`,
  "",
].join("\n");

writeReport(
  "verify",
  { check: checkOk, test: testOk, build: buildOk, checkReport, buildReport },
  markdown,
);
if (!checkOk || !testOk || !buildOk) process.exit(1);
