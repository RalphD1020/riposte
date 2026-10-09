"""The official asset build: every Blender source → validated GLB + manifest.

Blender MCP (or an artist) edits the .blend sources under art-src/blender;
this script is what turns them into game assets, headless and repeatable:

    blender --background --factory-startup --python tools/blender/export_assets.py

Each source is validated against its contract first (validate_assets.py). Any
problem fails the build with a non-zero exit and nothing is half-written.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import validate_assets  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES = os.path.join(ROOT, "art-src", "blender")
OUT = os.path.join(ROOT, "game", "assets", "generated")

ASSETS = [
    # source, kind, asset id, output
    ("fighters/wolf.blend", "fighter", "fighter.wolf", "fighters/wolf.glb"),
    ("fighters/wolf_training.blend", "fighter", "fighter.wolf.training", "fighters/wolf_training.glb"),
    ("weapons/bastard_sword.blend", "weapon", "weapon.bastard_sword", "weapons/bastard_sword.glb"),
    ("weapons/bastard_sword_training.blend", "weapon", "weapon.bastard_sword.training", "weapons/bastard_sword_training.glb"),
    ("arenas/standard_arena.blend", "arena", "arena.standard", "arenas/standard_arena.glb"),
]


def _export_kwargs(path, kind):
    wanted = {
        "filepath": path,
        "export_format": "GLB",
        "export_yup": True,
        "export_apply": False,
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
        "export_animations": kind == "fighter",
        "export_animation_mode": "ACTIONS",
        "export_skins": kind == "fighter",
        "export_force_sampling": True,
        "export_frame_step": 1,
        "export_def_bones": False,
        "export_reset_pose_bones": True,
        "export_image_format": "NONE",
    }
    available = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    return {k: v for k, v in wanted.items() if k in available}


def main():
    failed = []
    for source, kind, asset_id, output in ASSETS:
        source_path = os.path.join(SOURCES, source)
        if not os.path.exists(source_path):
            failed.append("%s: missing source" % source)
            continue
        bpy.ops.wm.open_mainfile(filepath=source_path)
        problems = validate_assets.VALIDATORS[kind]()
        if problems:
            failed.extend("%s: %s" % (source, p) for p in problems)
            continue
        out_path = os.path.join(OUT, output)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        bpy.ops.export_scene.gltf(**_export_kwargs(out_path, kind))
        with open(os.path.splitext(out_path)[0] + ".manifest.json", "w", encoding="utf-8", newline="\n") as handle:
            json.dump(validate_assets.manifest(asset_id, kind), handle, indent=2)
            handle.write("\n")
        print("RIPOSTE_EXPORTED", output)
    if failed:
        for problem in failed:
            print("RIPOSTE_ASSET_PROBLEM", problem)
        sys.exit(1)
    print("RIPOSTE_ASSETS_OK", len(ASSETS))


if __name__ == "__main__":
    main()
