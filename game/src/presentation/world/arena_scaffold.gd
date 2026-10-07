class_name ArenaScaffold
extends Node3D

## The duel space: Compatibility environment, one key light (no shadow maps),
## and the arena floor with its boundary ring, or the arena kit's authored
## scene. The floor stays calmer than the fighters (UX §80). Visual only; the
## authoritative boundary is ArenaConstraints.
##
## See also: /docs/concepts/presentation.md

const RING_WIDTH := 0.08
## The boundary ring is a torus flattened to a painted line.
const RING_FLATTEN := 0.15
const FLOOR_THICKNESS := 0.2
const FLOOR_MARGIN := 0.6
const CIRCLE_SEGMENTS := 64
const CENTER_MARK_RADIUS := 0.3
## Home marks sit at each side's spawn, which is what makes the arena's
## north-south axis legible at a glance (SIDE-001).
const HOME_MARK_RADIUS := 0.75
const HOME_MARK_INNER := 0.55
const HOME_MARK_HEIGHT := 0.004


static func create(kit: PresentationKit, arena_radius: float, spawn_offset: float) -> ArenaScaffold:
	var scaffold := ArenaScaffold.new()
	scaffold.name = "Arena"
	scaffold._build_environment()
	if kit.scene != null:
		scaffold.add_child(kit.scene.instantiate())
	else:
		scaffold._build_floor(arena_radius)
		scaffold._build_home_marks(spawn_offset)
	return scaffold


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = RiposteTheme.WORLD_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = RiposteTheme.WORLD_AMBIENT
	environment.ambient_light_energy = RiposteTheme.WORLD_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = RiposteTheme.WORLD_KEY
	key.light_energy = RiposteTheme.WORLD_KEY_ENERGY
	key.rotation_degrees = RiposteTheme.WORLD_KEY_ROTATION_DEGREES
	key.shadow_enabled = false
	add_child(key)


func _build_floor(arena_radius: float) -> void:
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = arena_radius + FLOOR_MARGIN
	floor_mesh.bottom_radius = arena_radius + FLOOR_MARGIN
	floor_mesh.height = FLOOR_THICKNESS
	floor_mesh.radial_segments = CIRCLE_SEGMENTS
	_add("Floor", floor_mesh, RiposteTheme.WORLD_FLOOR, Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = arena_radius - RING_WIDTH * 0.5
	ring_mesh.outer_radius = arena_radius + RING_WIDTH * 0.5
	ring_mesh.rings = CIRCLE_SEGMENTS
	ring_mesh.ring_segments = 6
	var ring := _add("BoundaryRing", ring_mesh, RiposteTheme.WORLD_RING, Vector3(0.0, 0.01, 0.0))
	ring.scale = Vector3(1.0, RING_FLATTEN, 1.0)
	var mark_mesh := CylinderMesh.new()
	mark_mesh.top_radius = CENTER_MARK_RADIUS
	mark_mesh.bottom_radius = CENTER_MARK_RADIUS
	mark_mesh.height = 0.004
	_add("CenterMark", mark_mesh, RiposteTheme.WORLD_FLOOR_EDGE, Vector3(0.0, 0.003, 0.0))


## One mark per end, at the spawn. Light's is a filled disc and Dark's is a
## ring, so the two ends read as different even without colour — side is
## never communicated by colour alone (SIDE-001).
func _build_home_marks(spawn_offset: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = HOME_MARK_RADIUS
	disc.bottom_radius = HOME_MARK_RADIUS
	disc.height = HOME_MARK_HEIGHT
	disc.radial_segments = CIRCLE_SEGMENTS
	_home_mark(DuelSide.Id.LIGHT_SOUTH, disc, RiposteTheme.WORLD_HOME_LIGHT, spawn_offset)
	var ring := TorusMesh.new()
	ring.inner_radius = HOME_MARK_INNER
	ring.outer_radius = HOME_MARK_RADIUS
	ring.rings = CIRCLE_SEGMENTS
	ring.ring_segments = 6
	_home_mark(DuelSide.Id.DARK_NORTH, ring, RiposteTheme.WORLD_HOME_DARK, spawn_offset).scale = Vector3(
		1.0, RING_FLATTEN, 1.0
	)


func _home_mark(side: DuelSide.Id, mesh: Mesh, tint: Color, spawn_offset: float) -> MeshInstance3D:
	var home := ArenaTransform.to_world(0.0, DuelSide.spawn_y(side, spawn_offset), HOME_MARK_HEIGHT)
	return _add("Home%s" % DuelSide.label(side), mesh, tint, home)


func _add(mesh_name: String, mesh: Mesh, color: Color, offset: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
