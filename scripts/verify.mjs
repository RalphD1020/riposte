#!/usr/bin/env node

/**
 * check → test → build. Release/admin command.
 */

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { resolvePnpm } from "./godot-bin.mjs";

const ROOT = resolve(import.meta.dirname, "..");
const started = Date.now();
const PNPM = resolvePnpm();

function runNode(script) {
  const result = spawnSync(process.execPath, [join(ROOT, "scripts", script)], {
    cwd: ROOT,
    encoding: "utf8",
    env: process.env,
    shell: false,
  });
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  return result.status === 0;
}

function runPnpm(scriptName) {
  const result = spawnSync(PNPM.command, [...PNPM.prefix, scriptName], {
    cwd: ROOT,
    encoding: "utf8",
    env: process.env,
    shell: false,
  });
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  return result.status === 0;
}

const checkOk = runNode("check.mjs");
const testOk = checkOk ? runPnpm("test") : false;
const buildOk = testOk ? runNode("build.mjs") : false;
const duration = ((Date.now() - started) / 1000).toFixed(2);
const checkReport = existsSync(join(ROOT, ".reports/check/latest.json"))
  ? JSON.parse(readFileSync(join(ROOT, ".reports/check/latest.json"), "utf8"))
  : null;
const buildReport = existsSync(join(ROOT, ".reports/build/latest.json"))
  ? JSON.parse(readFileSync(join(ROOT, ".reports/build/latest.json"), "utf8"))
  : null;

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

const outDir = join(ROOT, ".reports", "verify");
mkdirSync(outDir, { recursive: true });
writeFileSync(
  join(outDir, "latest.json"),
  `${JSON.stringify({ check: checkOk, test: testOk, build: buildOk, checkReport, buildReport, markdown }, null, 2)}\n`,
);
writeFileSync(join(outDir, "latest.md"), markdown);
console.log(markdown);
if (!checkOk || !testOk || !buildOk) process.exit(1);
