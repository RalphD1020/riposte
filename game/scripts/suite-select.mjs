/**
 * TEST-TIER-001 selection: which suites a change or an area needs, read from
 * the one manifest (tests/suite_manifest.json) the harness reads too. An
 * explicit map, not a dependency graph: the areas name their owning paths.
 *
 * @see ../../docs/reference/testing.md
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";

export function loadManifest(gameRoot) {
  return JSON.parse(
    readFileSync(join(gameRoot, "tests/suite_manifest.json"), "utf8"),
  );
}

/** Suites for named areas; `fast` is every fast-size suite, and a registered
 * suite name selects itself. Unknown names are returned, never ignored. */
export function suitesForAreas(manifest, areas) {
  const suites = new Set();
  const unknown = [];
  for (const area of areas) {
    if (area === "fast") {
      for (const suite of manifest.suites)
        if (suite.tier === "fast") suites.add(suite.name);
    } else if (manifest.areas[area]) {
      for (const name of manifest.areas[area].suites) suites.add(name);
    } else if (manifest.suites.some((suite) => suite.name === area)) {
      suites.add(area);
    } else {
      unknown.push(area);
    }
  }
  return { suites: [...suites], unknown };
}

/** Suites for changed files, given as paths relative to the game package.
 * A changed test file selects only its own suite; a production file its
 * owning areas; docs and non-game files select nothing. */
export function suitesForFiles(manifest, files) {
  const suites = new Set();
  const unowned = [];
  for (const file of files) {
    const own = manifest.suites.find((suite) => suite.path === `res://${file}`);
    if (own) {
      suites.add(own.name);
      continue;
    }
    let owned = false;
    for (const area of Object.values(manifest.areas)) {
      if (area.paths.some((prefix) => file.startsWith(prefix))) {
        owned = true;
        for (const name of area.suites) suites.add(name);
      }
    }
    if (!owned && /\.(gd|tscn|tres|json|cfg|mjs)$/.test(file))
      unowned.push(file);
  }
  return { suites: [...suites], unowned };
}
