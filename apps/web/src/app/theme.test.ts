import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { SiteTheme } from "@/content/site";

/**
 * WCAG 2.2 contrast gate for the `@theme` tokens in globals.css: text pairs
 * ≥ 4.5:1 (1.4.3) and essential non-text boundaries ≥ 3:1 (1.4.11). The
 * formula lives here, independent of the stylesheet it checks.
 */

// Vitest runs from the package root; jsdom's import.meta.url is not a file URL.
const css = readFileSync(resolve(process.cwd(), "src/app/globals.css"), "utf8");

function token(name: string): string {
  const value = new RegExp(`--color-${name}:\\s*(#[0-9a-f]{6})`, "i").exec(
    css,
  )?.[1];
  if (value === undefined) throw new Error(`missing --color-${name}`);
  return value.toLowerCase();
}

function channel(hex: string, start: number): number {
  const value = Number.parseInt(hex.slice(start, start + 2), 16) / 255;
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

function luminance(hex: string): number {
  return (
    0.2126 * channel(hex, 1) +
    0.7152 * channel(hex, 3) +
    0.0722 * channel(hex, 5)
  );
}

function contrast(a: string, b: string): number {
  const first = luminance(a);
  const second = luminance(b);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

const TEXT_PAIRS: ReadonlyArray<readonly [string, string]> = [
  ["text", "surface"],
  ["text", "surface-muted"],
  ["text-muted", "surface"],
  ["text-muted", "surface-muted"],
  ["text-on-steel", "steel"],
  ["text-on-steel", "steel-hover"],
  ["text-on-steel", "steel-pressed"],
  ["accent-on-steel", "steel"],
];

const BOUNDARY_PAIRS: ReadonlyArray<readonly [string, string]> = [
  ["focus", "surface"],
  ["focus", "surface-muted"],
  ["focus-on-steel", "steel"],
  ["steel", "surface"],
];

describe("theme contrast", () => {
  it("knows the formula's fixed points", () => {
    expect(contrast("#000000", "#ffffff")).toBeCloseTo(21, 5);
    expect(contrast("#777777", "#777777")).toBeCloseTo(1, 5);
  });

  it.each(TEXT_PAIRS)(
    "%s text on %s reaches 4.5:1",
    (foreground, background) => {
      expect(
        contrast(token(foreground), token(background)),
      ).toBeGreaterThanOrEqual(4.5);
    },
  );

  it.each(BOUNDARY_PAIRS)(
    "%s boundary on %s reaches 3:1",
    (foreground, background) => {
      expect(
        contrast(token(foreground), token(background)),
      ).toBeGreaterThanOrEqual(3);
    },
  );

  it("keeps metadata colors in step with the stylesheet", () => {
    expect(SiteTheme.background).toBe(token("surface"));
    expect(SiteTheme.themeColor).toBe(token("steel"));
  });

  it("fails loudly on a missing token", () => {
    expect(() => token("does-not-exist")).toThrow(
      "missing --color-does-not-exist",
    );
  });
});
