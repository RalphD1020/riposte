"""The official asset build: every Blender source → validated GLB + manifest.

Blender MCP (or an artist) edits the .blend sources under art-src/blender;
this script is what turns them into game assets, headless and repeatable:

    blender --background --factory-startup --python tools/blender/export_assets.py

Each source is validated against its contract first (validate_assets.py). Any
problem fails the build with a non-zero exit and nothing is half-written.
"""

import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import character_assembly  # noqa: E402
import glb_compact  # noqa: E402
import validate_assets  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES = os.path.join(ROOT, "art-src", "blender")
OUT = os.path.join(ROOT, "game", "assets", "generated")

ASSETS = [
    # source, kind, asset id, output
    ("fighters/wolf.blend", "fighter", "fighter.wolf", "fighters/wolf.glb"),
    ("fighters/wolf_training.blend", "fighter", "fighter.wolf.training", "fighters/wolf_training.glb"),
    ## The production body candidate: one connected skinned body with Wolf's clips, not the shipping blockout.
    ("fighters/wolf_production.blend", "candidate", "fighter.wolf.production", "fighters/wolf_production.glb"),
    ## The male base, the authored master every male character derives from (CHARACTER-SOURCE-001): Model A's head, the heroic pass, on WolfRig.
    ## One export per validated configuration of its physique keys (male_base.configuration.json).
    ("characters/male_base.blend", "candidate", "character.male_base", "characters/male_base.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.lean", "characters/variants/male_base_lean.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.lean_half", "characters/variants/male_base_lean_half.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.heavy_half", "characters/variants/male_base_heavy_half.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.heavy", "characters/variants/male_base_heavy.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.extreme_lean", "characters/variants/male_base_extreme_lean.glb"),
    ("characters/male_base.blend", "candidate", "character.male_base.extreme_heavy", "characters/variants/male_base_extreme_heavy.glb"),
    ## Characters: a manifest assembles the base in a configuration with the character's identity and an outfit.
    ("characters/wolf/wolf.assembly.json", "character", "character.wolf.bare", "characters/wolf_bare.glb"),
    ("characters/wolf/wolf.assembly.json", "character", "character.wolf.ranger", "characters/wolf_ranger.glb"),
    ("characters/wolf/wolf.assembly.json", "character", "character.wolf.training", "characters/wolf_training.glb"),
    ("weapons/bastard_sword.blend", "weapon", "weapon.bastard_sword", "weapons/bastard_sword.glb"),
    ("weapons/bastard_sword_training.blend", "weapon", "weapon.bastard_sword.training", "weapons/bastard_sword_training.glb"),
    ("arenas/standard_arena.blend", "arena", "arena.standard", "arenas/standard_arena.glb"),
    ("arenas/masonry_board.blend", "board", "arena.masonry_board", "arenas/masonry_board.glb"),
    ("arenas/arena_floor.blend", "floor", "arena.floor", "arenas/arena_floor.glb"),
    ("arenas/arena_bowl.blend", "bowl", "arena.bowl", "arenas/arena_bowl.glb"),
    ("arenas/end_stage.blend", "deck", "arena.end", "arenas/end_stage.glb"),
    ("crowd/seated.blend", "crowd", "crowd.seated", "crowd/seated.glb"),
    ("crowd/cheer.blend", "crowd", "crowd.cheer", "crowd/cheer.glb"),
    ("crowd/hair_crop.blend", "crowd", "crowd.hair_crop", "crowd/hair_crop.glb"),
    ("crowd/hair_bun.blend", "crowd", "crowd.hair_bun", "crowd/hair_bun.glb"),
    ("crowd/hair_fringe.blend", "crowd", "crowd.hair_fringe", "crowd/hair_fringe.glb"),
    ("crowd/face.blend", "crowd", "crowd.face", "crowd/face.glb"),
    ("crowd/beard_full.blend", "crowd", "crowd.beard_full", "crowd/beard_full.glb"),
]


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_known():
    """The suite's required list has to be a subset of this export list."""
    path = os.path.join(HERE, "required_presentation_assets.json")
    with open(path, encoding="utf-8") as handle:
        rows = json.load(handle)
    known = {row[2] for row in ASSETS}
    missing = [row["id"] for row in rows if row["id"] not in known]
    if missing:
        raise SystemExit("required assets missing from the export list: %s" % ", ".join(missing))


