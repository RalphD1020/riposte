#!/usr/bin/env node

/**
 * Enforce the permanent monorepo topology.
 *
 * @see ../docs/architecture/monorepo.md
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import {
  REQUIRED_ARTIFACTS,
  STAGE_DIR,
  exportProblems,
  shellProblems,
} from "./stage-web-game.mjs";

const ROOT = resolve(import.meta.dirname, "..");
const errors = [];
const REQUIRED_GAME_TEST_SCRIPTS = ["typecheck", "test", "test:headless"];
const REQUIRED_GODOT_ATOMIC = [
  "godot:version",
  "godot:import",
  "godot:scripts:check",
  "godot:test",
  "godot:check",
];
const OPTIONAL_GODOT_SCRIPTS = ["dev", "build", "format", "format:check"];

function isGodotBacked(script) {
  return typeof script === "string" && /godot/i.test(script);
}

function isGodotWebServe(script) {
  return (
    typeof script === "string" && /serve-web|dist\/game\/web/i.test(script)
  );
}

function readJson(relativePath) {
  return JSON.parse(readFileSync(join(ROOT, relativePath), "utf-8"));
}

function walkFiles(dir, callback) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (
        entry.name === "node_modules" ||
        entry.name === ".next" ||
        entry.name === "coverage" ||
        entry.name === ".godot" ||
        entry.name === "dist" ||
        entry.name === ".turbo"
      ) {
        continue;
      }
      walkFiles(fullPath, callback);
      continue;
    }
    callback(fullPath, entry.name);
  }
}

function fail(message) {
  errors.push(message);
}

if (!existsSync(join(ROOT, "apps/web"))) fail("apps/web does not exist");
if (!existsSync(join(ROOT, "game"))) fail("game does not exist");

const webPkg = existsSync(join(ROOT, "apps/web/package.json"))
  ? readJson("apps/web/package.json")
  : null;
const gamePkg = existsSync(join(ROOT, "game/package.json"))
  ? readJson("game/package.json")
  : null;
const rootPkg = readJson("package.json");
const workspace = readFileSync(join(ROOT, "pnpm-workspace.yaml"), "utf-8");

if (webPkg?.name !== "@riposte/web") {
  fail(
    `apps/web/package.json name must be @riposte/web (got ${String(webPkg?.name)})`,
  );
}
if (gamePkg?.name !== "@riposte/game") {
  fail(
    `game/package.json name must be @riposte/game (got ${String(gamePkg?.name)})`,
  );
}

for (const entry of ["apps/*", "packages/*", "game"]) {
  // Allow either single or double quotes
  const quoted = [`'${entry}'`, `"${entry}"`, entry];
  if (!quoted.some((q) => workspace.includes(q))) {
    fail(`pnpm-workspace.yaml must include ${entry}`);
  }
}

if (existsSync(join(ROOT, "apps/web/game"))) {
  fail("game must not exist beneath apps/web");
}

walkFiles(join(ROOT, "apps/web"), (fullPath, name) => {
  const rel = relative(ROOT, fullPath).replaceAll("\\", "/");
  if (
    name.endsWith(".gd") ||
    name.endsWith(".tscn") ||
    name.endsWith(".tres") ||
    name === "project.godot"
  ) {
    fail(`${rel} must not live under apps/web`);
  }
});

const gameDeps = {
  ...gamePkg?.dependencies,
  ...gamePkg?.devDependencies,
};
if (gameDeps["@riposte/web"]) {
  fail("@riposte/game must not depend on @riposte/web");
}

const turboOrchestration = ["dev", "lint", "typecheck", "test"];
for (const name of turboOrchestration) {
  const script = rootPkg.scripts?.[name];
  if (typeof script !== "string" || !script.includes("turbo")) {
    fail(`root script "${name}" must use turbo (got ${String(script)})`);
  }
  if (script.includes("@riposte/web") || script.includes("@riposte/game")) {
    fail(`root script "${name}" must not be hardcoded to a package`);
  }
}
if (
  typeof rootPkg.scripts?.check !== "string" ||
  !rootPkg.scripts.check.includes("scripts/check.mjs")
) {
  fail(
    'root script "check" must be the synchronous report runner (scripts/check.mjs)',
  );
}
if (
  typeof rootPkg.scripts?.build !== "string" ||
  !rootPkg.scripts.build.includes("scripts/build.mjs")
) {
  fail('root script "build" must produce artifacts via scripts/build.mjs');
}
if (
  typeof rootPkg.scripts?.verify !== "string" ||
  !rootPkg.scripts.verify.includes("scripts/verify.mjs")
) {
  fail(
    'root script "verify" must be check then test then build (scripts/verify.mjs)',
  );
}

/**
 * Staging the Web export is the one place Next touches Godot output
 * (MONO-001, WEB-004). The dangerous failure is a `/play` that serves a shell
 * and then 404s on the wasm, because that looks like a working deploy — so
 * the fail-closed behaviour is asserted here rather than trusted.
 */
