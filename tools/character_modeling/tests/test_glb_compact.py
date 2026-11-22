"""GLB compaction keeps every buffer view an accessor reads, sparse ones included.

`tools/blender/glb_compact.py` (pure Python, no Blender) prunes rest-only animation channels and
repacks the binary. The exporter writes morph targets as sparse accessors, whose indices and
values live in their own buffer views; a repack that keeps only `accessor.bufferView` drops
them and the asset no longer imports (Godot: "Sparse indices were out of bounds").
"""

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "blender"))
import glb_compact  # noqa: E402


def _glb(gltf, binary):
    path = Path(tempfile.mkdtemp()) / "fixture.glb"
    glb_compact._write(str(path), gltf, binary)
    return path


def _fixture():
    """A mesh whose morph target is sparse (2 of 3 vertices moved) and a clip with one
    rest-only channel (pruned) and one moving channel (kept)."""
    positions = struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0)
    times = struct.pack("<2f", 0.0, 1.0)
    rest_rotation = struct.pack("<8f", 0, 0, 0, 1, 0, 0, 0, 1)
    moving = struct.pack("<6f", 0, 0, 0, 0, 0.5, 0)
    sparse_indices = struct.pack("<2H", 0, 2) + b"\0\0"
    sparse_values = struct.pack("<6f", 0.1, 0, 0, 0, 0.2, 0)
    chunks = [positions, times, rest_rotation, moving, sparse_indices, sparse_values]
    views, binary = [], b""
    for chunk in chunks:
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(chunk)})
        binary += chunk
    gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"componentType": 5126, "count": 3, "type": "VEC3",
             "sparse": {"count": 2, "indices": {"bufferView": 4, "componentType": 5123},
                        "values": {"bufferView": 5}}},
        ],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 4}]}]}],
        "nodes": [{"mesh": 0}],
        "animations": [{"channels": [{"sampler": 0, "target": {"node": 0, "path": "rotation"}},
                                     {"sampler": 1, "target": {"node": 0, "path": "translation"}}],
                        "samplers": [{"input": 1, "output": 2}, {"input": 1, "output": 3}]}],
    }
    return gltf, binary, sparse_indices, sparse_values


def _sparse_bytes(gltf, binary):
    sparse = next(a for a in gltf["accessors"] if "sparse" in a)["sparse"]
    out = []
    for part in ("indices", "values"):
        view = gltf["bufferViews"][sparse[part]["bufferView"]]
        out.append(binary[view["byteOffset"]: view["byteOffset"] + view["byteLength"]])
    return out


class SparseAccessors(unittest.TestCase):
    def test_compaction_prunes_rest_channels_and_keeps_sparse_views(self):
        ## ARRANGE: the fixture imports as authored.
        gltf, binary, indices, values = _fixture()
        self.assertEqual(_sparse_bytes(gltf, binary), [indices, values])
        path = _glb(gltf, binary)
        ## ACT
        removed = glb_compact.compact(str(path))
        ## ASSERT: the rest-only rotation is gone, the moving channel stays, and the sparse
        ## accessor still reads its own indices and values.
        packed, data = glb_compact._read(str(path))
        self.assertEqual(removed, 1)
        self.assertEqual([c["target"]["path"] for c in packed["animations"][0]["channels"]], ["translation"])
        self.assertEqual(_sparse_bytes(packed, data), [indices, values])
        for accessor in packed["accessors"]:
            for view in glb_compact._views_of(accessor):
                self.assertLess(view, len(packed["bufferViews"]))

    def test_a_repack_that_ignores_sparse_views_is_detected(self):
        ## PERTURB: the pre-fix repack (only `accessor.bufferView`) drops the sparse views.
        gltf, binary, indices, values = _fixture()
        original = glb_compact._views_of
        glb_compact._views_of = lambda a: [a["bufferView"]] if "bufferView" in a else []
        try:
            path = _glb(gltf, binary)
            glb_compact.compact(str(path))
            packed, data = glb_compact._read(str(path))
            broken = _sparse_bytes(packed, data) != [indices, values]
        except (IndexError, KeyError):
            broken = True
        finally:
            glb_compact._views_of = original
        ## ASSERT: the dropped views either fail the repack or leave the accessor misread.
        self.assertTrue(broken)


if __name__ == "__main__":
    unittest.main()
