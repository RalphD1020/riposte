#!/usr/bin/env node

/**
 * Secret and gitignore contract.
 *
 * @see ../docs/architecture/SECURITY.md
 */

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const errors = [];

const gitignore = readFileSync(resolve(ROOT, ".gitignore"), "utf-8");
const requiredIgnore = [
  ".env",
  ".impl",
  "*.pem",
  "game/.godot/",
  "**/.godot/export_credentials.cfg",
];

for (const pattern of requiredIgnore) {
  if (!gitignore.includes(pattern)) {
    errors.push(`.gitignore must contain ${pattern}`);
  }
}

const tracked = spawnSync("git", ["ls-files", "-z"], {
  cwd: ROOT,
  encoding: "utf-8",
});

if (tracked.status !== 0) {
  console.error("security:check failed — git ls-files");
  process.exit(tracked.status ?? 1);
}

const files = tracked.stdout.split("\0").filter(Boolean);
const pemBlock = /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/;
const awsKey = /AKIA[0-9A-Z]{16}/;

for (const file of files) {
  const name = basename(file);
  const normalized = file.replaceAll("\\", "/");

  if (normalized.endsWith(".godot/export_credentials.cfg")) {
    errors.push(`tracked Godot export credentials: ${normalized}`);
  }
  if (name.endsWith(".pem")) {
    errors.push(`tracked PEM: ${normalized}`);
  }
  if (name.startsWith(".env") && name !== ".env.example") {
    errors.push(`tracked env file: ${normalized}`);
  }

  let content;
  try {
    content = readFileSync(resolve(ROOT, file), "utf-8");
  } catch {
    continue;
  }
  if (pemBlock.test(content)) {
    errors.push(`private key material: ${normalized}`);
  }
  if (awsKey.test(content)) {
    errors.push(`AWS access key pattern: ${normalized}`);
  }
}

if (errors.length > 0) {
  console.error(`\n${errors.length} security issue(s) found:\n`);
  for (const error of errors) console.error(`  - ${error}`);
  console.log(
    `RIPOSTE_RESULT {"kind":"security-check","failed":${errors.length},"passed":0}`,
  );
  process.exit(1);
}

console.log("Security check passed.");
console.log('RIPOSTE_RESULT {"kind":"security-check","failed":0,"passed":1}');
