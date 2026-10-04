#!/usr/bin/env node

/**
 * Documentation generation hook. Documentation is authored by hand; this
 * validates that the committed documentation registries exist so the doc
 * graph cannot silently lose a surface. No generated contracts yet.
 *
 * @see ../docs/architecture/monorepo.md
 */

import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const REQUIRED = [
  "README.md",
  "AGENTS.md",
  "docs",
  "spec/invariants.md",
  "examples",
  "game/README.md",
  "game/package.json",
  "apps/web/package.json",
];

const missing = REQUIRED.filter((path) => !existsSync(join(ROOT, path)));
if (missing.length > 0) {
  console.error("docs:generate failed — missing documentation registries:");
  for (const path of missing) console.error(`  - ${path}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"docs-generate","failed":${missing.length},"passed":0}`,
  );
  process.exit(1);
}

console.log(
  "Documentation registries present (documentation is authored; no generated contracts yet).",
);
console.log('RIPOSTE_RESULT {"kind":"docs-generate","failed":0,"passed":1}');
