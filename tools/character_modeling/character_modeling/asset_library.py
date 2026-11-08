"""The character asset library (CHARACTER-LIBRARY-001): approved, versioned, reusable assets.

Every approved piece of a character (the foundation, a face, a hairstyle, facial hair, a skin,
attire, rigging data) is published here once per version, never edited: a candidate is
built in an iteration folder, approved by the person, then promoted. Promotion writes a new
version directory, refuses to overwrite one, and marks the previous version superseded in
the index; a superseded version stays for rollback and the characters that use it.

Layout (`art-src/blender/library/`):

    library.json                                   the index: origins, categories, assets, versions
    <origin>/<category>/category.json              every origin carries every category (menus)
    <origin>/<category>/<asset id>/v<NNN>/asset.json + payload files (read-only byte copies)

An asset has two identities: its category (what it is, from `CATEGORIES`, shared by every
character and by the creator's menus) and its origin (the foundation or character that first
produced it: provenance, never an exclusivity rule). Its compatibility says what it may be
used with (the foundation id and fingerprint, required regions); a creator lists an asset
for a character only when that holds.

Payload files are byte copies (small definitions, data). Large approved sources that stay
where they are (the foundation's blend and record) are listed as `protected` with their
sha256: `verify` fails if one changes, so an approved source cannot be overwritten in place;
a revision is a new source file and a new version.

Pure Python: no Blender.

    python -m character_modeling.asset_library verify
    python -m character_modeling.asset_library promote <spec.json>
    python -m character_modeling.asset_library menu [--foundation <id>]
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

SCHEMA = "riposte.library_asset"
INDEX_SCHEMA = "riposte.asset_library"
CATEGORY_SCHEMA = "riposte.library_category"
ROOT = Path(__file__).resolve().parents[3]
LIBRARY = ROOT / "art-src" / "blender" / "library"
## The shared categories and their subtypes: one schema for every character and the menus.
CATEGORIES = {
    "foundation": ("body", "variant_generation", "head", "skeleton", "landmarks", "regions"),
    "face": ("face", "eyes", "brows", "nose", "expressions"),
    "hair": ("hairstyle",),
    "facial_hair": ("beard", "moustache", "sideburns", "stubble"),
    "skin": ("tone", "material"),
    "attire": ("top", "trousers", "armour", "footwear", "belt", "accessory"),
    "rigging": ("fit_profile", "weights", "corrective"),
}
## A `riposte.garment` definition's type -> its library category.
CATEGORY_OF_TYPE = {"hair": "hair", "facial_hair": "facial_hair", "garment": "attire"}
## Lifecycle. Only approved assets are promoted; superseded is set by a later promotion;
## candidates, reviews and rejections stay with their iteration's evidence.
STATUSES = ("candidate", "reviewed", "approved", "superseded", "rejected")
PROMOTABLE = "approved"
REQUIRED = ("id", "category", "subtype", "origin", "status", "approval", "compatibility")
## Folders outside the repository's tracked sources (evidence, local plans).
LOCAL_FOLDERS = (".reports", ".impl")
## Compatibility of an asset with one body/head configuration (CHARACTER-LIBRARY-001):
## validated (a recorded, visually approved build of that configuration), compatible by
## contract (its foundation supports the configuration and its fitting contract maps onto it,
## not yet visually approved there), unsupported (never offered).
VALIDATED, BY_CONTRACT, UNSUPPORTED = "validated", "compatible_by_contract", "unsupported"
COMPATIBILITY_STATES = (VALIDATED, BY_CONTRACT, UNSUPPORTED)
VALIDATION_SCHEMA = "riposte.library_validations"
## Stable identities for catalogs (Blender's asset catalogs key on UUIDs).
UUID_NAMESPACE = "riposte.character_library"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _write(path, data, read_only=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=1, sort_keys=True)
        handle.write("\n")
    if read_only:
        os.chmod(path, stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)


## Where library payloads and protected sources may live (resolved): the repository. A path
## that resolves elsewhere, through `..` or a link, is refused.
PERMITTED_ROOTS = (ROOT,)


def canonical(path, roots=None):
    """`path` (repository-relative or absolute) as one comparable form: absolute, `..` and
    links resolved, case-normalized where the file system ignores case. Raises ValueError
    when it resolves outside `roots` (default PERMITTED_ROOTS)."""
    raw = Path(path)
    resolved = os.path.normcase(os.path.realpath(raw if raw.is_absolute() else ROOT / raw))
    bases = [os.path.normcase(os.path.realpath(r)) for r in (roots or PERMITTED_ROOTS)]
    if not any(resolved == b or resolved.startswith(b.rstrip(os.sep) + os.sep) for b in bases):
        raise ValueError("%s resolves outside the permitted roots" % path)
    return resolved


def _relative(path):
    """A repository-relative POSIX path (provenance never records a machine's paths)."""
    path = Path(path).resolve()
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.name
    ## Iteration evidence and local work folders are not part of the repository.
    return "iteration evidence: %s" % path.name if rel.split("/", 1)[0] in LOCAL_FOLDERS else rel


def empty_index():
    return {"schema": INDEX_SCHEMA, "version": 1, "categories": {k: list(v) for k, v in CATEGORIES.items()},
            "origins": {}, "assets": {}}


def index(root=LIBRARY):
    path = Path(root) / "library.json"
    return _read(path) if path.exists() else empty_index()


def ensure_origin(root, origin):
    """Give `origin` every category directory (with its marker), the same for every
    character, and register it in the index."""
    root = Path(root)
    library = index(root)
    for category, subtypes in CATEGORIES.items():
        marker = root / origin / category / "category.json"
        if not marker.exists():
            _write(marker, {"schema": CATEGORY_SCHEMA, "origin": origin, "category": category, "subtypes": list(subtypes)})
    library["origins"].setdefault(origin, {"categories": {c: [] for c in CATEGORIES}})
    _write(root / "library.json", library)
    return library


def spec_problems(spec, library, roots=None):
    """Why `spec` (an asset to promote) cannot be promoted. Empty means it can."""
    missing = [k for k in REQUIRED if k not in spec]
    if missing:
        return ["asset spec lacks %s" % ", ".join(missing)]
    out = []
    if spec["category"] not in CATEGORIES:
        out.append("%s: unknown category %s (known: %s)" % (spec["id"], spec["category"], sorted(CATEGORIES)))
    elif spec["subtype"] not in CATEGORIES[spec["category"]]:
        out.append("%s: subtype %s is not one of %s's %s" % (spec["id"], spec["subtype"], spec["category"], CATEGORIES[spec["category"]]))
    if spec["status"] != PROMOTABLE:
        out.append("%s: only an approved asset is promoted (status %s)" % (spec["id"], spec["status"]))
    approval = spec["approval"]
    for key in ("date", "by", "evidence"):
        if not approval.get(key):
            out.append("%s: approval names its %s" % (spec["id"], key))
    known = library["assets"]
    existing = known.get(spec["id"])
    if existing and (existing["origin"], existing["category"]) != (spec["origin"], spec["category"]):
        out.append("%s: already an asset of %s/%s" % (spec["id"], existing["origin"], existing["category"]))
    for dep in spec.get("dependencies", []):
        entry = known.get(dep.get("id"), {}).get("versions", {}).get(dep.get("version"))
        if entry is None:
            out.append("%s depends on an unknown asset %s %s" % (spec["id"], dep.get("id"), dep.get("version")))
    for rel, digest in spec.get("protected", {}).items():
        try:
            path = canonical(rel, roots)
        except ValueError as error:
            out.append("%s: protected source %s" % (spec["id"], error))
            continue
        if not os.path.exists(path) or sha256(path) != digest:
            out.append("%s: protected source %s does not match its sha256" % (spec["id"], rel))
    for rel in spec.get("payload", []):
        try:
            path = canonical(rel, roots)
        except ValueError as error:
            out.append("%s: payload %s" % (spec["id"], error))
            continue
        if not os.path.exists(path):
            out.append("%s: payload %s is missing" % (spec["id"], rel))
    return out


def promote(spec, root=LIBRARY, roots=None):
    """Publish `spec` as the asset's next version: a new directory, read-only copies of its
    payload, its asset.json; the previous current version superseded in the index. Never
    overwrites. `roots`: where payloads and protected sources may resolve (default the
    repository). Returns the new version."""
    root = Path(root)
    library = ensure_origin(root, spec["origin"]) if spec.get("origin") else index(root)
    problems = spec_problems(spec, library, roots)
    if problems:
        raise ValueError("; ".join(problems))
    entry = library["assets"].setdefault(spec["id"], {"origin": spec["origin"], "category": spec["category"],
                                                       "subtype": spec["subtype"], "current": None, "versions": {},
                                                       "uuid": asset_uuid(spec["id"])})
    version = "v%03d" % (len(entry["versions"]) + 1)
    target = root / spec["origin"] / spec["category"] / spec["id"] / version
    if target.exists():
        raise ValueError("%s %s exists: an approved version is never overwritten" % (spec["id"], version))
    files = {}
    for rel in spec.get("payload", []):
        src = Path(canonical(rel, roots))
        dst = target / src.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        os.chmod(dst, stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)
        files[src.name] = {"from": _relative(src), "sha256": sha256(dst)}
    asset = {"schema": SCHEMA, "id": spec["id"], "version": version, "category": spec["category"],
             "subtype": spec["subtype"], "origin": spec["origin"], "status": PROMOTABLE,
             "approval": spec["approval"], "compatibility": spec["compatibility"],
             "dependencies": spec.get("dependencies", []), "coverage": spec.get("coverage", {}),
             "files": files, "protected": spec.get("protected", {}), "sources": spec.get("sources", {}),
             "tags": spec.get("tags", []), "notes": spec.get("notes", "")}
    _write(target / "asset.json", asset, read_only=True)
    if entry["current"]:
        entry["versions"][entry["current"]]["status"] = "superseded"
    entry["versions"][version] = {"status": PROMOTABLE, "sha256": sha256(target / "asset.json")}
    entry["current"] = version
    ids = library["origins"][spec["origin"]]["categories"][spec["category"]]
    if spec["id"] not in ids:
        ids.append(spec["id"])
    _write(root / "library.json", library)
    return version


def asset(asset_id, version=None, root=LIBRARY):
    """An asset's asset.json (its current version unless `version`)."""
    entry = index(root)["assets"][asset_id]
    version = version or entry["current"]
    return _read(Path(root) / entry["origin"] / entry["category"] / asset_id / version / "asset.json")


def payload(asset_id, name, version=None, root=LIBRARY):
    """A payload file of an asset version, parsed when it is JSON."""
    entry = index(root)["assets"][asset_id]
    path = Path(root) / entry["origin"] / entry["category"] / asset_id / (version or entry["current"]) / name
    return _read(path) if path.suffix == ".json" else path


## The foundation asset whose current version names the document every build reads.
FOUNDATION_ASSET = "male_base_foundation"
FOUNDATION_SCHEMA = "riposte.character_foundation"


def current_foundation_document(root=LIBRARY, roots=None):
    """The approved foundation document in place (its canonical path): the one payload of the
    current `male_base_foundation` version that is a foundation document, where it came
    from. A foundation revision is a new document and a new version, so every build follows
    the library and the superseded document stays in place for rollback."""
    data = asset(FOUNDATION_ASSET, root=root)
    found = [entry["from"] for name, entry in sorted(data["files"].items())
             if name.endswith(".json") and payload(FOUNDATION_ASSET, name, root=root).get("schema") == FOUNDATION_SCHEMA]
    if len(found) != 1:
        raise ValueError("%s %s carries %d foundation documents, not one" % (FOUNDATION_ASSET, data["version"], len(found)))
    return canonical(found[0], roots)


def verify(root=LIBRARY, check_protected=True, roots=None):
    """Problems with the library: a category directory missing for an origin, a version's
    asset.json or payload changed, missing or unlisted, a protected source changed (an
    approved or a superseded version's: a rollback needs its sources too)."""
    root = Path(root)
    library = index(root)
    out = []
    if library.get("schema") != INDEX_SCHEMA:
        return ["the library index is not a %s" % INDEX_SCHEMA]
    if library["categories"] != {k: list(v) for k, v in CATEGORIES.items()}:
        out.append("the index's categories are not the shared schema's")
    for origin in library["origins"]:
        for category in CATEGORIES:
            if not (root / origin / category / "category.json").exists():
                out.append("%s lacks the %s category" % (origin, category))
    for asset_id, entry in sorted(library["assets"].items()):
        if entry.get("uuid") != asset_uuid(asset_id):
            out.append("%s: its uuid is not the stable uuid of its id" % asset_id)
        for record in validations(asset_id, root):
            if record["version"] not in entry["versions"]:
                out.append("%s: a validation names an unknown version %s" % (asset_id, record["version"]))
        for version, record in sorted(entry["versions"].items()):
            folder = root / entry["origin"] / entry["category"] / asset_id / version
            meta = folder / "asset.json"
            if not meta.exists():
                out.append("%s %s: asset.json is missing" % (asset_id, version))
                continue
            if sha256(meta) != record["sha256"]:
                out.append("%s %s: asset.json changed (an approved version is immutable)" % (asset_id, version))
            data = _read(meta)
            for name, file_entry in data["files"].items():
                path = folder / name
                if not path.exists() or sha256(path) != file_entry["sha256"]:
                    out.append("%s %s: %s changed or missing" % (asset_id, version, name))
            listed = set(data["files"]) | {"asset.json"}
            out += ["%s %s: %s is not part of the version" % (asset_id, version, p.name)
                    for p in sorted(folder.iterdir()) if p.name not in listed]
            if check_protected:
                for rel, digest in data.get("protected", {}).items():
                    try:
                        path = canonical(rel, roots)
                    except ValueError as error:
                        out.append("%s %s: protected source %s" % (asset_id, version, error))
                        continue
                    if not os.path.exists(path) or sha256(path) != digest:
                        out.append("%s %s: protected source %s was changed in place" % (asset_id, version, rel))
    return out


def protected_paths(root=LIBRARY, roots=None):
    """The canonical paths (`canonical`) every promoted version (approved or superseded)
    protects in place."""
    library = index(root)
    out = set()
    for asset_id, entry in library["assets"].items():
        for version in entry["versions"]:
            out.update(canonical(p, roots) for p in asset(asset_id, version, root).get("protected", {}))
    return out


def refuse_overwrite(path, root=LIBRARY, roots=None):
    """Raise if `path` (repository-relative or absolute, through `..` or a link) is a source
    a promoted version protects, or resolves outside the permitted roots."""
    try:
        target = canonical(path, roots)
    except ValueError as error:
        raise SystemExit("RIPOSTE_LIBRARY_PROTECTED: refusing to write %s" % error)
    if target in protected_paths(root, roots):
        raise SystemExit("RIPOSTE_LIBRARY_PROTECTED: %s belongs to an approved library asset; "
                         "a revision is a new file and a new version, never an overwrite" % _relative(target))


def asset_uuid(asset_id):
    import uuid
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "%s/%s" % (UUID_NAMESPACE, asset_id)))


