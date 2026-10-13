"""Post-export GLB compaction (no bpy): drop animation channels that only ever
hold their node's rest value, then repack the accessors and binary they used.

Blender's exporter writes every bone's translation, rotation and scale for
every action, so each clip carries dozens of channels that never leave the
rest pose (every scale track, every bone a clip does not move). In Godot a
bone an animation does not track is posed at its rest, so such a channel adds
nothing but bytes — mostly glTF JSON, which dominated the fighter's size.
A channel that holds a constant *non-rest* value (a support clip's held
stance legs) is kept: dropping it would change the pose.

Deterministic: kept channels, samplers, accessors and buffer views keep their
original order, so the same input always produces the same file.

See also: /docs/reference/assets.md
"""

import json
import struct

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
FLOAT = 5126
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
REST = {"translation": (0.0, 0.0, 0.0), "rotation": (0.0, 0.0, 0.0, 1.0), "scale": (1.0, 1.0, 1.0)}
TOLERANCE = 1e-6


def _read(path):
    with open(path, "rb") as handle:
        data = handle.read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("%s is not a GLB" % path)
    offset = 12
    gltf, binary = None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + length]
        if kind == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif kind == CHUNK_BIN:
            binary = chunk
        offset += 8 + length
    return gltf, binary


def _write(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + (8 + len(binary) if binary else 0)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, 2, total))
        handle.write(struct.pack("<II", len(text), CHUNK_JSON))
        handle.write(text)
        if binary:
            handle.write(struct.pack("<II", len(binary), CHUNK_BIN))
            handle.write(binary)


def _floats(gltf, binary, index):
    accessor = gltf["accessors"][index]
    if accessor["componentType"] != FLOAT:
        return None
    view = gltf["bufferViews"][accessor["bufferView"]]
    width = COMPONENTS[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = struct.unpack_from("<%df" % (accessor["count"] * width), binary, start)
    return [values[i:i + width] for i in range(0, len(values), width)]


def _node_rest(node, path):
    return tuple(node.get(path, REST[path]))


def _is_rest(samples, rest, path):
    for value in samples:
        if path == "rotation":
            ## q and -q are the same rotation.
            if abs(sum(a * b for a, b in zip(value, rest))) < 1.0 - TOLERANCE:
                return False
        elif any(abs(a - b) > TOLERANCE for a, b in zip(value, rest)):
            return False
    return True


def _prune_channels(gltf, binary):
    removed = 0
    for animation in gltf.get("animations", []):
        kept = []
        for channel in animation["channels"]:
            target = channel["target"]
            path = target.get("path")
            sampler = animation["samplers"][channel["sampler"]]
            samples = _floats(gltf, binary, sampler["output"]) if path in REST else None
            if samples is not None and _is_rest(samples, _node_rest(gltf["nodes"][target["node"]], path), path):
                removed += 1
                continue
            kept.append(channel)
        if not kept:
            ## glTF requires a channel; a clip that never leaves rest keeps one.
            kept = animation["channels"][:1]
            removed -= 1
        used = sorted({c["sampler"] for c in kept})
        remap = {old: new for new, old in enumerate(used)}
        animation["samplers"] = [animation["samplers"][i] for i in used]
        for channel in kept:
            channel["sampler"] = remap[channel["sampler"]]
        animation["channels"] = kept
    return removed


def _used_accessors(gltf):
    used = set()
    for mesh in gltf.get("meshes", []):
        for primitive in mesh["primitives"]:
            used.update(primitive.get("attributes", {}).values())
            if "indices" in primitive:
                used.add(primitive["indices"])
            for target in primitive.get("targets", []):
                used.update(target.values())
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            used.add(skin["inverseBindMatrices"])
    for animation in gltf.get("animations", []):
        for sampler in animation["samplers"]:
            used.update((sampler["input"], sampler["output"]))
    return used


def _repack(gltf, binary):
    """Keep only referenced accessors and their views, in original order."""
    used = sorted(_used_accessors(gltf))
    accessor_map = {old: new for new, old in enumerate(used)}
    accessors = [gltf["accessors"][i] for i in used]
    views_used = sorted({a["bufferView"] for a in accessors if "bufferView" in a})
    images = [img["bufferView"] for img in gltf.get("images", []) if "bufferView" in img]
    views_used = sorted(set(views_used) | set(images))
    view_map = {old: new for new, old in enumerate(views_used)}
    packed = bytearray()
    views = []
    for old in views_used:
        view = dict(gltf["bufferViews"][old])
        start = view.get("byteOffset", 0)
        chunk = binary[start: start + view["byteLength"]]
        packed += b"\0" * (-len(packed) % 4)
        view["byteOffset"] = len(packed)
        packed += chunk
        views.append(view)
    for accessor in accessors:
        if "bufferView" in accessor:
            accessor["bufferView"] = view_map[accessor["bufferView"]]
    for image in gltf.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
    for mesh in gltf.get("meshes", []):
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: accessor_map[v] for k, v in primitive.get("attributes", {}).items()}
            if "indices" in primitive:
                primitive["indices"] = accessor_map[primitive["indices"]]
            primitive["targets"] = [{k: accessor_map[v] for k, v in t.items()} for t in primitive.get("targets", [])] or None
            if primitive["targets"] is None:
                del primitive["targets"]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    for animation in gltf.get("animations", []):
        for sampler in animation["samplers"]:
            sampler["input"] = accessor_map[sampler["input"]]
            sampler["output"] = accessor_map[sampler["output"]]
    gltf["accessors"] = accessors
    gltf["bufferViews"] = views
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(packed)
    return bytes(packed)


def compact(path):
    """Compact the GLB at `path` in place; returns the channels removed."""
    gltf, binary = _read(path)
    if not gltf.get("animations"):
        return 0
    removed = _prune_channels(gltf, binary)
    binary = _repack(gltf, binary)
    _write(path, gltf, binary)
    return removed
