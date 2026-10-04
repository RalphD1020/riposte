#!/usr/bin/env node

/**
 * Install the official Godot 4.7.2-stable Web single-thread export templates.
 * Downloads the official `.tpz`, verifies the published SHA-512 plus the pinned
 * SHA-256 of the same bytes, then extracts only the nothreads Web templates.
 *
 * @see ../../scripts/godot-bin.mjs
 * @see ../../docs/reference/tooling.md
 */

import { existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import {
  EXPECTED_EXPORT_TEMPLATE_DIR,
  OFFICIAL_EXPORT_TEMPLATES_URL,
  WEB_NOTHREADS_DEBUG_TEMPLATE,
  WEB_NOTHREADS_RELEASE_TEMPLATE,
  assertOfficialExportTemplatesDigest,
  defaultExportTemplatesRoot,
  installedWebExportTemplates,
} from "../../scripts/godot-bin.mjs";

const NEEDED = [
  `templates/${WEB_NOTHREADS_RELEASE_TEMPLATE}`,
  `templates/${WEB_NOTHREADS_DEBUG_TEMPLATE}`,
  "templates/version.txt",
];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function cacheDir() {
  if (process.platform === "win32") {
    return join(
      process.env.LOCALAPPDATA || "",
      "Godot",
      "export_template_downloads",
    );
  }
  return join(
    process.env.HOME || "",
    ".cache",
    "godot",
    "export_template_downloads",
  );
}

function download(url, dest) {
  mkdirSync(dirname(dest), { recursive: true });
  const curl = process.platform === "win32" ? "curl.exe" : "curl";
  const result = spawnSync(
    curl,
    [
      "-L",
      "--fail",
      "--retry",
      "5",
      "--retry-all-errors",
      "--continue-at",
      "-",
      "--output",
      dest,
      url,
    ],
    { stdio: "inherit", shell: false },
  );
  if (result.status !== 0) {
    fail(`Failed to download official export templates from ${url}`);
  }
}

function extractNeeded(tpz, destDir) {
  mkdirSync(destDir, { recursive: true });
  if (process.platform === "win32") {
    const dest = destDir.replace(/'/g, "''");
    const archive = tpz.replace(/'/g, "''");
    const names = NEEDED.map((name) => `'${name}'`).join(", ");
    const script = `
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $zip = [System.IO.Compression.ZipFile]::OpenRead('${archive}')
      $wanted = @(${names})
      foreach ($entry in $zip.Entries) {
        if ($wanted -contains $entry.FullName) {
          $out = Join-Path '${dest}' $entry.Name
          if (Test-Path $out) { Remove-Item $out -Force }
          [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
        }
      }
      $zip.Dispose()
    `;
    const result = spawnSync(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", script],
      { encoding: "utf8", shell: false },
    );
    process.stdout.write(result.stdout ?? "");
    process.stderr.write(result.stderr ?? "");
    if (result.status !== 0) {
      fail("Failed to extract official Web export templates from the .tpz");
    }
    return;
  }
  const result = spawnSync(
    "unzip",
    ["-o", "-j", tpz, ...NEEDED, "-d", destDir],
    { encoding: "utf8", shell: false },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.status !== 0) {
    fail("Failed to extract official Web export templates from the .tpz");
  }
}

function verifyOrDelete(tpz) {
  try {
    return assertOfficialExportTemplatesDigest(tpz);
  } catch (error) {
    rmSync(tpz, { force: true });
    return fail(error instanceof Error ? error.message : String(error));
  }
}

const destDir = defaultExportTemplatesRoot();
if (installedWebExportTemplates(destDir)) {
  console.log(`Export templates already installed: ${destDir}`);
  process.exit(0);
}

const tpz = join(
  cacheDir(),
  `Godot_v${EXPECTED_EXPORT_TEMPLATE_DIR}_export_templates.tpz`,
);
if (existsSync(tpz)) {
  console.log(
    `Verifying cached official ${EXPECTED_EXPORT_TEMPLATE_DIR} export templates...`,
  );
} else {
  console.log(
    `Downloading official ${EXPECTED_EXPORT_TEMPLATE_DIR} export templates...`,
  );
  download(OFFICIAL_EXPORT_TEMPLATES_URL, tpz);
}
verifyOrDelete(tpz);
extractNeeded(tpz, destDir);
if (!installedWebExportTemplates(destDir)) {
  rmSync(destDir, { recursive: true, force: true });
  fail(
    `Official archive did not install ${WEB_NOTHREADS_RELEASE_TEMPLATE}, ${WEB_NOTHREADS_DEBUG_TEMPLATE}, and version.txt ${EXPECTED_EXPORT_TEMPLATE_DIR}`,
  );
}
console.log(`Installed Web single-thread templates at ${destDir}`);
