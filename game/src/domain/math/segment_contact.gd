class_name SegmentContact
extends RefCounted

## Reusable output of SimMath.closest_segments: segment parameters, closest
## points, and their distance. One instance per caller keeps hot loops free of
## allocations.
##
## See also: /docs/concepts/simulation.md

var s: float = 0.0
var t: float = 0.0
var ax: float = 0.0
var ay: float = 0.0
var bx: float = 0.0
var by: float = 0.0
var distance: float = 0.0
