class_name ArenaSurfaceState
extends Node3D

## Sand over the wooden disc. A byte mask, stamped from the snapshot and the
## tick's events. Rounds keep it. A new presenter starts full. It never writes
## the simulation and it adds no collider.
##
## See also: /docs/concepts/presentation.md

const RESOLUTION := 256
const STRIDE := 0.75
const FOOT_OFFSET := 0.12
const WALK_RADIUS := 0.18
const WALK_STRENGTH := 50.0
const COMBAT_RADIUS := 0.20
const COMBAT_STRENGTH := 75.0
const BURST_LONG := 0.9
const BURST_LAT := 0.28
const BURST_STRENGTH := 120.0
const KILL_RADIUS := 1.0
const KILL_STRENGTH := 200.0
const TOP_THICKNESS := 0.004
const SIDE_DROP := 0.4
const SIDE_SEGMENTS := 64
const SHADER_PATH := "res://src/presentation/world/sand_surface.gdshader"

var _radius: float = 8.27
var _resolution: int = RESOLUTION
var _image: Image
var _texture: ImageTexture
var _dirty: bool = false
var _updates: int = 0
var _distance: PackedFloat32Array = PackedFloat32Array()
var _foot: PackedInt32Array = PackedInt32Array()


static func create(platform_radius: float, cell_count: int = RESOLUTION) -> ArenaSurfaceState:
	var surface := ArenaSurfaceState.new()
	surface.name = "SandSurface"
	surface._radius = platform_radius
	surface._resolution = maxi(cell_count, 2)
	surface._distance.resize(2)
	surface._foot.resize(2)
	surface._build()
	return surface


func resolution() -> int:
	return _resolution


func update_count() -> int:
	return _updates


func coverage_sim(sim_x: float, sim_y: float) -> int:
	var cell := _cell_for_sim(sim_x, sim_y)
	return _coverage(cell.x, cell.y)


func stamp_circle(center: Vector2, radius: float, strength: float) -> bool:
	return _stamp(center, Vector2.RIGHT, radius, radius, strength)


func stamp_ellipse(center: Vector2, along: Vector2, long_radius: float, lat_radius: float, strength: float) -> bool:
	return _stamp(center, along, long_radius, lat_radius, strength)


func consume(snapshot: PresentationSnapshot, events: Array[DuelEvent]) -> void:
	_bursts(snapshot, events)
	_strides(snapshot)
	_kills(events)
	flush()


func flush() -> void:
	if not _dirty or _texture == null or _image == null:
		return
	_texture.update(_image)
	_dirty = false
	_updates += 1


func _build() -> void:
	_image = Image.create(_resolution, _resolution, false, Image.FORMAT_R8)
	_image.fill(Color.WHITE)
	_texture = ImageTexture.create_from_image(_image)
	var shader := load(SHADER_PATH) as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("coverage", _texture)
	material.set_shader_parameter("sand_color", RiposteTheme.SAND)
	material.set_shader_parameter("wood_color", RiposteTheme.WOOD)
	material.set_shader_parameter("map_extent", _radius * 2.0)
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = _radius
	top_mesh.bottom_radius = _radius
	top_mesh.height = TOP_THICKNESS
	top_mesh.radial_segments = SIDE_SEGMENTS
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = top_mesh
	top.position = Vector3(0.0, -TOP_THICKNESS * 0.5, 0.0)
	top.material_override = material
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)
	var side := MeshInstance3D.new()
	side.name = "Side"
	side.mesh = _side_mesh()
	side.material_override = _wood()
	side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(side)


func _wood() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = RiposteTheme.WOOD
	material.roughness = 0.9
	material.metallic = 0.0
	return material


func _side_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lip := _radius + 0.01
	for index: int in SIDE_SEGMENTS:
		var a0 := TAU * float(index) / float(SIDE_SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SIDE_SEGMENTS)
		var p0 := Vector3(cos(a0) * lip, 0.0, sin(a0) * lip)
		var p1 := Vector3(cos(a1) * lip, 0.0, sin(a1) * lip)
		var q0 := Vector3(p0.x, -SIDE_DROP, p0.z)
		var q1 := Vector3(p1.x, -SIDE_DROP, p1.z)
		tool.add_vertex(p0)
		tool.add_vertex(q0)
		tool.add_vertex(p1)
		tool.add_vertex(p1)
		tool.add_vertex(q0)
		tool.add_vertex(q1)
	tool.generate_normals()
	return tool.commit()


func _bursts(snapshot: PresentationSnapshot, events: Array[DuelEvent]) -> void:
	for event: DuelEvent in events:
		if event.type != DuelEventTypes.BURST_STARTED:
			continue
		if event.actor < 0 or event.actor >= snapshot.fighters.size():
			continue
		var heading := Vector2(event.number(DuelEventKeys.HEADING_X), event.number(DuelEventKeys.HEADING_Y))
		if heading.length() < 0.01:
			continue
		var row := snapshot.fighter(event.actor)
		var center := Vector2(row.x, row.y)
		if not _inside(center):
			continue
		_stamp(center, heading, BURST_LONG, BURST_LAT, BURST_STRENGTH)
		_distance[event.actor] = 0.0