def configuration_key(body):
    """One body configuration's key: height, frame and muscularity (the body inputs)."""
    return "h%.2f_f%.3f_m%.3f" % (float(body["height_m"]), float(body["frame_build"]), float(body["muscularity"]))


def _validations_path(root, entry, asset_id):
    return Path(root) / entry["origin"] / entry["category"] / asset_id / "validations.json"


def validations(asset_id, root=LIBRARY):
    """The asset's recorded validations: [{version, configuration, foundation, evidence, date}]."""
    entry = index(root)["assets"][asset_id]
    path = _validations_path(root, entry, asset_id)
    return _read(path)["records"] if path.exists() else []


def record_validation(asset_id, version, body, foundation_id, evidence, date, root=LIBRARY):
    """Record that `asset_id` `version` was built on `body` and visually approved there.
    Append-only: an approved asset is never edited; its validations only grow."""
    entry = index(root)["assets"][asset_id]
    if version not in entry["versions"]:
        raise ValueError("%s has no version %s" % (asset_id, version))
    if foundation_id not in asset(asset_id, version, root)["compatibility"].get("foundations", []):
        raise ValueError("%s %s does not support %s" % (asset_id, version, foundation_id))
    if not evidence or not date:
        raise ValueError("a validation names its evidence and date")
    path = _validations_path(root, entry, asset_id)
    data = _read(path) if path.exists() else {"schema": VALIDATION_SCHEMA, "asset": asset_id, "records": []}
    record = {"version": version, "configuration": configuration_key(body), "foundation": foundation_id,
              "evidence": evidence, "date": date}
    if record not in data["records"]:
        data["records"].append(record)
    _write(path, data)
    return record


