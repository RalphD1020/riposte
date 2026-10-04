#!/usr/bin/env node

/**
 * Validate documentation consistency.
 *
 * 1. No markdown under docs/, spec/, examples/ references .impl/
 * 2. Every docs markdown header includes See also: or Source:
 *
 * @see ../docs/architecture/monorepo.md
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const errors = [];

function walkMd(dir, callback) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== "node_modules") {
      walkMd(fullPath, callback);
    } else if (entry.name.endsWith(".md")) {
      const content = readFileSync(fullPath, "utf-8");
      callback(relative(ROOT, fullPath).replaceAll("\\", "/"), content);
    }
  }
}

function checkNoImplReferences() {
  for (const dir of ["docs", "spec", "examples"]) {
    walkMd(join(ROOT, dir), (file, content) => {
      if (content.includes(".impl/")) {
        errors.push(
          `${file} references .impl/ which is gitignored. Use docs/, spec/, or examples/ instead.`,
        );
      }
    });
  }
}

function checkDocsHaveCrossRefs() {
  walkMd(join(ROOT, "docs"), (file, content) => {
    const firstLines = content.split("\n").slice(0, 15).join("\n");
    if (!firstLines.includes("See also:") && !firstLines.includes("Source:")) {
      errors.push(
        `${file} is missing cross-references in the header. Add "See also:" or "Source:".`,
      );
    }
  });
}

console.log("Checking documentation consistency...");
checkNoImplReferences();
checkDocsHaveCrossRefs();

if (errors.length > 0) {
  console.error(`\n${errors.length} documentation issue(s) found:\n`);
  for (const error of errors) console.error(`  - ${error}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"docs-check","failed":${errors.length},"passed":0}`,
  );
  process.exit(1);
}

console.log("Documentation check passed.");
console.log('RIPOSTE_RESULT {"kind":"docs-check","failed":0,"passed":1}');
