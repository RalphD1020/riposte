"""Materialize the P3 presentation candidate from its tracked recipe (recipe.json), or fail closed.

The candidate lives in the git-ignored game/assets/candidates/. This puts the exact recipe outputs there:
the wrapper from its tracked copy, the body either verified in place or rebuilt from the recipe inputs by the
pinned Blender. Every input and output is checked against its recorded sha256; a rebuilt body whose bytes
differ from the recipe is a failure to inspect (semantic and visual diff), never a new hash to accept.
Prints one RIPOSTE_MATERIALIZE JSON line; exit 0 ready, 1 failed, 2 input / tool problem.

    python tools/blender/candidates/p3_v7/materialize.py [--rebuild] [--work <dir>]
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
RECIPE = Path(__file__).with_name("recipe.json")
STEP_TIMEOUT_S = 600


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def report(status: str, code: int, **fields) -> int:
    print("RIPOSTE_MATERIALIZE " + json.dumps(dict(status=status, **fields), sort_keys=True))
    return code


def tool_path(spec: dict) -> Path:
    return Path(os.environ.get(spec["env"], spec["default"]))


def check_tool(name: str, spec: dict) -> str | None:
    exe = tool_path(spec)
    if not exe.exists():
        return f"{name} not found at {exe} (set {spec['env']})"
    out = subprocess.run([str(exe), "--version"], capture_output=True, text=True, timeout=60).stdout
    first = out.strip().splitlines()[0] if out.strip() else ""
    if spec["version"] not in first:
        return f"{name} is '{first}', the recipe pins '{spec['version']}'"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true", help="rebuild the body from the recipe inputs even if a matching one exists")
    parser.add_argument("--work", help="scratch directory for the rebuild (default: a temp dir)")
    args = parser.parse_args()
    recipe = json.loads(RECIPE.read_text(encoding="utf-8"))

    problems, missing = [], []
    for key, entry in recipe["inputs"].items():
        path = ROOT / entry["path"]
        if not path.exists():
            missing.append({"input": key, "path": entry["path"], "tracked": entry["tracked"]})
        elif sha256(path) != entry["sha256"]:
            problems.append(f"input {key} ({entry['path']}) does not match the recipe hash")

    body = recipe["outputs"]["body"]
    body_dest = ROOT / body["to"]
    body_ready = body_dest.exists() and sha256(body_dest) == body["sha256"]
    rebuilt = False
    if args.rebuild or not body_ready:
        needed = [m for m in missing if m["input"] != "wrapper"]
        if needed or problems:
            return report("ERROR", 2, reason="cannot rebuild the body: inputs missing or changed", missing=needed, problems=problems, note=recipe["open"])
        tool_error = check_tool("blender", recipe["tools"]["blender"])
        if tool_error:
            return report("ERROR", 2, reason=tool_error)
        work = Path(args.work) if args.work else Path(tempfile.mkdtemp(prefix="riposte_p3_candidate_"))
        work.mkdir(parents=True, exist_ok=True)
        names = {k: str(ROOT / v["path"]) for k, v in recipe["inputs"].items()}
        names.update(work=str(work), rig_contract=recipe["rig_contract"])
        exe = str(tool_path(recipe["tools"]["blender"]))
        for index, step in enumerate(recipe["steps"]):
            argv = [exe] + [a.format(**names) for a in step["args"]]
            try:
                done = subprocess.run(argv, capture_output=True, text=True, timeout=STEP_TIMEOUT_S, cwd=ROOT)
            except subprocess.TimeoutExpired:
                return report("TIMEOUT", 1, step=index, timeout_s=STEP_TIMEOUT_S)
            if done.returncode != 0 or ("expect" in step and step["expect"] not in done.stdout):
                return report("FAIL", 1, step=index, returncode=done.returncode, tail=done.stdout[-600:] + done.stderr[-600:])
        built = Path(body["from"].format(**names))
        if not built.exists():
            return report("FAIL", 1, reason=f"the export produced no body at {built}")
        built_hash = sha256(built)
        if built_hash != body["sha256"]:
            return report("FAIL", 1, reason="the rebuilt body differs from the recipe: inspect semantically / visually, never re-bless automatically",
                          rebuilt_sha256=built_hash, recipe_sha256=body["sha256"], rebuilt_at=str(built))
        body_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(built, body_dest)
        rebuilt = True

    wrapper = recipe["outputs"]["wrapper"]
    source = ROOT / recipe["inputs"]["wrapper"]["path"]
    if not source.exists() or sha256(source) != wrapper["sha256"]:
        return report("ERROR", 2, reason="the tracked wrapper copy is missing or changed", path=str(source))
    wrapper_dest = ROOT / wrapper["to"]
    if not wrapper_dest.exists() or sha256(wrapper_dest) != wrapper["sha256"]:
        shutil.copyfile(source, wrapper_dest)

    for key, out in recipe["outputs"].items():
        dest = ROOT / out["to"]
        if not dest.exists() or sha256(dest) != out["sha256"]:
            return report("FAIL", 1, reason=f"output {key} does not match the recipe after materializing", path=out["to"])
    record = {"candidate_id": recipe["candidate_id"], "rebuilt": rebuilt, "outputs": {k: v["sha256"] for k, v in recipe["outputs"].items()},
              "rig_contract": recipe["rig_contract"], "untracked_inputs": [k for k, v in recipe["inputs"].items() if not v["tracked"]]}
    (ROOT / "game/assets/candidates/p3_v7_hg.materialized.json").write_text(json.dumps(record, indent=1), encoding="utf-8")
    return report("PASS", 0, **record)


if __name__ == "__main__":
    sys.exit(main())