def compatibility(asset_id, foundation_id, body, envelope, version=None, root=LIBRARY):
    """The compatibility state of an asset version with one configuration: validated (a
    recorded validation), compatible by contract (its foundation supports it and `body` lies
    in the foundation's supported envelope {input: (low, high)}), else unsupported."""
    data = asset(asset_id, version, root)
    if foundation_id not in data["compatibility"].get("foundations", []):
        return UNSUPPORTED
    if any(not envelope[k][0] <= float(body[k]) <= envelope[k][1] for k in envelope):
        return UNSUPPORTED
    key = configuration_key(body)
    if any(r["version"] == data["version"] and r["configuration"] == key and r["foundation"] == foundation_id
           for r in validations(asset_id, root)):
        return VALIDATED
    return BY_CONTRACT


def menu(foundation_id=None, root=LIBRARY, body=None, envelope=None):
    """{category: [{id, version, origin, subtype, compatibility}]} of the current approved
    assets, every category present (empty included). With a `foundation_id`, only assets
    supporting it; with a `body` (and the foundation's `envelope`), each asset's state for
    that configuration, unsupported ones left out."""
    library = index(root)
    out = {category: [] for category in CATEGORIES}
    for asset_id, entry in sorted(library["assets"].items()):
        data = asset(asset_id, root=root)
        foundations = data["compatibility"].get("foundations", [])
        if foundation_id and foundation_id not in foundations:
            continue
        state = compatibility(asset_id, foundation_id, body, envelope or {}, root=root) if body is not None else None
        if state == UNSUPPORTED:
            continue
        row = {"id": asset_id, "version": entry["current"], "origin": entry["origin"], "subtype": entry["subtype"]}
        if state:
            row["compatibility"] = state
        out[entry["category"]].append(row)
    return out


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("verify", "promote", "menu"))
    parser.add_argument("spec", nargs="?")
    parser.add_argument("--foundation", default=None)
    args = parser.parse_args(argv)
    if args.action == "promote":
        version = promote(_read(args.spec))
        print("RIPOSTE_LIBRARY_PROMOTED", _read(args.spec)["id"], version)
        return 0
    if args.action == "menu":
        print(json.dumps(menu(args.foundation), indent=1))
        return 0
    problems = verify()
    for p in problems:
        print("RIPOSTE_LIBRARY_PROBLEM", p)
    print("RIPOSTE_LIBRARY_VERIFY", "ok" if not problems else "%d problems" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
