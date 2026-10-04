#!/usr/bin/env node

/**
 * Kill localhost dev servers and leftover listeners.
 *
 * Targets processes listening on common Riposte ports:
 *   3000 (next dev), 3001 (next fallback), 8060 (local Godot Web serve)
 *
 * Cross-platform: uses `netstat` + `taskkill` on Windows,
 * `lsof` + `kill` on macOS/Linux.
 *
 * Recovery only — never required for normal shutdown (Ctrl+C).
 *
 * Usage: pnpm kill
 *
 * @see ../docs/guides/local-dev.md
 */

import { execSync } from "node:child_process";

const PORTS = [3000, 3001, 8060];
const isWindows = process.platform === "win32";

let killed = 0;

for (const port of PORTS) {
  try {
    if (isWindows) {
      const output = execSync(
        `netstat -ano | findstr :${port} | findstr LISTENING`,
        {
          encoding: "utf-8",
          stdio: ["pipe", "pipe", "pipe"],
        },
      );
      const pids = new Set(
        output
          .split("\n")
          .map((line) => line.trim().split(/\s+/).pop())
          .filter((pid) => pid && /^\d+$/.test(pid)),
      );
      for (const pid of pids) {
        try {
          execSync(`taskkill /PID ${pid} /F`, { stdio: "pipe" });
          console.log(`Killed PID ${pid} on port ${port}`);
          killed++;
        } catch {
          // Process may have already exited
        }
      }
    } else {
      const output = execSync(`lsof -ti :${port}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      });
      const pids = output.trim().split("\n").filter(Boolean);
      for (const pid of pids) {
        try {
          execSync(`kill -9 ${pid}`, { stdio: "pipe" });
          console.log(`Killed PID ${pid} on port ${port}`);
          killed++;
        } catch {
          // Process may have already exited
        }
      }
    }
  } catch {
    // No process found on this port — expected
  }
}

if (killed === 0) {
  console.log("No servers found on ports:", PORTS.join(", "));
} else {
  console.log(`\nDone. Killed ${killed} process${killed === 1 ? "" : "es"}.`);
}
