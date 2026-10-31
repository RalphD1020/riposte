"""Build manifests: the reproducibility record of one accepted model build.

A manifest names the profile it was built from (by content hash), the study
lineage and tool versions that produced it, the physical reference it was
scaled to, its key measurements, and the validation it passed. It never
decides acceptance: ``status`` stays ``pending`` until a person records it.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from .baseline import reference

SCHEMA = "riposte.build_manifest"
VERSION = 1
REQUIRED = ("profile", "profile_sha256", "status", "model", "study", "physical_baseline",
            "measurements", "validation")
STUDY_REQUIRED = ("lineage", "label", "generator_sha256", "blender")
BASELINE_TOLERANCE = 1e-9


def file_sha256(path):
    """Content hash with line endings normalized, so a checkout's CRLF does not move it."""
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def validate(data, directory):
    """Problems with a manifest whose profile sits in ``directory``."""
    if not isinstance(data, dict):
        return ["manifest must be an object"]
    problems = []
    if data.get("schema") != SCHEMA:
        problems.append("schema must be %s" % SCHEMA)
    if data.get("version") != VERSION:
        problems.append("version must be %s" % VERSION)
    problems += ["%s is required" % key for key in REQUIRED if key not in data]
    if problems:
        return problems
    if data["status"] not in ("study", "pending"):
        problems.append("status must be study or pending until a person accepts the build")
    profile = Path(directory) / data["profile"]
    if not profile.is_file():
        problems.append("profile %s does not exist" % data["profile"])
    elif file_sha256(profile) != data["profile_sha256"]:
        problems.append("profile %s changed since the manifest was written" % data["profile"])
    study = data["study"]
    problems += ["study.%s is required" % key for key in STUDY_REQUIRED if key not in study]
    expected = reference()
    stated = data["physical_baseline"]
    for key, value in expected.items():
        if not isinstance(stated.get(key), (int, float)) or abs(stated[key] - value) > BASELINE_TOLERANCE:
            problems.append("physical_baseline.%s must be Wolf's %s" % (key, value))
    return problems


def load_manifest(path):
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    problems = validate(data, path.parent)
    if problems:
        raise ValueError("%s: %s" % (path, "; ".join(problems)))
    return data
