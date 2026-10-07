#!/usr/bin/env node

/**
 * Validate documentation consistency, in both directions.
 *
 * 1. No markdown under docs/, spec/, examples/ references .impl/
 * 2. Every docs markdown header includes See also: or Source:
 * 3. Every `docs/…md` path and spec invariant anchor cited from code
 *    resolves (code → docs/spec)
 * 4. Every relative markdown link and backticked repository path in
 *    committed markdown exists (docs → code). Tool-managed blocks
 *    (`<!-- BEGIN:x -->` … `<!-- END:x -->`) describe other packages and are skipped.
 *
 * @see ../docs/reference/tooling.md
 * @see ../docs/architecture/monorepo.md
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const errors = [];
const SKIP_DIRS = new Set([
  "node_modules",
  ".godot",
  ".next",
  "out",
  "coverage",
  "dist",
  ".turbo",
]);
const CODE_ROOTS = [
  "game/src",
  "game/content",
  "game/tests",
  "game/tools",
  "game/scripts",
  "apps/web/src",
  "apps/web/scripts",
  "scripts",
];
const CODE_FILE = /\.(gd|ts|tsx|mjs|css)$/;
const MARKDOWN_ROOTS = ["docs", "spec", "examples"];
const MARKDOWN_FILES = ["README.md", "AGENTS.md", "game/README.md"];
const REPO_PATH = /^(?:game|apps|scripts|docs|spec|examples)\/[\w@./-]+$/;
/**
 * Paths docs may name that only exist after a build. They are gitignored
 * artifacts, so requiring them on disk would make the docs gate depend on
 * whether someone had run an export.
 */
const BUILD_OUTPUTS = new Set(["apps/web/public/game"]);

function walk(dir, accept, callback) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, accept, callback);
    } else if (accept.test(entry.name)) {
      callback(
        relative(ROOT, fullPath).replaceAll("\\", "/"),
        readFileSync(fullPath, "utf-8"),
      );
    }
  }
}

function committedMarkdown(callback) {
  for (const dir of MARKDOWN_ROOTS) walk(join(ROOT, dir), /\.md$/, callback);
  for (const file of MARKDOWN_FILES) {
    if (existsSync(join(ROOT, file)))
      callback(file, readFileSync(join(ROOT, file), "utf-8"));
  }
}

function checkNoImplReferences() {
  for (const dir of MARKDOWN_ROOTS) {
    walk(join(ROOT, dir), /\.md$/, (file, content) => {
      if (content.includes(".impl/")) {
        errors.push(
          `${file} references .impl/ which is gitignored. Use docs/, spec/, or examples/ instead.`,
        );
      }
    });
  }
}

function checkDocsHaveCrossRefs() {
  walk(join(ROOT, "docs"), /\.md$/, (file, content) => {
    const firstLines = content.split("\n").slice(0, 15).join("\n");
    if (!firstLines.includes("See also:") && !firstLines.includes("Source:")) {
      errors.push(
        `${file} is missing cross-references in the header. Add "See also:" or "Source:".`,
      );
    }
  });
}

function specAnchors() {
  const spec = readFileSync(join(ROOT, "spec/invariants.md"), "utf-8");
  return new Set(
    [...spec.matchAll(/^###\s+([A-Z0-9-]+)\s*$/gm)].map((match) =>
      match[1].toLowerCase(),
    ),
  );
}

function checkCodeReferences() {
  const anchors = specAnchors();
  for (const root of CODE_ROOTS) {
    walk(join(ROOT, root), CODE_FILE, (file, content) => {
      for (const match of content.matchAll(
        /(?<![\w.-])(docs\/[\w/.-]+?\.md)/g,
      )) {
        if (!existsSync(join(ROOT, match[1])))
          errors.push(`${file} cites missing ${match[1]}`);
      }
      for (const match of content.matchAll(/invariants\.md#([a-z0-9-]+)/g)) {
        if (!anchors.has(match[1]))
          errors.push(`${file} cites missing spec anchor #${match[1]}`);
      }
    });
  }
}

function checkMarkdownTargets() {
  committedMarkdown((file, raw) => {
    const content = raw.replace(
      /<!-- BEGIN:([\w-]+) -->[\s\S]*?<!-- END:\1 -->/g,
      "",
    );
    for (const match of content.matchAll(
      /\]\((?!https?:|mailto:|#)([^)\s#]+)(?:#[^)\s]*)?\)/g,
    )) {
      if (!existsSync(resolve(ROOT, dirname(file), match[1]))) {
        errors.push(`${file} links to missing ${match[1]}`);
      }
    }
    for (const match of content.matchAll(/`([^`\s]+)`/g)) {
      const path = match[1].replace(/\/$/, "");
      if (
        REPO_PATH.test(path) &&
        !BUILD_OUTPUTS.has(path) &&
        !existsSync(join(ROOT, path))
      ) {
        errors.push(`${file} names missing path ${match[1]}`);
      }
    }
  });
}

console.log("Checking documentation consistency...");
checkNoImplReferences();
checkDocsHaveCrossRefs();
checkCodeReferences();
checkMarkdownTargets();

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