func _strides(snapshot: PresentationSnapshot) -> void:
	for slot: int in mini(snapshot.fighters.size(), 2):
		var row := snapshot.fighter(slot)
		var speed := SimMath.length(row.vx, row.vy)
		var center := Vector2(row.x, row.y)
		if not row.is_alive() or row.is_falling or not _inside(center) or speed < FighterAnimationSelector.MOVE_SPEED:
			continue
		_distance[slot] += speed * SimulationTimebase.TICK_SECONDS
		var committed := row.phase == CombatPhase.Id.CHARGING or CombatPhase.is_swinging(row.phase)
		while _distance[slot] >= STRIDE:
			_distance[slot] -= STRIDE
			_plant(row, committed)


func _plant(row: PresentationFighter, committed: bool) -> void:
	var side := 1.0 if _foot[row.slot] == 0 else -1.0
	_foot[row.slot] = 1 - _foot[row.slot]
	var right := Vector2(sin(row.facing), -cos(row.facing)) * FOOT_OFFSET * side
	var radius := COMBAT_RADIUS if committed else WALK_RADIUS
	var strength := COMBAT_STRENGTH if committed else WALK_STRENGTH
	stamp_circle(Vector2(row.x, row.y) + right, radius, strength)


func _kills(events: Array[DuelEvent]) -> void:
	for event: DuelEvent in events:
		if event.type != DuelEventTypes.FIGHTER_KILLED:
			continue
		var center := Vector2(event.number(DuelEventKeys.X), event.number(DuelEventKeys.Y))
		if _inside(center):
			stamp_circle(center, KILL_RADIUS, KILL_STRENGTH)
		if event.target >= 0 and event.target < _distance.size():
			_distance[event.target] = 0.0


func _stamp(center: Vector2, along: Vector2, long_radius: float, lat_radius: float, strength: float) -> bool:
	var heading := along.normalized() if along.length() > 0.001 else Vector2.RIGHT
	var reach := maxf(long_radius, lat_radius)
	var min_cell := _cell_for_sim(center.x - reach, center.y - reach)
	var max_cell := _cell_for_sim(center.x + reach, center.y + reach)
	var changed := false
	var y0 := mini(min_cell.y, max_cell.y)
	var y1 := maxi(min_cell.y, max_cell.y)
	var x0 := mini(min_cell.x, max_cell.x)
	var x1 := maxi(min_cell.x, max_cell.x)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			if not _in_grid(ix, iy):
				continue
			var at := _sim_for_cell(ix, iy)
			if not _inside(at):
				continue
			var offset := at - center
			var longitudinal := offset.dot(heading) / maxf(long_radius, 0.001)
			var lateral := offset.dot(Vector2(heading.y, -heading.x)) / maxf(lat_radius, 0.001)
			var distance := sqrt(longitudinal * longitudinal + lateral * lateral)
			if distance > 1.0:
				continue
			var blend := distance * distance * (3.0 - 2.0 * distance)
			var removal := roundi(strength * (1.0 - blend))
			if removal <= 0:
				continue
			var next := maxi(_coverage(ix, iy) - removal, 0)
			if next == _coverage(ix, iy):
				continue
			_image.set_pixel(ix, iy, Color(float(next) / 255.0, 0.0, 0.0))
			changed = true
	if changed:
		_dirty = true
	return changed


func _inside(sim_point: Vector2) -> bool:
	return SimMath.length(sim_point.x, sim_point.y) <= _radius


func _cell_for_sim(sim_x: float, sim_y: float) -> Vector2i:
	var world := ArenaTransform.to_world(sim_x, sim_y)
	var extent := _radius * 2.0
	var u := (world.x + _radius) / extent
	var v := (world.z + _radius) / extent
	return Vector2i(_clamp_cell(u), _clamp_cell(v))


func _sim_for_cell(ix: int, iy: int) -> Vector2:
	var extent := _radius * 2.0
	var world_x := (float(ix) + 0.5) / float(_resolution) * extent - _radius
	var world_z := (float(iy) + 0.5) / float(_resolution) * extent - _radius
	return ArenaTransform.to_plane(Vector3(world_x, 0.0, world_z))


func _clamp_cell(unit: float) -> int:
	return clampi(int(unit * float(_resolution)), 0, _resolution - 1)


func _in_grid(ix: int, iy: int) -> bool:
	return ix >= 0 and iy >= 0 and ix < _resolution and iy < _resolution


func _coverage(ix: int, iy: int) -> int:
	return clampi(roundi(_image.get_pixel(ix, iy).r * 255.0), 0, 255)
