class_name CrowdForeground
extends RefCounted

## Spectator sections whose projected bounds enter the combat window are
## hidden. The arcade and the basin are not sections. Hiding does not change
## who is seated or whether they are cheering.
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


## A section overlaps the fight when one of its projected corners lies in the
## projected disc. The disc moves with the camera. Hysteresis grows that
## window only after the section is already hidden.
static func overlaps(section_points: PackedVector2Array, combat_points: PackedVector2Array, already_hidden: bool) -> bool:
	if section_points.is_empty() or combat_points.is_empty():
		return false
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
