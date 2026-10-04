#!/usr/bin/env node

/**
 * Single Godot binary resolver. GODOT_BIN, then `godot` on PATH.
 * Also owns shared export/harness constants and `webExportPresetProblems`.
 * Does not hardcode machine-local install paths.
 *
 * @see ../docs/reference/tooling.md
 */

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

export const EXPECTED_GODOT_VERSION = "4.7.2.stable";
export const EXPECTED_EXPORT_TEMPLATE_DIR = "4.7.2.stable";
export const WEB_NOTHREADS_RELEASE_TEMPLATE = "web_nothreads_release.zip";
export const WEB_NOTHREADS_DEBUG_TEMPLATE = "web_nothreads_debug.zip";
export const OFFICIAL_EXPORT_TEMPLATES_URL =
  "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz";
export const OFFICIAL_EXPORT_TEMPLATES_SHA512_SUMS_URL =
  "https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt";
export const OFFICIAL_EXPORT_TEMPLATES_SHA512 =
  "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079";
export const OFFICIAL_EXPORT_TEMPLATES_SHA256 =
  "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011";
export const WEB_EXPORT_PRESET_NAME = "Web";
export const HARNESS_FIXED_FPS = 60;
export const WEB_SAFE_AREA_TOKEN = "--riposte-safe-top";
export const WEB_SAFE_AREA_JSON_TOKEN = "riposteSafeAreaJson";

export function which(name) {
  const tool = process.platform === "win32" ? "where" : "which";
  const result = spawnSync(tool, [name], { encoding: "utf8" });
  if (result.status !== 0) return null;
  return (
    (result.stdout || "")
      .split(/\r?\n/)
      .find((line) => line.trim().length > 0) || null
  );
}

export function resolvePnpm() {
  if (process.platform !== "win32") {
    return { command: which("pnpm") || "pnpm", prefix: [] };
  }
  const cmd = which("pnpm.cmd") || which("pnpm");
  if (cmd) {
    const cjs = join(dirname(cmd), "node_modules/pnpm/bin/pnpm.cjs");
    if (existsSync(cjs)) {
      return { command: process.execPath, prefix: [cjs] };
    }
  }
  throw new Error(
    "pnpm not found. Install pnpm 10.x and ensure it is on PATH.",
  );
}

export function resolveGodot() {
  if (process.env.GODOT_BIN) {
    if (!existsSync(process.env.GODOT_BIN)) {
      throw new Error(
        `GODOT_BIN is set but not found: ${process.env.GODOT_BIN}`,
      );
    }
    return { binary: process.env.GODOT_BIN, source: "GODOT_BIN" };
  }
  const found = which("godot") || which("godot.exe");
  if (found && existsSync(found)) {
    return { binary: found, source: "PATH" };
  }
  throw new Error(
    "Godot 4.7.2-stable not found. Put `godot` on PATH or set GODOT_BIN to the 4.7.2-stable editor binary.",
  );
}

export function normalizeGodotVersion(raw) {
  const token = String(raw ?? "")
    .trim()
    .split(/\s+/)[0];
  const match = token.match(/^(\d+\.\d+\.\d+\.stable)/);
  return match ? match[1] : token;
}

export function readGodotVersion(binary) {
  const result = spawnSync(binary, ["--version"], { encoding: "utf8" });
  const text = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  return { raw: text, normalized: normalizeGodotVersion(text) };
}

export function assertGodotVersion(resolved = resolveGodot()) {
  const version = readGodotVersion(resolved.binary);
  if (version.normalized !== EXPECTED_GODOT_VERSION) {
    throw new Error(
      `Godot version mismatch: expected ${EXPECTED_GODOT_VERSION}, got ${version.raw || "(empty)"}`,
    );
  }
  return {
    ...resolved,
    ...version,
    expected: EXPECTED_GODOT_VERSION,
    version_match: true,
  };
}

