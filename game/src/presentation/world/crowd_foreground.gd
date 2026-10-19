class_name CrowdForeground
extends RefCounted

## A section is hidden when one of its projected corners lies on the fighting
## disc. The rectangle around that disc is not the window: stands beside the
## fight stay up. The arcade and the basin are not sections. Hiding does not
## change who is seated or whether they are cheering.
##
## See also: /docs/concepts/presentation.md

## Extra viewport fraction kept once a section is already hidden.
const MARGIN := 0.05
## Samples around the fighting disc, plus a point at blade height.
const DISC_SAMPLES := 8
const BLADE_HEIGHT := 1.2


static func project(camera: Camera3D, world_points: PackedVector3Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	var viewport := camera.get_viewport()
	if viewport == null:
		return projected
	var size := viewport.get_visible_rect().size
	if size.x <= 1.0 or size.y <= 1.0:
		return projected
	for world: Vector3 in world_points:
		if camera.is_position_behind(world):
			continue
		projected.append(camera.unproject_position(world) / size)
	return projected


static func disc_points(radius: float) -> PackedVector3Array:
	var worlds := PackedVector3Array()
	worlds.append(Vector3(0.0, BLADE_HEIGHT, 0.0))
	for index: int in DISC_SAMPLES:
		var angle := TAU * float(index) / float(DISC_SAMPLES)
		worlds.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return worlds


## A section overlaps the fight when one of its projected corners lies inside
## the disc's outline. Fewer than three combat samples fall back to their
## bounding box. Hysteresis grows the outline only after the section is hidden.
static func overlaps(section_points: PackedVector2Array, combat_points: PackedVector2Array, already_hidden: bool) -> bool:
	if section_points.is_empty() or combat_points.is_empty():
		return false
	var outline := _hull(combat_points)
	if outline.size() < 3:
		return _in_box(section_points, combat_points, already_hidden)
	if already_hidden:
		outline = _grow(outline, MARGIN)
	for point: Vector2 in section_points:
		if _inside(outline, point):
			return true
	return false


static func _in_box(section_points: PackedVector2Array, combat_points: PackedVector2Array, already_hidden: bool) -> bool:
	var bounds := _bounds(combat_points)
	if already_hidden:
		bounds = bounds.grow(MARGIN)
	for point: Vector2 in section_points:
		if bounds.has_point(point):
			return true
	return false


static func _bounds(points: PackedVector2Array) -> Rect2:
	var lo := points[0]
	var hi := points[0]
	for point: Vector2 in points:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)


static func _hull(points: PackedVector2Array) -> PackedVector2Array:
	var sorted: Array[Vector2] = []
	for point: Vector2 in points:
		var placed := sorted.size()
		for index: int in sorted.size():
			var other := sorted[index]
			if point.x < other.x or (is_equal_approx(point.x, other.x) and point.y < other.y):
				placed = index
				break
		sorted.insert(placed, point)
	var lower: Array[Vector2] = []
	var upper: Array[Vector2] = []
	for point: Vector2 in sorted:
		while lower.size() >= 2 and _turn(lower[lower.size() - 2], lower[lower.size() - 1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	for index: int in sorted.size():
		var point := sorted[sorted.size() - 1 - index]
		while upper.size() >= 2 and _turn(upper[upper.size() - 2], upper[upper.size() - 1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	if not lower.is_empty():
		lower.pop_back()
	if not upper.is_empty():
		upper.pop_back()
	var outline := PackedVector2Array()
	for point: Vector2 in lower:
		outline.append(point)
	for point: Vector2 in upper:
		outline.append(point)
	return outline


static func _grow(outline: PackedVector2Array, margin: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point: Vector2 in outline:
		center += point
	center /= float(outline.size())
	var grown := PackedVector2Array()
	for point: Vector2 in outline:
		var offset := point - center
		if offset.length() < 0.0001:
			grown.append(point)
		else:
			grown.append(point + offset.normalized() * margin)
	return grown


static func _inside(outline: PackedVector2Array, point: Vector2) -> bool:
	var previous := outline[outline.size() - 1]
	for current: Vector2 in outline:
		if _turn(previous, current, point) < 0.0:
			return false
		previous = current
	return true


static func _turn(origin: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - origin).cross(b - origin)
