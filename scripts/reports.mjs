/**
 * Shared plumbing for the report runners (`check`, `build`, `verify`): run a
 * command with its output echoed, and write `.reports/<name>/latest.json` +
 * `latest.md`.
 *
 * @see ../docs/reference/tooling.md
 */

import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

export const ROOT = resolve(import.meta.dirname, "..");

/** Run synchronously, echo stdout/stderr, return the exit status (1 if it never started). */
export function runEchoed(command, args, cwd = ROOT) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: process.env,
    shell: false,
  });
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  return result.status ?? 1;
}

/** Persist the report (markdown included in the JSON) and print the markdown. */
export function writeReport(name, report, markdown) {
  const outDir = join(ROOT, ".reports", name);
  mkdirSync(outDir, { recursive: true });
  writeFileSync(
    join(outDir, "latest.json"),
    `${JSON.stringify({ ...report, markdown }, null, 2)}\n`,
  );
  writeFileSync(join(outDir, "latest.md"), markdown);
  console.log(markdown);
}