export function defaultExportTemplatesRoot() {
  if (process.env.GODOT_EXPORT_TEMPLATES_DIR) {
    return process.env.GODOT_EXPORT_TEMPLATES_DIR;
  }
  if (process.platform === "win32") {
    return join(
      process.env.APPDATA || "",
      "Godot",
      "export_templates",
      EXPECTED_EXPORT_TEMPLATE_DIR,
    );
  }
  if (process.platform === "darwin") {
    return join(
      process.env.HOME || "",
      "Library",
      "Application Support",
      "Godot",
      "export_templates",
      EXPECTED_EXPORT_TEMPLATE_DIR,
    );
  }
  return join(
    process.env.HOME || "",
    ".local",
    "share",
    "godot",
    "export_templates",
    EXPECTED_EXPORT_TEMPLATE_DIR,
  );
}

export function resolveExportTemplatesDir(resolved = resolveGodot()) {
  const candidates = [];
  if (process.env.GODOT_EXPORT_TEMPLATES_DIR) {
    candidates.push(process.env.GODOT_EXPORT_TEMPLATES_DIR);
  }
  candidates.push(defaultExportTemplatesRoot());
  const portable = join(
    dirname(resolved.binary),
    "editor_data",
    "export_templates",
    EXPECTED_EXPORT_TEMPLATE_DIR,
  );
  candidates.push(portable);
  for (const dir of candidates) {
    if (dir && existsSync(join(dir, WEB_NOTHREADS_RELEASE_TEMPLATE))) {
      return dir;
    }
  }
  return candidates[0];
}

export function webExportPresetProblems(text) {
  const src = String(text ?? "");
  const problems = [];
  if (
    !new RegExp(`name="${WEB_EXPORT_PRESET_NAME}"`).test(src) ||
    !/platform="Web"/.test(src)
  ) {
    problems.push(
      `export_presets.cfg must define the ${WEB_EXPORT_PRESET_NAME} preset (name and platform)`,
    );
  }
  if (
    !/variant\/thread_support=false/.test(src) ||
    /variant\/thread_support=true/.test(src)
  ) {
    problems.push("export_presets.cfg must keep variant/thread_support=false");
  }
  if (!/dedicated_server=false/.test(src)) {
    problems.push("export_presets.cfg must not export a dedicated server");
  }
  if (!src.includes("index.html")) {
    problems.push("export_presets.cfg export basename must stay index.html");
  }
  if (
    !src.includes(WEB_SAFE_AREA_TOKEN) &&
    !src.includes(WEB_SAFE_AREA_JSON_TOKEN)
  ) {
    problems.push(
      "export_presets.cfg Head Include must publish the safe-area shell",
    );
  }
  if (
    !/vram_texture_compression\/for_mobile=true/.test(src) ||
    /vram_texture_compression\/for_mobile=false/.test(src)
  ) {
    problems.push(
      "export_presets.cfg must enable vram_texture_compression/for_mobile",
    );
  }
  if (!/vram_texture_compression\/for_desktop=true/.test(src)) {
    problems.push(
      "export_presets.cfg must enable vram_texture_compression/for_desktop",
    );
  }
  return problems;
}

export function assertOfficialExportTemplatesDigest(tpzPath) {
  if (!existsSync(tpzPath)) {
    throw new Error(`Official export-template archive is missing: ${tpzPath}`);
  }
  const bytes = readFileSync(tpzPath);
  const sha512 = createHash("sha512").update(bytes).digest("hex");
  if (sha512 !== OFFICIAL_EXPORT_TEMPLATES_SHA512) {
    throw new Error(
      `Official 4.7.2-stable export-template SHA-512 mismatch (expected ${OFFICIAL_EXPORT_TEMPLATES_SHA512}, got ${sha512}). Official digest: ${OFFICIAL_EXPORT_TEMPLATES_SHA512_SUMS_URL}. Delete the archive and retry.`,
    );
  }
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (sha256 !== OFFICIAL_EXPORT_TEMPLATES_SHA256) {
    throw new Error(
      `Official 4.7.2-stable export-template SHA-256 mismatch (expected ${OFFICIAL_EXPORT_TEMPLATES_SHA256}, got ${sha256}). Official digest: ${OFFICIAL_EXPORT_TEMPLATES_SHA512_SUMS_URL}. Delete the archive and retry.`,
    );
  }
  return { sha512, sha256 };
}

