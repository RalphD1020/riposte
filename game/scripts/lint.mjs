#!/usr/bin/env node

/**
 * Static source-policy lint for @riposte/game. Does not invoke Godot import.
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { webExportPresetProblems } from "../../scripts/godot-bin.mjs";

const GAME_ROOT = join(fileURLToPath(new URL(".", import.meta.url)), "..");
const errors = [];

function walk(dir, callback) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (
      entry.name === ".godot" ||
      entry.name === "coverage" ||
      entry.name.startsWith(".")
    )
      continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, callback);
    else callback(full, entry.name);
  }
}

function gdCodeTokens(line) {
  let out = "";
  let inString = false;
  let quote = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inString) {
      if (ch === "\\") {
        i += 1;
        continue;
      }
      if (ch === quote) inString = false;
      continue;
    }
    if (ch === "#") break;
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }
    out += ch;
  }
  return out;
}

function fail(message) {
  errors.push(message);
}

const project = readFileSync(join(GAME_ROOT, "project.godot"), "utf8");
if (!project.includes('renderer/rendering_method="gl_compatibility"')) {
  fail("project.godot must use Compatibility (gl_compatibility)");
}
if (!project.includes('renderer/rendering_method.mobile="gl_compatibility"')) {
  fail("project.godot mobile renderer must stay Compatibility");
}
if (project.includes("forward_plus") || project.includes('"Mobile"')) {
  fail("project.godot must not select Forward+ or Mobile");
}

const presetsPath = join(GAME_ROOT, "export_presets.cfg");
if (existsSync(presetsPath)) {
  for (const problem of webExportPresetProblems(
    readFileSync(presetsPath, "utf8"),
  )) {
    fail(problem);
  }
}

for (const line of project.split(/\r?\n/)) {
  const match = line.match(/^gdscript\/warnings\/([a-z0-9_]+)=0$/);
  if (match) {
    fail(`project.godot must not ignore GDScript warning ${match[1]}`);
  }
}

/**
 * Zero-tolerance warning suppression policy:
 * No @warning_ignore, warning_ignore_start, or warning_ignore_restore anywhere.
 * No exceptions. No allowlists.
 */
walk(GAME_ROOT, (full, name) => {
  if (!name.endsWith(".gd")) return;
  const rel = relative(GAME_ROOT, full).replaceAll("\\", "/");
  const text = readFileSync(full, "utf8");
  if (
    text.includes("@warning_ignore") ||
    text.includes("warning_ignore_start") ||
    text.includes("warning_ignore_restore")
  ) {
    fail(`${rel} must not use @warning_ignore; fix the warning`);
  }
});

walk(join(GAME_ROOT, "scripts"), (full, name) => {
  if (!name.endsWith(".mjs") && !name.endsWith(".js")) return;
  const text = readFileSync(full, "utf8");
  if (/writeFile\w*\([^)]*global_script_class_cache/.test(text)) {
    fail(
      `${relative(GAME_ROOT, full).replaceAll("\\", "/")} must not generate Godot class cache`,
    );
  }
  if (
    /['"`]C:\\Godot\\/.test(text) ||
    /Godot_v4\.7\.2-stable_win64/.test(text)
  ) {
    fail(
      `${relative(GAME_ROOT, full).replaceAll("\\", "/")} must not hardcode a machine Godot path`,
    );
  }
});

if (errors.length > 0) {
  console.error(`${errors.length} game lint issue(s):`);
  for (const error of errors) console.error(`  - ${error}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"game-lint","failed":${errors.length},"passed":0}`,
  );
  process.exit(1);
}

console.log("Game source lint passed.");
console.log('RIPOSTE_RESULT {"kind":"game-lint","failed":0,"passed":1}');