def _configure(source_path, asset_id):
    """A master with physique keys exports one configuration: its parameters'
    keys mixed into the rest mesh and the keys removed, in memory (the source
    is never saved). Returns (name, values, problems); None when the source
    has no configuration file."""
    config_path = os.path.splitext(source_path)[0] + ".configuration.json"
    if not os.path.exists(config_path):
        return None
    with open(config_path, encoding="utf-8") as handle:
        config = json.load(handle)
    name = config["exports"].get(asset_id)
    if name is None:
        return None, {}, ["%s has no configuration for %s" % (os.path.basename(config_path), asset_id)]
    values = config["configurations"][name]
    body = bpy.data.objects.get(config["mesh"])
    if body is None or body.data.shape_keys is None:
        return name, values, ["%s carries no physique keys" % config["mesh"]]
    return name, values, character_assembly.bake_configuration(body, values, config["parameters"])


def _export_kwargs(path, kind):
    wanted = {
        "filepath": path,
        "export_format": "GLB",
        "export_yup": True,
        "export_apply": False,
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
        "export_animations": kind in ("fighter", "candidate", "character"),
        "export_animation_mode": "ACTIONS",
        "export_skins": kind in ("fighter", "candidate", "character"),
        ## Four influences per vertex, the strongest kept: Compatibility's
        ## skinning limit, explicit here so an exporter default can never
        ## ship eight. PRES-PRODUCTION asserts the imported stride is four.
        "export_influence_nb": 4,
        "export_all_influences": False,
        "export_force_sampling": True,
        ## 30 Hz keys, linearly interpolated: the rigid block rig reads the
        ## same, and the fast sword motion is procedural (carriage, IK), not
        ## clip keys. Keeps the fighter under the integrity size limit.
        "export_frame_step": 2,
        ## Drop sampled keys a held pose repeats (lossless for linear
        ## interpolation), so holds — a stab's impaled beat, a victory's load —
        ## cost nothing and the fighter stays under the integrity size limit.
        "export_optimize_animation_size": True,
        "export_def_bones": False,
        "export_reset_pose_bones": True,
        ## Fighters embed the face paint. Everything else stays untextured so a
        ## stone mesh does not grow an image it does not use.
        "export_image_format": "AUTO" if kind == "fighter" else "NONE",
    }
    ## Stone blocks carry a per-block Color multiplier, and the deck top a
    ## faint lift toward its rim. The default material mode skips it when
    ## images are not exported.
    if kind in ("bowl", "floor", "board", "deck"):
        wanted["export_vertex_color"] = "ACTIVE"
    available = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    return {k: v for k, v in wanted.items() if k in available}


def _selected(assets):
    if "--" not in sys.argv:
        return assets
    extra = sys.argv[sys.argv.index("--") + 1:]
    if "--only" not in extra:
        return assets
    wanted = set(extra[extra.index("--only") + 1].split(","))
    return [row for row in assets if row[2] in wanted or row[3] in wanted]


def main():
    _require_known()
    failed = []
    chosen = _selected(ASSETS)
    for source, kind, asset_id, output in chosen:
        source_path = os.path.join(SOURCES, source)
        if not os.path.exists(source_path):
            failed.append("%s: missing source" % source)
            continue
        assembled = None
        if kind == "character":
            assembled, problems = character_assembly.assemble(source_path, asset_id, SOURCES)
            if problems:
                failed.extend("%s: %s" % (source, p) for p in problems)
                continue
            configured = None
        else:
            bpy.ops.wm.open_mainfile(filepath=source_path)
            configured = _configure(source_path, asset_id)
            if configured is not None and configured[2]:
                failed.extend("%s: %s" % (source, p) for p in configured[2])
                continue
        problems = validate_assets.VALIDATORS[kind]()
        if problems:
            failed.extend("%s: %s" % (source, p) for p in problems)
            continue
        out_path = os.path.join(OUT, output)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        bpy.ops.export_scene.gltf(**_export_kwargs(out_path, kind))
        ## Rest-only channels (every scale track, every bone a clip leaves
        ## alone) cost glTF JSON and nothing else: Godot poses an untracked
        ## bone at rest.
        glb_compact.compact(out_path)
        recorded = validate_assets.manifest(asset_id, kind)
        recorded["source"] = source.replace("\\", "/")
        recorded["source_sha256"] = _sha256(source_path)
        if assembled is not None:
            recorded["assembly"] = {"outfit": assembled["outfit"], "configuration": assembled["configuration"]}
        if configured is not None:
            recorded["configuration"] = {"name": configured[0], "values": configured[1],
                                         "sha256": _sha256(os.path.splitext(source_path)[0] + ".configuration.json")}
        with open(os.path.splitext(out_path)[0] + ".manifest.json", "w", encoding="utf-8", newline="\n") as handle:
            json.dump(recorded, handle, indent=2)
            handle.write("\n")
        print("RIPOSTE_EXPORTED", output)
    if failed:
        for problem in failed:
            print("RIPOSTE_ASSET_PROBLEM", problem)
        sys.exit(1)
    print("RIPOSTE_ASSETS_OK", len(chosen))


if __name__ == "__main__":
    main()