export function installedWebExportTemplates(dir) {
  if (!dir) return false;
  const versionPath = join(dir, "version.txt");
  if (!existsSync(join(dir, WEB_NOTHREADS_RELEASE_TEMPLATE))) return false;
  if (!existsSync(join(dir, WEB_NOTHREADS_DEBUG_TEMPLATE))) return false;
  if (!existsSync(versionPath)) return false;
  return (
    readFileSync(versionPath, "utf8").trim() === EXPECTED_EXPORT_TEMPLATE_DIR
  );
}

export function assertWebExportTemplates(resolved = resolveGodot()) {
  const dir = resolveExportTemplatesDir(resolved);
  if (!installedWebExportTemplates(dir)) {
    throw new Error(
      `Godot ${EXPECTED_EXPORT_TEMPLATE_DIR} Web single-thread export templates are missing or not the official 4.7.2-stable release (${WEB_NOTHREADS_RELEASE_TEMPLATE} + ${WEB_NOTHREADS_DEBUG_TEMPLATE} + version.txt). Install with pnpm game:export:templates, then retry.`,
    );
  }
  return {
    dir,
    release: join(dir, WEB_NOTHREADS_RELEASE_TEMPLATE),
    debug: join(dir, WEB_NOTHREADS_DEBUG_TEMPLATE),
    version: EXPECTED_EXPORT_TEMPLATE_DIR,
  };
}

export function parseEngineIssues(text) {
  const errors = [];
  const warnings = [];
  for (const line of String(text ?? "").split(/\r?\n/)) {
    if (
      /^SCRIPT ERROR:/.test(line) ||
      /^ERROR:/.test(line) ||
      /^Parse Error:/.test(line)
    ) {
      errors.push(line);
    } else if (/^WARNING:/.test(line)) {
      warnings.push(line);
    }
  }
  return { errors, warnings };
}

export function parseRiposteResult(text) {
  const matches = String(text ?? "").matchAll(/RIPOSTE_RESULT\s+(\{.*\})/g);
  let last = null;
  for (const match of matches) {
    try {
      last = JSON.parse(match[1]);
    } catch {
      /* keep previous */
    }
  }
  return last;
}

export function godotHarnessFailed(riposte) {
  if (riposte == null || typeof riposte !== "object") {
    return true;
  }
  return (Number(riposte.failed) || 0) > 0 || (Number(riposte.errors) || 0) > 0;
}

export function classifyGodotTestOutcome({ riposte, status, issues } = {}) {
  const engineErrors = issues?.errors ?? [];
  if (riposte == null || typeof riposte !== "object") {
    return "HARNESS_FAILURE";
  }
  if (
    riposte.failure_category === "HARNESS_FAILURE" ||
    riposte.failure_category === "TEST_FAILURE"
  ) {
    return riposte.failure_category;
  }
  if ((Number(riposte.failed) || 0) > 0 || (Number(riposte.errors) || 0) > 0) {
    return "TEST_FAILURE";
  }
  if (engineErrors.length > 0) {
    return "HARNESS_FAILURE";
  }
  if (status !== 0 && status !== null) {
    return "HARNESS_FAILURE";
  }
  return "PASS";
}

export function spawnGodot(args, options = {}) {
  const resolved = options.resolved ?? resolveGodot();
  const timeout = options.timeout ?? 120_000;
  const result = spawnSync(resolved.binary, args, {
    cwd: options.cwd,
    encoding: "utf8",
    env: process.env,
    shell: false,
    timeout,
  });
  const text = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  const timed_out =
    result.error?.code === "ETIMEDOUT" || result.error?.code === "ETIME";
  return { ...result, text, resolved, timed_out };
}
