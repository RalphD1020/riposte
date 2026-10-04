/**
 * Cleanup path lists for generated output and dependency state.
 *
 * @see ../docs/guides/local-dev.md
 */

export const GENERATED_PATHS = [
  ".reports",
  ".turbo",
  ".next",
  "dist",
  "coverage",
  "out",
  "game/.godot",
  "apps/web/.next",
  "apps/web/out",
  "apps/web/coverage",
  "game/coverage",
];

export const GENERATED_GLOBS = ["*.tsbuildinfo"];

export const SKIP_DIR_NAMES = new Set([".git", ".pnpm-store"]);
