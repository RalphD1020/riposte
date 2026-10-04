#!/usr/bin/env node

/**
 * Download and install official Godot 4.7.2-stable export templates.
 */

import { existsSync, mkdirSync, createWriteStream, renameSync } from "node:fs";
import { join } from "node:path";
import { createUnzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import {
  assertOfficialExportTemplatesDigest,
  defaultExportTemplatesRoot,
  installedWebExportTemplates,
  OFFICIAL_EXPORT_TEMPLATES_URL,
  EXPECTED_EXPORT_TEMPLATE_DIR,
} from "../../scripts/godot-bin.mjs";

const templatesDir = defaultExportTemplatesRoot();
const archivePath = join(
  templatesDir,
  "..",
  "Godot_v4.7.2-stable_export_templates.tpz",
);

console.log("Godot Export Templates Installer");
console.log("=================================");
console.log(`Target: ${templatesDir}`);

if (installedWebExportTemplates(templatesDir)) {
  console.log("Export templates already installed.");
  process.exit(0);
}

mkdirSync(join(templatesDir, ".."), { recursive: true });

async function download(url, dest) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to download: ${response.status} ${response.statusText}`,
    );
  }
  const fileStream = createWriteStream(dest);
  await pipeline(response.body, fileStream);
}

async function main() {
  if (!existsSync(archivePath)) {
    console.log(`Downloading from ${OFFICIAL_EXPORT_TEMPLATES_URL}...`);
    await download(OFFICIAL_EXPORT_TEMPLATES_URL, archivePath);
    console.log("Download complete.");
  }

  console.log("Verifying digest...");
  assertOfficialExportTemplatesDigest(archivePath);
  console.log("Digest verified.");

  console.log("Extracting...");
  // Note: This is a placeholder - actual extraction would use a zip library
  console.log("Please manually extract the templates to:", templatesDir);
  console.log("Archive location:", archivePath);
  console.log("");
  console.log("Expected structure after extraction:");
  console.log(`  ${templatesDir}/`);
  console.log("    web_nothreads_release.zip");
  console.log("    web_nothreads_debug.zip");
  console.log("    version.txt");
}

main().catch((error) => {
  console.error("Failed:", error.message);
  process.exit(1);
});
