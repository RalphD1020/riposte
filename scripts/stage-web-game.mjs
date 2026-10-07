#!/usr/bin/env node

/**
 * Stage the Godot Web export into the Next.js app so `/play` is served from
 * our own origin (WEB-004, WEB-005).
 *
 * Copy, not move, and not a symlink: `dist/game/web/` stays the canonical
 * itch.io artifact, and `apps/web/public/game/` is a second consumer of it.
 *
 * Fail-closed. Staging a missing or half-written export would publish a
 * `/play` that loads a shell and then hangs on a 404 for the wasm, which is
 * the single worst failure this script could allow: it looks like a working
 * deploy. So the export is verified before anything is copied, and the
 * destination is replaced wholesale rather than merged over — a stale
 * `index.pck` beside a fresh `index.wasm` is a crash with no useful message.
 *
 * MONO-001: Next serves these bytes and never owns them. Godot sources
 * (`.gd`, `.tscn`, `.tres`, `project.godot`) still live only in `game/`, no
 * `.gd` is ever copied here, and `apps/web/public/game/` is gitignored build
 * output.
 *
 * @see ../spec/invariants.md#web-004
 * @see ../spec/invariants.md#mono-001
 * @see ../docs/concepts/web.md
 */

import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(import.meta.dirname, "..");
export const EXPORT_DIR = join(ROOT, "dist", "game", "web");
export const STAGE_DIR = join(ROOT, "apps", "web", "public", "game");

/**
 * The files a browser needs before it can run a single frame. A shell on its
 * own is the dangerous case, so every one of these is required.
 */
export const REQUIRED_ARTIFACTS = [
  "index.html",
  "index.js",
  "index.wasm",
  "index.pck",
];

/** Why this export cannot be staged, or an empty list. */
export function exportProblems(dir, exists = existsSync) {
  if (!exists(dir)) {
    return [
      "no Godot Web export to stage: run `pnpm game:export:web` first (dist/game/web/)",
    ];
  }
  return REQUIRED_ARTIFACTS.filter((name) => !exists(join(dir, name))).map(
    (name) => `incomplete Godot Web export: missing dist/game/web/${name}`,
  );
}

/**
 * The staged shell must be the engine's, not a hand-written page that merely
 * resembles it. A page without the engine bootstrap would 200 forever.
 */
export function shellProblems(html) {
  const text = String(html ?? "");
  const problems = [];
  if (!text.includes("Engine")) {
    problems.push("staged index.html is not a Godot shell (no Engine)");
  }
  if (!text.includes("GODOT_THREADS_ENABLED = false")) {
    problems.push(
      "WEB-003: staged index.html must keep GODOT_THREADS_ENABLED = false",
    );
  }
  return problems;
}

export function stage() {
  const problems = exportProblems(EXPORT_DIR);
  if (problems.length > 0) {
    return { ok: false, problems };
  }
  const shell = shellProblems(
    readFileSync(join(EXPORT_DIR, "index.html"), "utf8"),
  );
  if (shell.length > 0) {
    return { ok: false, problems: shell };
  }
  rmSync(STAGE_DIR, { recursive: true, force: true });
  mkdirSync(STAGE_DIR, { recursive: true });
  cpSync(EXPORT_DIR, STAGE_DIR, { recursive: true });
  return { ok: true, problems: [] };
}

/** True when a previous run left a complete, usable artifact in place. */
export function isStaged() {
  return exportProblems(STAGE_DIR).length === 0;
}

/** Importable for reporting; only the direct invocation copies anything. */
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const result = stage();
  if (!result.ok) {
    for (const problem of result.problems) console.error(problem);
    console.log(
      'RIPOSTE_RESULT {"kind":"web-game-stage","status":"FAIL","failed":1,"passed":0}',
    );
    process.exit(1);
  }
  console.log(
    `RIPOSTE_RESULT ${JSON.stringify({
      kind: "web-game-stage",
      status: "PASS",
      failed: 0,
      passed: 1,
      source: "dist/game/web/",
      artifact: "apps/web/public/game/index.html",
      served_at: "/play",
    })}`,
  );
}
