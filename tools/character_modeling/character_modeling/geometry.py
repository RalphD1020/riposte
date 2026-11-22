"""The canonical, order-independent geometry digest (CHARACTER-BUILD-001).

Two builds of the same inputs are geometrically equivalent when this digest matches, even
when `bmesh.ops.extrude_edge_only` enumerated faces in a different pointer-hash order. The
digest is a comparison tool, never a reason to mutate a mesh.

What it captures and what it deliberately does not:

- geometry: each face as its vertices' coordinates, rounded to `PRECISION` decimal places
  (0.01 mm), rotated to begin at its smallest coordinate so a re-indexed face matches;
- winding: the rotation preserves direction, so a reversed face does NOT match;
- per-face metadata the caller supplies (material index, `riposte_region`, `riposte_rim`);
- face multiplicity: the records are sorted but never de-duplicated, so a duplicated or
  removed face changes the digest.

It does NOT capture UVs, skin weights, normals or vertex-index order. Those are other
validation systems' concerns (rig/material validation, the GLB artifact hash); this stays a
geometry digest and MUST NOT grow into a general asset serializer.

Pure Python: no Blender. `male_base_v2.canonical_geometry` builds the face records from a
BMesh/mesh and calls this.
"""

from __future__ import annotations

import hashlib
import json

## Coordinate rounding for the canonical digest: 5 decimal places of a metre = 0.01 mm, the
## same precision as `male_base_v2.FINGERPRINT_DECIMALS`. A vertex that moves more than this
## changes the digest; a sub-0.01 mm wobble does not.
PRECISION = 5


def canonical_faces(vertices, faces, precision=PRECISION):
    """The sorted canonical records of a mesh (duplicates preserved, never de-duplicated).

    `vertices`: a sequence of (x, y, z). `faces`: an iterable of (vertex_index_sequence,
    metadata) where metadata is any JSON-able tuple the caller wants folded into identity
    (e.g. material index, region, rim flag). Each record is (rounded-coordinate ring rotated
    to its smallest vertex, metadata); the list is sorted so face-array order does not matter,
    and identical records are kept so multiplicity does."""
    co = [tuple(round(float(c), precision) for c in v) for v in vertices]
    records = []
    for verts, meta in faces:
        ring = [co[i] for i in verts]
        start = ring.index(min(ring))
        records.append([ring[start:] + ring[:start], list(meta)])
    records.sort()
    return records


def digest(payload):
    """A short sha256 of a JSON-able payload (stable key order)."""
    return hashlib.sha256(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()).hexdigest()


def mesh_digest(vertices, faces, materials=(), precision=PRECISION):
    """The canonical geometry digest of a mesh: its canonical faces and the material names
    their indices refer to (so two surfaces that coincide but carry different materials are
    not equal)."""
    return digest({"faces": canonical_faces(vertices, faces, precision), "materials": list(materials)})
