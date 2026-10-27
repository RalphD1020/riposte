"""The mesh a diagnostic reads. Plain lists, no Blender.

A capture names one figure in figure-local metres: Z up, -Y forward, +X left,
the mirror plane at x = 0. Faces are vertex-index tuples (triangles or
polygons). ``face_flags`` marks approved features by face index — the face
panels, the centre ridge, and the panel-boundary curve — so a diagnostic can
exempt exactly those faces and nothing near them.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct

SCHEMA = "riposte.mesh_capture"
VERSION = 1
FLAG_FACE_PANEL = "face_panel"
FLAG_FACE_RIDGE = "face_ridge"
FLAG_FACE_V = "face_v"
FLAGS = (FLAG_FACE_PANEL, FLAG_FACE_RIDGE, FLAG_FACE_V)


class MeshData:
    """``hidden`` marks vertices buried inside another part (the neck top inside
    the skull). They shape nothing anyone can see, so creases and dents there
    are not reported; the outline is unaffected because they are inside."""

    def __init__(self, vertices, faces, face_flags=None, name="", hidden=None):
        self.vertices = [tuple(float(c) for c in v) for v in vertices]
        self.faces = [tuple(int(i) for i in f) for f in faces]
        self.face_flags = {key: set(value) for key, value in (face_flags or {}).items()}
        self.name = name
        self.hidden = set(hidden or ())
        unknown = sorted(set(self.face_flags) - set(FLAGS))
        if unknown:
            raise ValueError("unknown face flags: %s" % ", ".join(unknown))
        count = len(self.vertices)
        for face in self.faces:
            if len(face) < 3 or min(face) < 0 or max(face) >= count:
                raise ValueError("face %s does not index %d vertices" % (face, count))
        self._normals = None
        self._edges = None

    @classmethod
    def from_dict(cls, data):
        return cls(data["vertices"], data["faces"], data.get("face_flags"), data.get("name", ""),
                   data.get("hidden_vertices"))

    def to_dict(self):
        return {
            "name": self.name,
            "vertices": [[round(c, 6) for c in v] for v in self.vertices],
            "faces": [list(f) for f in self.faces],
            "face_flags": {key: sorted(value) for key, value in self.face_flags.items()},
            "hidden_vertices": sorted(self.hidden),
        }

    @classmethod
    def merged(cls, parts, name=""):
        vertices, faces, flags, hidden = [], [], {}, set()
        for part in parts:
            v0, f0 = len(vertices), len(faces)
            vertices.extend(part.vertices)
            faces.extend(tuple(i + v0 for i in f) for f in part.faces)
            for key, value in part.face_flags.items():
                flags.setdefault(key, set()).update(i + f0 for i in value)
            hidden.update(i + v0 for i in part.hidden)
        return cls(vertices, faces, flags, name, hidden)

    def flagged(self, face_index):
        return any(face_index in value for value in self.face_flags.values())

    def triangles(self):
        """Fan triangulation; yields (face_index, a, b, c)."""
        for index, face in enumerate(self.faces):
            for k in range(1, len(face) - 1):
                yield index, face[0], face[k], face[k + 1]

    def face_normals(self):
        """Unit normals (Newell) and areas, cached."""
        if self._normals is None:
            normals, areas = [], []
            verts = self.vertices
            for face in self.faces:
                nx = ny = nz = 0.0
                for k in range(len(face)):
                    x0, y0, z0 = verts[face[k]]
                    x1, y1, z1 = verts[face[(k + 1) % len(face)]]
                    nx += (y0 - y1) * (z0 + z1)
                    ny += (z0 - z1) * (x0 + x1)
                    nz += (x0 - x1) * (y0 + y1)
                length = math.sqrt(nx * nx + ny * ny + nz * nz)
                areas.append(0.5 * length)
                normals.append((nx / length, ny / length, nz / length) if length > 0.0 else (0.0, 0.0, 0.0))
            self._normals = (normals, areas)
        return self._normals

    def edges(self):
        """{(a, b) with a < b: [(face_index, forward), ...]}; forward is a -> b in the face winding."""
        if self._edges is None:
            edges = {}
            for index, face in enumerate(self.faces):
                for k in range(len(face)):
                    a, b = face[k], face[(k + 1) % len(face)]
                    key = (a, b) if a < b else (b, a)
                    edges.setdefault(key, []).append((index, a < b))
            self._edges = edges
        return self._edges

    def vertex_neighbors(self):
        neighbors = [set() for _ in self.vertices]
        for a, b in self.edges():
            neighbors[a].add(b)
            neighbors[b].add(a)
        return neighbors

    def vertex_normals(self):
        normals, areas = self.face_normals()
        acc = [[0.0, 0.0, 0.0] for _ in self.vertices]
        for index, face in enumerate(self.faces):
            nx, ny, nz = normals[index]
            w = areas[index]
            for vi in face:
                acc[vi][0] += nx * w
                acc[vi][1] += ny * w
                acc[vi][2] += nz * w
        out = []
        for x, y, z in acc:
            length = math.sqrt(x * x + y * y + z * z)
            out.append((x / length, y / length, z / length) if length > 0.0 else (0.0, 0.0, 0.0))
        return out

    def stats(self):
        return {"vertices": len(self.vertices), "faces": len(self.faces), "edges": len(self.edges())}

    def mesh_hash(self, precision=1e-5):
        """Identical for identical topology and positions within ``precision``."""
        digest = hashlib.sha256()
        scale = 1.0 / precision
        for v in self.vertices:
            digest.update(struct.pack("<3q", *(int(round(c * scale)) for c in v)))
        for f in self.faces:
            digest.update(struct.pack("<%di" % (len(f) + 1), len(f), *f))
        return digest.hexdigest()


def load_capture(path):
    data = json.loads(open(path, encoding="utf-8").read())
    if data.get("schema") != SCHEMA or data.get("version") != VERSION:
        raise ValueError("%s is not a %s v%d capture" % (path, SCHEMA, VERSION))
    return data


def capture_mesh(capture):
    return MeshData.merged([MeshData.from_dict(part) for part in capture["parts"]], capture.get("figure", ""))
