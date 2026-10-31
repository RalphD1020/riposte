"""Freeze a versioned, immutable baseline of the base body and the characters built on it.

A baseline is a directory `art-src/blender/characters/baseline/<version>/` holding byte
copies of the protected sources (the master, its configuration, regions and surfaces, the
character assemblies and their attire, the approved hair definitions), the exports made
from them, the body record (`body_record`), and `baseline.json` listing every file with
its sha256. Freezing refuses an existing version, so a baseline is written once; the
copies are marked read-only; `verify` re-hashes every file and is run by the tests, so a
baseline that changes fails the build. Experiments happen on a versioned candidate
(`male_base.v2.blend`), never on the baseline and never by overwriting the master.

    python -m character_modeling.baseline_freeze freeze v1 --record <record.json> --captures <dir>
    python -m character_modeling.baseline_freeze verify v1

Run from tools/character_modeling. Pure Python: no Blender.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path

SCHEMA = "riposte.body_baseline"
ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"
GARMENTS = ROOT / "art-src" / "blender" / "garments"
GENERATED = ROOT / "game" / "assets" / "generated" / "characters"
BASELINES = CHARACTERS / "baseline"
## Sources a body overhaul must never lose (relative to the repository root).
SOURCES = (
    "art-src/blender/characters/male_base.blend",
    "art-src/blender/characters/male_base.configuration.json",
    "art-src/blender/characters/male_base.regions.json",
    "art-src/blender/characters/male_base.surfaces.json",
    "art-src/blender/characters/male_base.surface_calibration.json",
    "art-src/blender/characters/wolf/wolf.assembly.json",
    "art-src/blender/characters/wolf/wolf_attire.blend",
    "art-src/blender/garments/wolf_hair_ranger.garment.json",
    "art-src/blender/garments/wolf_hair_training.garment.json",
)
## Exports made from those sources (the seven configurations and Wolf's three).
EXPORTS = (
    "game/assets/generated/characters/male_base.glb",
    "game/assets/generated/characters/variants/male_base_lean.glb",
    "game/assets/generated/characters/variants/male_base_lean_half.glb",
    "game/assets/generated/characters/variants/male_base_heavy_half.glb",
    "game/assets/generated/characters/variants/male_base_heavy.glb",
    "game/assets/generated/characters/variants/male_base_extreme_lean.glb",
    "game/assets/generated/characters/variants/male_base_extreme_heavy.glb",
    "game/assets/generated/characters/wolf_bare.glb",
    "game/assets/generated/characters/wolf_ranger.glb",
    "game/assets/generated/characters/wolf_training.glb",
)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _copy(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)


def freeze(version, record=None, captures=None, notes=""):
    """Write the baseline once. Returns its manifest."""
    target = BASELINES / version
    if target.exists():
        raise SystemExit("RIPOSTE_BASELINE_EXISTS: %s is frozen; a baseline is written once" % target)
    files = {}
    for rel in SOURCES:
        src = ROOT / rel
        dst = target / "sources" / Path(rel).relative_to("art-src/blender")
        _copy(src, dst)
        files[dst.relative_to(target).as_posix()] = {"from": rel, "sha256": sha256(dst)}
    for rel in EXPORTS:
        src = ROOT / rel
        dst = target / "exports" / Path(rel).name
        _copy(src, dst)
        manifest = src.with_suffix(".manifest.json")
        files[dst.relative_to(target).as_posix()] = {"from": rel, "sha256": sha256(dst)}
        if manifest.exists():
            mdst = target / "exports" / manifest.name
            _copy(manifest, mdst)
            files[mdst.relative_to(target).as_posix()] = {"from": manifest.relative_to(ROOT).as_posix(), "sha256": sha256(mdst)}
    if record:
        dst = target / "body_record.json"
        _copy(Path(record), dst)
        files["body_record.json"] = {"from": "tools/blender/inspect/base_record.py", "sha256": sha256(dst)}
    if captures:
        for png in sorted(Path(captures).glob("*.png")):
            dst = target / "captures" / png.name
            _copy(png, dst)
            files[dst.relative_to(target).as_posix()] = {"from": "tools/blender/inspect/render_views.py", "sha256": sha256(dst)}
    manifest = {"schema": SCHEMA, "version": version, "notes": notes, "files": files}
    path = target / "baseline.json"
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent=1)
        handle.write("\n")
    os.chmod(path, stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)
    return manifest


def verify(version, root=BASELINES):
    """Problems with a frozen baseline: a listed file missing or changed, or a file not listed."""
    target = Path(root) / version
    manifest_path = target / "baseline.json"
    if not manifest_path.exists():
        return ["baseline %s has no baseline.json" % version]
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    problems = []
    for rel, entry in sorted(manifest["files"].items()):
        path = target / rel
        if not path.exists():
            problems.append("baseline %s: %s is missing" % (version, rel))
        elif sha256(path) != entry["sha256"]:
            problems.append("baseline %s: %s changed (a baseline is immutable)" % (version, rel))
    listed = set(manifest["files"]) | {"baseline.json"}
    for path in sorted(p for p in target.rglob("*") if p.is_file()):
        rel = path.relative_to(target).as_posix()
        if rel not in listed:
            problems.append("baseline %s: %s is not part of the frozen baseline" % (version, rel))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("freeze", "verify"))
    parser.add_argument("version")
    parser.add_argument("--record", default="")
    parser.add_argument("--captures", default="")
    parser.add_argument("--notes", default="")
    args = parser.parse_args(argv)
    if args.action == "freeze":
        manifest = freeze(args.version, args.record or None, args.captures or None, args.notes)
        print("RIPOSTE_BASELINE_FROZEN %s files %d" % (args.version, len(manifest["files"])))
        return 0
    problems = verify(args.version)
    for p in problems:
        print("RIPOSTE_BASELINE_PROBLEM", p)
    print("RIPOSTE_BASELINE_VERIFY %s %s" % (args.version, "ok" if not problems else "%d problems" % len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
