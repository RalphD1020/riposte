#!/usr/bin/env node

/**
 * Produce distributable artifacts. Does not rerun check.
 *
 * @see ../docs/reference/tooling.md
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import { resolvePnpm } from "./godot-bin.mjs";
import { ROOT, runEchoed, writeReport } from "./reports.mjs";
import { isStaged } from "./stage-web-game.mjs";

const PNPM = resolvePnpm();
const started = Date.now();

const status = runEchoed(PNPM.command, [
  ...PNPM.prefix,
  "exec",
  "turbo",
  "build",
]);
const ok = status === 0;
const duration = ((Date.now() - started) / 1000).toFixed(2);
const hasExportPreset = existsSync(join(ROOT, "game/export_presets.cfg"));
const staged = isStaged();

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
  "## Staged `/play`",
  staged
    ? "PASS staged artifact at `apps/web/public/game/index.html` (served at `/play`)."
    : "No staged artifact — `/play` falls back to the itch link. Run `pnpm game:export:web && pnpm game:stage:web`.",
  "",
  `FINAL: ${ok ? "PASS" : "FAIL"}`,
  "",
].join("\n");

writeReport(
  "build",
  {
    result: ok ? "PASS" : "FAIL",
    durationSec: Number(duration),
    web: { artifact: "apps/web/.next/", ok },
    godot: { skipped: true, export_presets: hasExportPreset },
    play: { staged, artifact: "apps/web/public/game/index.html" },
  },
  markdown,
);
if (!ok) process.exit(status);
