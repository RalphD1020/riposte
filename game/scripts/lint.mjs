#!/usr/bin/env node

/**
 * Static source-policy lint for @riposte/game. Does not invoke Godot import.
 *
 * Rules:
 * - WEB-001 Compatibility renderer; warnings never downgraded to ignore.
 * - WEB-003/004 committed Web export preset is present and valid.
 * - ZERO-TOLERANCE-001 no @warning_ignore anywhere.
 * - SIM-PURITY-001 `src/domain` + `content/rules` are deterministic and
 *   engine-independent: no scene types, no float32 engine vectors, no engine
 *   singletons, no platform-libm math (use SimMath), no randomness outside
 *   SeededRng, no output, no signals, no await.
 * - PRES-001 `src/presentation` never drives the simulation, never names an
 *   application class, and contains no content identities (kits own
 *   identity). Layer bans are derived from each layer's `class_name`s.
 * - TEST-TRUTH-001 no release `assert()`, no vacuous test assertions.
 * - DuelEvent payloads are read and written through DuelEventKeys (src + tests).
 * Rules with `strings: true` see string literals; comments are always ignored.
 *
 * @see ../../spec/invariants.md
 * @see ../../docs/reference/godot.md
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

/**
 * Code portion of a GDScript line: `#` comments removed, and string literals
 * removed too unless `keepStrings` (for rules about literal values).
 */
function gdCode(line, keepStrings = false) {
  let out = "";
  let inString = false;
  let quote = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inString) {
      if (keepStrings) out += ch;
      if (ch === "\\") {
        if (keepStrings && i + 1 < line.length) out += line[i + 1];
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
      if (keepStrings) out += ch;
      continue;
    }
    out += ch;
  }
  return out;
}

function fail(message) {
  errors.push(message);
}

function relPath(full) {
  return relative(GAME_ROOT, full).replaceAll("\\", "/");
}

/** `class_name` declarations of every .gd file under `dir`. */
function classNamesIn(dir) {
  const names = [];
  walk(join(GAME_ROOT, dir), (full, name) => {
    if (!name.endsWith(".gd")) return;
    const match = /^class_name\s+(\w+)/m.exec(readFileSync(full, "utf8"));
    if (match) names.push(match[1]);
  });
  return names;
}

/** A rule banning any of `names` (derived from a layer, so it never goes stale). */
function layerRule(id, names, reason) {
  return {
    id,
    pattern: names.length > 0 ? new RegExp(`\\b(${names.join("|")})\\b`) : /$^/,
    reason,
  };
}

/**
 * Apply `rules` ({ id, pattern, reason, strings? }) to every code line of .gd
 * files under `dir`. `strings: true` rules also see string literals.
 */
function scanCode(dir, rules, { allow = new Set() } = {}) {
  walk(join(GAME_ROOT, dir), (full, name) => {
    if (!name.endsWith(".gd")) return;
    const rel = relPath(full);
    const lines = readFileSync(full, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i += 1) {
      const code = gdCode(lines[i]);
      const literal = gdCode(lines[i], true);
      for (const rule of rules) {
        if (allow.has(`${rel}:${rule.id}`)) continue;
        if (rule.pattern.test(rule.strings ? literal : code)) {
          fail(`${rel}:${i + 1} ${rule.reason}`);
        }
      }
    }
  });
}

// --- project.godot -----------------------------------------------------------
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
if (!project.includes("pointing/emulate_mouse_from_touch=false")) {
  fail(
    "project.godot must disable mouse emulation from touch (one input owner)",
  );
}
for (const line of project.split(/\r?\n/)) {
  const match = line.match(/^gdscript\/warnings\/([a-z0-9_]+)=([01])$/);
  if (match) {
    fail(
      `project.godot must keep GDScript warning ${match[1]} as an error (=2)`,
    );
  }
}

// --- export preset (WEB-003 / WEB-004) ---------------------------------------
const presetsPath = join(GAME_ROOT, "export_presets.cfg");
if (!existsSync(presetsPath)) {
  fail("export_presets.cfg is required committed Web export configuration");
} else {
  for (const problem of webExportPresetProblems(
    readFileSync(presetsPath, "utf8"),
  )) {
    fail(problem);
  }
}

// --- ZERO-TOLERANCE-001 ------------------------------------------------------
walk(GAME_ROOT, (full, name) => {
  if (!name.endsWith(".gd")) return;
  const text = readFileSync(full, "utf8");
  if (
    text.includes("@warning_ignore") ||
    text.includes("warning_ignore_start") ||
    text.includes("warning_ignore_restore")
  ) {
    fail(`${relPath(full)} must not use @warning_ignore; fix the warning`);
  }
});

