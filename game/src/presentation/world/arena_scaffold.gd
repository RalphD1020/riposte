class_name ArenaScaffold
extends Node3D

## The duel space: Compatibility environment, a warm key and a cool rim light
## (no shadow maps), and the arena floor with its boundary ring, or the arena
## kit's authored scene. The floor stays calmer than the fighters (UX §80):
## richness lives on the perimeter and in the void, never under the fight.
## Visual only; the authoritative boundary is ArenaConstraints.
##
## See also: /docs/concepts/presentation.md

const RING_WIDTH := 0.08
## The boundary ring is a torus flattened to a painted line.
const RING_FLATTEN := 0.15
## A thick slab, so the cliff reads as a real drop from the gameplay camera.
const FLOOR_THICKNESS := 1.6
## The visible floor edge IS the physical cliff — no invisible margin.
const EDGE_STRIP_DROP := 0.02
const CIRCLE_SEGMENTS := 64
const CENTER_MARK_RADIUS := 0.3
## Home marks sit at each side's spawn, which is what makes the arena's
## north-south axis legible at a glance (SIDE-001).
const HOME_MARK_RADIUS := 0.75
const HOME_MARK_INNER := 0.55
const HOME_MARK_HEIGHT := 0.004
## Primitive perimeter: brazier posts just outside the platform, glowing by
## emission alone.
const BRAZIER_COUNT := 6
const BRAZIER_OFFSET := 0.9
const BRAZIER_SIZE := Vector3(0.36, 0.9, 0.36)
const BRAZIER_GLOW := 2.2
## Presentation floor slab under the platform top (m).
const GROUND_THICKNESS := 0.2


static func create(kit: PresentationKit, platform_radius: float, edge_warning_inset: float, spawn_offset: float) -> ArenaScaffold:
	var scaffold := ArenaScaffold.new()
	scaffold.name = "Arena"
	scaffold._build_environment()
	if kit.scene != null:
		## The authored arena brings the platform, cliff, and perimeter; the
		## warning ring and home marks still come from the rules, so they can
		## never drift from the boundary and spawns they mark.
		scaffold.add_child(kit.scene.instantiate())
		scaffold._build_ring(platform_radius, edge_warning_inset)
	else:
		scaffold._build_floor(platform_radius, edge_warning_inset)
		scaffold._build_perimeter(platform_radius)
	scaffold._build_home_marks(spawn_offset)
	scaffold._build_presentation_ground(platform_radius)
	return scaffold


## The platform top as a presentation-only surface, from the rules' radius on
## either arena path: a dropped sword lands on it inside the edge and falls past
## it outside. Nothing authoritative uses it (PresentationPhysicsLayers).
func _build_presentation_ground(platform_radius: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = platform_radius
	shape.height = GROUND_THICKNESS
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var ground := StaticBody3D.new()
	ground.name = "PresentationGround"
	ground.collision_layer = PresentationPhysicsLayers.PRESENTATION_GROUND
	ground.collision_mask = 0
	ground.position = Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)
	ground.add_child(collider)
	add_child(ground)


func presentation_ground() -> StaticBody3D:
	return get_node_or_null("PresentationGround") as StaticBody3D


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
	add_child(_light("KeyLight", RiposteTheme.WORLD_KEY, RiposteTheme.WORLD_KEY_ENERGY, RiposteTheme.WORLD_KEY_ROTATION_DEGREES))
	add_child(_light("RimLight", RiposteTheme.WORLD_RIM, RiposteTheme.WORLD_RIM_ENERGY, RiposteTheme.WORLD_RIM_ROTATION_DEGREES))


static func _light(light_name: String, color: Color, energy: float, rotation_deg: Vector3) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.rotation_degrees = rotation_deg
	light.shadow_enabled = false
	return light


func _build_floor(platform_radius: float, edge_warning_inset: float) -> void:
	## The slab: a stone top over a darker cliff face.
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = platform_radius
	floor_mesh.bottom_radius = platform_radius * 0.94
	floor_mesh.height = FLOOR_THICKNESS
	floor_mesh.radial_segments = CIRCLE_SEGMENTS
	_add("Cliff", floor_mesh, RiposteTheme.WORLD_CLIFF, Vector3(0.0, -FLOOR_THICKNESS * 0.5 - 0.002, 0.0))
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = platform_radius
	top_mesh.bottom_radius = platform_radius
	top_mesh.height = 0.004
	top_mesh.radial_segments = CIRCLE_SEGMENTS
	_add("Floor", top_mesh, RiposteTheme.WORLD_FLOOR, Vector3(0.0, -0.002, 0.0))
	_build_ring(platform_radius, edge_warning_inset)
	var mark_mesh := CylinderMesh.new()
	mark_mesh.top_radius = CENTER_MARK_RADIUS
	mark_mesh.bottom_radius = CENTER_MARK_RADIUS
	mark_mesh.height = 0.004
	_add("CenterMark", mark_mesh, RiposteTheme.WORLD_FLOOR_EDGE, Vector3(0.0, 0.003, 0.0))


## Warning ring: an etched, faintly glowing groove, plus the dropped edge
## strip out to the physical cliff.
func _build_ring(platform_radius: float, edge_warning_inset: float) -> void:
	var warning_radius := platform_radius - edge_warning_inset
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = warning_radius - RING_WIDTH * 0.5
	ring_mesh.outer_radius = warning_radius + RING_WIDTH * 0.5
	ring_mesh.rings = CIRCLE_SEGMENTS
	ring_mesh.ring_segments = 6
	var ring := _add("BoundaryRing", ring_mesh, RiposteTheme.WORLD_RING, Vector3(0.0, 0.01, 0.0), RiposteTheme.WORLD_RING_EMISSION)
	ring.scale = Vector3(1.0, RING_FLATTEN, 1.0)
	## Edge strip: annular disc between warning ring and platform edge.
	## Slightly dropped to create a visual depth cue at the cliff.
	if edge_warning_inset > 0.0:
		var edge_mesh := TorusMesh.new()
		edge_mesh.inner_radius = warning_radius
		edge_mesh.outer_radius = platform_radius
		edge_mesh.rings = CIRCLE_SEGMENTS
		edge_mesh.ring_segments = 4
		var edge := _add("EdgeStrip", edge_mesh, RiposteTheme.WORLD_FLOOR_EDGE, Vector3(0.0, -EDGE_STRIP_DROP, 0.0))
		edge.scale = Vector3(1.0, RING_FLATTEN, 1.0)


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


## Braziers stand off the platform, on the diagonals away from both spawns,
## so they frame the duel without ever sitting under it.
func _build_perimeter(platform_radius: float) -> void:
	var post := BoxMesh.new()
	post.size = BRAZIER_SIZE
	var radius := platform_radius + BRAZIER_OFFSET
	for i in BRAZIER_COUNT:
		var angle := TAU * (float(i) + 0.5) / float(BRAZIER_COUNT)
		var at := Vector3(cos(angle) * radius, BRAZIER_SIZE.y * 0.5 - 0.3, sin(angle) * radius)
		_add("Brazier%d" % i, post, RiposteTheme.WORLD_CLIFF, at)
		var flame := BoxMesh.new()
		flame.size = Vector3(BRAZIER_SIZE.x * 0.7, 0.12, BRAZIER_SIZE.z * 0.7)
		_add("BrazierGlow%d" % i, flame, RiposteTheme.WORLD_BRAZIER, at + Vector3(0.0, BRAZIER_SIZE.y * 0.5 + 0.06, 0.0), BRAZIER_GLOW)


func _add(mesh_name: String, mesh: Mesh, color: Color, offset: Vector3, emission: float = 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
