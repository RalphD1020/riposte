"""A character's identity profile: the manifest's `art` block (CHARACTER-SOURCE-001).

One character manifest is the authority for what a character is; its `art` block is
the machine-readable part of the art direction that the assembly, the audits and a
Blender MCP task all read. It names the identity anchors every outfit keeps, and per
presentation (an outfit) its identity, its hairstyle and that hairstyle's design
regions, the constructions its garments may use, and its shoulder reinforcement.

These checks keep outfits from drifting away from the character. They never judge
whether the character looks good: that stays a person's approval at the gates.

Pure Python: no Blender.
"""

## What stays the character in every outfit; each anchor is a sentence an artist reads.
ANCHORS = ("face", "anatomy", "silhouette", "equipment")
## The garment construction vocabulary. A garment's `category` must be one of
## `garments.CATEGORIES`, the subset whose clearance profile exists; the rest enter
## that list with their profile, calibrated on the first asset of the construction.
CONSTRUCTIONS = ("fitted", "padded", "structured", "rigid", "fur", "loose", "accessory")
SHOULDER_REINFORCEMENT = ("none", "integrated_mantle")
## A design region outside the art profile's list that a hairstyle may still carry.
HAIR_ACCENTS = "accents"
OUTFIT_REQUIRED = ("identity", "hair", "hair_regions", "construction", "shoulder_reinforcement")


def problems(manifest, outfit=None, definitions=()):
    """Why the manifest's identity profile is inconsistent; with `outfit` and that
    outfit's asset `definitions`, also why that outfit drifts from it. Empty means consistent."""
    art = manifest.get("art")
    if not art:
        return ["%s has no art profile" % manifest.get("id", "?")]
    out = []
    anchors = art.get("anchors", {})
    out += ["art profile lacks the %s anchor" % a for a in ANCHORS if not anchors.get(a)]
    intrinsic = set(manifest["materials"]["intrinsic"])
    missing = sorted(intrinsic - set(manifest["identity"].get("palette", {})))
    if missing:
        out.append("the identity palette lacks the intrinsic materials %s" % missing)
    outfits = manifest["outfits"]
    profiled = art.get("outfits", {})
    for name in sorted(set(profiled) - set(outfits)):
        out.append("art profile describes an outfit %s the manifest does not have" % name)
    for name, row in sorted(outfits.items()):
        recolored = sorted(intrinsic & set(row.get("palette", {})))
        if recolored:
            out.append("outfit %s recolors identity materials %s" % (name, recolored))
        if row.get("complete") and name not in profiled:
            out.append("complete outfit %s has no art profile" % name)
    for name, entry in sorted(profiled.items()):
        out += _outfit_problems(name, entry)
    if outfit is not None and outfit in profiled:
        out += _worn_problems(outfit, profiled[outfit], definitions)
    return out


def _outfit_problems(name, entry):
    out = ["outfit %s: art profile lacks %s" % (name, key) for key in OUTFIT_REQUIRED if key not in entry]
    if out:
        return out
    if entry["shoulder_reinforcement"] not in SHOULDER_REINFORCEMENT:
        out.append("outfit %s: shoulder_reinforcement must be one of %s" % (name, SHOULDER_REINFORCEMENT))
    unknown = [c for c in entry["construction"] if c not in CONSTRUCTIONS]
    if unknown:
        out.append("outfit %s: unknown constructions %s" % (name, unknown))
    if "scalp" not in entry["hair_regions"]:
        out.append("outfit %s: a hairstyle is built on a scalp region" % name)
    return out


def _worn_problems(name, entry, definitions):
    """The assets actually worn in an outfit against its profile."""
    out = []
    by_id = {d["id"]: d for d in definitions}
    hair = by_id.get(entry.get("hair"))
    if hair is None or hair.get("type") != "hair":
        out.append("outfit %s does not wear its profiled hairstyle %s" % (name, entry.get("hair")))
    else:
        declared = set(hair["design"]["regions"])
        wanted = set(entry["hair_regions"])
        if wanted - declared:
            out.append("outfit %s: hairstyle %s lacks the design regions %s" % (name, hair["id"], sorted(wanted - declared)))
        extra = declared - wanted - {HAIR_ACCENTS}
        if extra:
            out.append("outfit %s: hairstyle %s has design regions %s outside the profile" % (name, hair["id"], sorted(extra)))
    for definition in definitions:
        if definition.get("type", "garment") == "garment" and definition["category"] not in entry["construction"]:
            out.append("outfit %s: %s is %s, not one of the outfit's constructions %s" % (
                name, definition["id"], definition["category"], entry["construction"]))
    return out