if (
  typeof rootPkg.scripts?.["game:stage:web"] !== "string" ||
  !rootPkg.scripts["game:stage:web"].includes("stage-web-game.mjs")
) {
  fail('root script "game:stage:web" must run scripts/stage-web-game.mjs');
}
const stageRelative = relative(ROOT, STAGE_DIR).replaceAll("\\", "/");
if (!readFileSync(join(ROOT, ".gitignore"), "utf-8").includes(stageRelative)) {
  fail(`${stageRelative} is build output and must be gitignored`);
}
if (exportProblems("", () => false).length !== 1) {
  fail("staging must refuse a missing export with exactly one explanation");
}
for (const missing of REQUIRED_ARTIFACTS) {
  const problems = exportProblems(
    "dist/game/web",
    (path) => !String(path).endsWith(missing),
  );
  if (problems.length !== 1 || !problems[0].includes(missing)) {
    fail(`staging must refuse an export missing ${missing}`);
  }
}
if (shellProblems("<html><body>Riposte</body></html>").length !== 2) {
  fail("staging must refuse a page that is not the engine's own shell");
}
if (shellProblems("Engine GODOT_THREADS_ENABLED = true").length !== 1) {
  fail("WEB-003: staging must refuse a threaded shell");
}
if (shellProblems("Engine GODOT_THREADS_ENABLED = false").length !== 0) {
  fail("staging must accept the real single-threaded shell");
}

const gameScripts = gamePkg?.scripts ?? {};
if (
  typeof gameScripts.lint !== "string" ||
  !gameScripts.lint.includes("lint.mjs")
) {
  fail(
    "game lint must be a source-policy scanner (lint.mjs), not Godot --import",
  );
}
if (/--import|--editor/.test(gameScripts.lint ?? "")) {
  fail("game lint must not run Godot import/editor scan");
}
for (const name of REQUIRED_GAME_TEST_SCRIPTS) {
  if (!isGodotBacked(gameScripts[name])) {
    fail(
      `game/package.json "${name}" must invoke the Godot checker or harness`,
    );
  }
}
if ("test:coverage" in gameScripts) {
  fail(
    "game/package.json must not define test:coverage until it measures GDScript coverage; use test / test:headless for the harness",
  );
}
for (const name of REQUIRED_GODOT_ATOMIC) {
  if (!isGodotBacked(gameScripts[name])) {
    fail(`game/package.json must expose atomic "${name}"`);
  }
}
if (
  typeof gameScripts.check !== "string" ||
  !gameScripts.check.includes("godot.mjs")
) {
  fail(
    "game check must be the ordered Godot runner (version → import → lint → scripts → tooling)",
  );
}
for (const name of OPTIONAL_GODOT_SCRIPTS) {
  if (
    name in gameScripts &&
    name !== "lint" &&
    !isGodotBacked(gameScripts[name])
  ) {
    if (name === "dev" && isGodotWebServe(gameScripts[name])) {
      continue;
    }
    fail(
      `game/package.json "${name}" is a no-op; omit it or implement a real command`,
    );
  }
}

if (errors.length > 0) {
  console.error(`\n${errors.length} architecture issue(s) found:\n`);
  for (const error of errors) console.error(`  - ${error}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"arch-check","failed":${errors.length},"passed":0}`,
  );
  process.exit(1);
}

console.log("Architecture check passed.");
console.log('RIPOSTE_RESULT {"kind":"arch-check","failed":0,"passed":1}');
