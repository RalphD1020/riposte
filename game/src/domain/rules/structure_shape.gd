class_name StructureShape
extends RefCounted

## One collision primitive of a stage structure, in the combat plane
## (STRUCTURE-CONTACT-001). Authored content, immutable once built. Only the
## shapes a shipped structure needs exist:
##
## ```text
## ARC      the inside face of a circle (centre, radius) over a span of less
##          than half a turn: solid beyond the radius, normal toward the centre.
##          A curved wall seen from the arena floor.
## SEGMENT  a thin wall from a to b, rounded at its ends by `half_thickness`,
##          solid on both sides. A jamb, a post seen edge-on.
## ```
##
## An arc owns only the directions inside its span; its ends are where a
## segment (a jamb) takes over, so a blade crossing a span boundary meets the
## jamb's face, never the arc from behind. The span is stored as the two unit
## directions of its ends, so the narrow phase never calls a trigonometric
## function.
##
## Implements: /spec/invariants.md#structure-contact-001
## See also: /docs/concepts/combat.md

enum Kind { ARC, SEGMENT }

var kind: Kind = Kind.ARC
## ARC: centre, radius, and the span from `from_x, from_y` turning
## counter-clockwise to `to_x, to_y`.
var cx: float = 0.0
var cy: float = 0.0
var radius: float = 0.0
var from_x: float = 1.0
var from_y: float = 0.0
var to_x: float = 1.0
var to_y: float = 0.0
## SEGMENT: its two ends and its half thickness.
var ax: float = 0.0
var ay: float = 0.0
var bx: float = 0.0
var by: float = 0.0
var half_thickness: float = 0.0


## The span is given by its two end directions (unit vectors from the centre).
static func arc(centre_x: float, centre_y: float, arc_radius: float, start_x: float, start_y: float, end_x: float, end_y: float) -> StructureShape:
	var shape := StructureShape.new()
	shape.kind = Kind.ARC
	shape.cx = centre_x
	shape.cy = centre_y
	shape.radius = arc_radius
	shape.from_x = start_x
	shape.from_y = start_y
	shape.to_x = end_x
	shape.to_y = end_y
	return shape


static func segment(start_x: float, start_y: float, end_x: float, end_y: float, half: float) -> StructureShape:
	var shape := StructureShape.new()
	shape.kind = Kind.SEGMENT
	shape.ax = start_x
	shape.ay = start_y
	shape.bx = end_x
	shape.by = end_y
	shape.half_thickness = half
	return shape


## Whether direction (`dx`, `dy`) from the centre lies inside the arc's span.
func spans(dx: float, dy: float) -> bool:
	return from_x * dy - from_y * dx >= 0.0 and dx * to_y - dy * to_x >= 0.0


func is_valid() -> bool:
	match kind:
		Kind.ARC:
			var unit_from := absf(SimMath.length(from_x, from_y) - 1.0) < 1.0e-9
			var unit_to := absf(SimMath.length(to_x, to_y) - 1.0) < 1.0e-9
			## Less than half a turn, so the span test above is exact.
			var turning := from_x * to_y - from_y * to_x
			return radius > 0.0 and is_finite(radius) and unit_from and unit_to and turning > 0.0
		Kind.SEGMENT:
			return SimMath.length(bx - ax, by - ay) > SimMath.EPSILON and half_thickness >= 0.0 and is_finite(half_thickness)
	return false
