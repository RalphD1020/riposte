#!/usr/bin/env node

/**
 * Produce distributable artifacts. Does not rerun check.
 */

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { resolvePnpm } from "./godot-bin.mjs";

const ROOT = resolve(import.meta.dirname, "..");
const PNPM = resolvePnpm();
const started = Date.now();

const result = spawnSync(
  PNPM.command,
  [...PNPM.prefix, "exec", "turbo", "build"],
  {
    cwd: ROOT,
    encoding: "utf8",
    env: process.env,
    shell: false,
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");

const ok = result.status === 0;
const duration = ((Date.now() - started) / 1000).toFixed(2);
const hasExportPreset = existsSync(join(ROOT, "game/export_presets.cfg"));

const markdown = [
  "# Riposte Build Report",
  "",
  `RESULT: ${ok ? "PASS" : "FAIL"}`,
  "",
  "Source check:",
  "not run by `build`",
  "use `pnpm verify` for check + build",
  "",
  "## Web",
  ok ? "PASS Next.js production build" : "FAIL Next.js production build",
  "artifact: apps/web/.next/",
  `duration: ${duration}s`,
  "",
  "## Godot",
  "Godot Web artifact is `pnpm game:export:web` (clean-room `dist/game/web/`, not part of site `build`).",
  hasExportPreset
    ? "Committed `game/export_presets.cfg` is present."
    : "Missing `game/export_presets.cfg` — export will fail closed.",
  "",
  `FINAL: ${ok ? "PASS" : "FAIL"}`,
  "",
].join("\n");

const report = {
  result: ok ? "PASS" : "FAIL",
  durationSec: Number(duration),
  web: { artifact: "apps/web/.next/", ok },
  godot: { skipped: true, export_presets: hasExportPreset },
  markdown,
};

const outDir = join(ROOT, ".reports", "build");
mkdirSync(outDir, { recursive: true });
writeFileSync(
  join(outDir, "latest.json"),
  `${JSON.stringify(report, null, 2)}\n`,
);
writeFileSync(join(outDir, "latest.md"), markdown);
console.log(markdown);
if (!ok) process.exit(result.status === null ? 1 : result.status);