// --- SIM-PURITY-001 ----------------------------------------------------------
const ENGINE_MATH =
  /(?<![\w.])(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|pow|exp|log|lerp|lerpf|lerp_angle|inverse_lerp|remap|smoothstep|move_toward|fmod|fposmod|snapped|snappedf|ease)\(/;
const GLOBAL_RANDOM =
  /(?<![\w.])(randf|randi|randf_range|randi_range|randfn|randomize|rand_from_seed)\(/;
const SIM_RULES = [
  {
    id: "scene",
    pattern:
      /\b(Node|Node2D|Node3D|Control|CanvasItem|Camera2D|Camera3D|MeshInstance3D|Skeleton3D|AnimationPlayer|AnimationTree|SceneTree|PackedScene|Resource|Viewport)\b/,
    reason: "simulation must not use engine scene types",
  },
  {
    id: "vector",
    pattern:
      /\b(Vector2|Vector2i|Vector3|Vector3i|Transform2D|Transform3D|Basis|Quaternion|Rect2|Rect2i)\b/,
    reason:
      "simulation must not use float32 engine vectors; use scalar float fields",
  },
  {
    id: "singleton",
    pattern:
      /\b(Time|OS|Engine|Input|DisplayServer|ProjectSettings|ResourceLoader|FileAccess|DirAccess)\./,
    reason: "simulation must not read engine singletons",
  },
  {
    id: "math",
    pattern: ENGINE_MATH,
    reason: "simulation must use SimMath, not platform libm / C++ math helpers",
  },
  {
    id: "random",
    pattern: GLOBAL_RANDOM,
    reason: "simulation randomness must come from SeededRng",
  },
  {
    id: "rng",
    pattern: /\bRandomNumberGenerator\b/,
    reason: "only SeededRng may wrap RandomNumberGenerator",
  },
  {
    id: "output",
    pattern:
      /(?<![\w.])(print|prints|printt|printerr|printraw|print_debug|push_error|push_warning)\(/,
    reason: "simulation must not log; return results instead",
  },
  {
    id: "signal",
    pattern: /\bsignal\b|\.emit\(/,
    reason: "simulation must not use signals; events are returned values",
  },
  {
    id: "await",
    pattern: /\bawait\b/,
    reason: "simulation must be synchronous",
  },
  {
    id: "layer",
    pattern:
      /\b(MatchSession|RiposteApp|RiposteTheme|MatchPresenter|PresentationKit|CpuController|PlayerSettings|FixedTickDriver)\b/,
    reason: "simulation must not depend on application or presentation",
  },
];
const APPLICATION_CLASSES = [
  ...classNamesIn("src/application"),
  ...classNamesIn("src/main"),
];
const PRESENTATION_CLASSES = classNamesIn("src/presentation");
SIM_RULES.push(
  layerRule(
    "upward",
    [...APPLICATION_CLASSES, ...PRESENTATION_CLASSES],
    "simulation must not depend on application or presentation (SIM-001)",
  ),
);
const SIM_ALLOW = new Set(["src/domain/rng/seeded_rng.gd:rng"]);
scanCode("src/domain", SIM_RULES, { allow: SIM_ALLOW });
scanCode("content/rules", SIM_RULES);

// --- PRES-001 ----------------------------------------------------------------
scanCode("src/presentation", [
  {
    id: "driver",
    pattern:
      /\b(DuelSimulation|MatchSession|PlayerSettings|CpuController|FixedTickDriver|RiposteApp)\b/,
    reason:
      "presentation consumes snapshots and events; it never drives the simulation",
  },
  {
    id: "identity",
    pattern: /bastard|duelist/i,
    strings: true,
    reason:
      "generic presentation must not name content identities; resolve kits instead",
  },
  layerRule(
    "upward",
    APPLICATION_CLASSES,
    "presentation must not depend on the application layer; take values, emit intents (PRES-001)",
  ),
]);

// --- Whole-source rules ------------------------------------------------------
scanCode("src", [
  {
    id: "random",
    pattern: GLOBAL_RANDOM,
    reason:
      "use an explicit RandomNumberGenerator / SeededRng, never global randomness",
  },
  {
    id: "assert",
    pattern: /(?<![\w.])assert\(/,
    reason:
      "assert() is stripped from release builds; use explicit branches (TEST-TRUTH-001)",
  },
  {
    id: "mobile",
    pattern: /OS\.has_feature\(\s*["']mobile["']\s*\)/,
    strings: true,
    reason:
      'Web-mobile detection must use web_android / web_ios, not OS.has_feature("mobile")',
  },
]);

// --- Event payload keys (DuelEventKeys) --------------------------------------
const PAYLOAD_RULES = [
  {
    id: "payload-read",
    pattern: /\.(number|text)\(\s*["']/,
    strings: true,
    reason:
      "read DuelEvent payloads through DuelEventKeys, not string literals",
  },
  {
    id: "payload-write",
    pattern: /DuelEvent\.create\(.*\{\s*["']/,
    strings: true,
    reason: "key DuelEvent payloads with DuelEventKeys, not string literals",
  },
];
scanCode("src", PAYLOAD_RULES);
scanCode("tests", PAYLOAD_RULES);

// --- TEST-TRUTH-001 ----------------------------------------------------------
walk(join(GAME_ROOT, "tests"), (full, name) => {
  if (!name.endsWith(".gd")) return;
  const rel = relPath(full);
  const lines = readFileSync(full, "utf8").split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i];
    const code = gdCode(raw);
    if (
      /assert_true\(\s*true\b/.test(code) ||
      /assert_false\(\s*false\b/.test(code)
    ) {
      fail(`${rel}:${i + 1} vacuous tautological assertion`);
    }
    if (/^\s*#\s*assert_/.test(raw)) {
      fail(`${rel}:${i + 1} commented-out assertion`);
    }
    if (
      /(?<![\w.])(skip|pending)\(/.test(code) ||
      /^\s*return\b.*#.*\bskip/i.test(raw)
    ) {
      fail(`${rel}:${i + 1} skipped test`);
    }
    if (/Engine\.time_scale\s*=/.test(code)) {
      fail(`${rel}:${i + 1} tests must keep Engine.time_scale == 1`);
    }
  }
});

// --- Node tooling ------------------------------------------------------------
walk(join(GAME_ROOT, "scripts"), (full, name) => {
  if (!name.endsWith(".mjs") && !name.endsWith(".js")) return;
  const text = readFileSync(full, "utf8");
  if (/writeFile\w*\([^)]*global_script_class_cache/.test(text)) {
    fail(`${relPath(full)} must not generate Godot class cache`);
  }
  if (
    /['"`]C:\\Godot\\/.test(text) ||
    /Godot_v4\.7\.2-stable_win64/.test(text)
  ) {
    fail(`${relPath(full)} must not hardcode a machine Godot path`);
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
