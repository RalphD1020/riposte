class_name StructureContactGeometry
extends RefCounted

## Where one sword's blade meets the stage's structures (STRUCTURE-CONTACT-001).
## The blade is the same capsule every blade contact uses — `blade_base_radius`
## to `tip_radius` on the authoritative pose, `blade_radius` thick
## (BLADE-COLLISION-PARITY-001). The guard, the handle and the hands do not
## meet structures.
##
## Per shape, one candidate:
##
## - ARC: the farthest point of the blade from the arc's centre among the
##   points inside the arc's span — the blade's two ends and any point where it
##   crosses a span boundary, because distance from a point is convex along a
##   segment. Gap `R − |p − c| − blade_radius`; normal toward the centre.
## - SEGMENT: the closest points of the two segments. Gap
##   `distance − blade_radius − half_thickness`; normal from the wall's point
##   toward the blade's.
##
## The two deepest candidates within `reach` are kept, each a distinct
## feature (structure, shape); ties keep the earlier feature, so the order is
## the authored order and never a dictionary's. `least_gap` is over every
## shape, whatever `reach` is, for the lifecycle.
##
## See also: /docs/concepts/combat.md

const CAPACITY := StructureContactSet.CAPACITY

var count: int = 0
var least_gap: float = INF
var structure := PackedInt32Array([0, 0])
var shape := PackedInt32Array([0, 0])
var point_x := PackedFloat64Array([0.0, 0.0])
var point_y := PackedFloat64Array([0.0, 0.0])
var normal_x := PackedFloat64Array([0.0, 0.0])
var normal_y := PackedFloat64Array([0.0, 0.0])
var gap := PackedFloat64Array([0.0, 0.0])
var fraction := PackedFloat64Array([0.0, 0.0])
var _segment := SegmentContact.new()
## The last shape's candidate.
var _gap := INF
var _px := 0.0
var _py := 0.0
var _nx := 0.0
var _ny := 1.0
var _t := 0.0


## Measure the blade from (`hx`, `hy`) to (`tx`, `ty`).
func measure(hx: float, hy: float, tx: float, ty: float, blade_radius: float, structures: Array[StageObjectDef], reach: float) -> void:
	count = 0
	least_gap = INF
	for index in structures.size():
		var structure_def := structures[index]
		if not structure_def.blocks_blade:
			continue
		for part in structure_def.shapes.size():
			var piece := structure_def.shapes[part]
			if piece.kind == StructureShape.Kind.ARC:
				_arc(piece, hx, hy, tx, ty, blade_radius)
			else:
				_segment_shape(piece, hx, hy, tx, ty, blade_radius)
			if _gap < least_gap:
				least_gap = _gap
			if _gap <= reach:
				_keep(index, part)


func _keep(index: int, part: int) -> void:
	var at := count
	if count == CAPACITY:
		if _gap >= gap[CAPACITY - 1]:
			return
		at = CAPACITY - 1
	else:
		count += 1
	## Insert by gap; an equal gap stays behind the earlier feature.
	while at > 0 and gap[at - 1] > _gap:
		_copy(at - 1, at)
		at -= 1
	structure[at] = index
	shape[at] = part
	point_x[at] = _px
	point_y[at] = _py
	normal_x[at] = _nx
	normal_y[at] = _ny
	gap[at] = _gap
	fraction[at] = _t


func _copy(from: int, to: int) -> void:
	structure[to] = structure[from]
	shape[to] = shape[from]
	point_x[to] = point_x[from]
	point_y[to] = point_y[from]
	normal_x[to] = normal_x[from]
	normal_y[to] = normal_y[from]
	gap[to] = gap[from]
	fraction[to] = fraction[from]


func _arc(piece: StructureShape, hx: float, hy: float, tx: float, ty: float, blade_radius: float) -> void:
	_gap = INF
	_arc_candidate(piece, hx, hy, tx, ty, 0.0, blade_radius)
	_arc_candidate(piece, hx, hy, tx, ty, 1.0, blade_radius)
	_arc_boundary(piece, piece.from_x, piece.from_y, hx, hy, tx, ty, blade_radius)
	_arc_boundary(piece, piece.to_x, piece.to_y, hx, hy, tx, ty, blade_radius)


## Where the blade crosses the span boundary ray along (`ux`, `uy`).
func _arc_boundary(piece: StructureShape, ux: float, uy: float, hx: float, hy: float, tx: float, ty: float, blade_radius: float) -> void:
	var start := ux * (hy - piece.cy) - uy * (hx - piece.cx)
	var finish := ux * (ty - piece.cy) - uy * (tx - piece.cx)
	if (start > 0.0) == (finish > 0.0) or start == finish:
		return
	var t := start / (start - finish)
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	if ux * (px - piece.cx) + uy * (py - piece.cy) <= 0.0:
		return
	_arc_candidate(piece, hx, hy, tx, ty, t, blade_radius)


func _arc_candidate(piece: StructureShape, hx: float, hy: float, tx: float, ty: float, t: float, blade_radius: float) -> void:
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	var dx := px - piece.cx
	var dy := py - piece.cy
	var distance := SimMath.length(dx, dy)
	if distance <= SimMath.EPSILON or not piece.spans(dx, dy):
		return
	var candidate := piece.radius - distance - blade_radius
	if candidate >= _gap:
		return
	_gap = candidate
	_px = px
	_py = py
	_nx = -dx / distance
	_ny = -dy / distance
	_t = t


func _segment_shape(piece: StructureShape, hx: float, hy: float, tx: float, ty: float, blade_radius: float) -> void:
	SimMath.closest_segments(hx, hy, tx, ty, piece.ax, piece.ay, piece.bx, piece.by, _segment)
	_gap = _segment.distance - blade_radius - piece.half_thickness
	_px = _segment.ax
	_py = _segment.ay
	_t = _segment.s
	if _segment.distance > SimMath.EPSILON:
		_nx = (_segment.ax - _segment.bx) / _segment.distance
		_ny = (_segment.ay - _segment.by) / _segment.distance
		return
	## Crossing: push toward the side the blade's base is on.
	var wx := piece.bx - piece.ax
	var wy := piece.by - piece.ay
	var length := SimMath.length(wx, wy)
	_nx = -wy / length
	_ny = wx / length
	if _nx * (hx - piece.ax) + _ny * (hy - piece.ay) < 0.0:
		_nx = -_nx
		_ny = -_ny
