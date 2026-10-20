class_name ArenaScaffold
extends Node3D

## The duel space: Compatibility environment, a warm key and a cool rim light
## (no shadow maps), and the arena floor with its boundary ring, or the arena
## kit's authored scene. The combat disc is the only presentation collider.
## `arena_floor.glb`, when present, used to replace the visible plug. The
## fighting surface is now the sand disc on this scaffold. The brick file
## stays on disk. `arena_bowl.glb` carries the arches and the treads. Neither
## mesh adds a collider. The authoritative boundary is ArenaConstraints.
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
const BOWL_SCENE := "res://assets/generated/arenas/arena_bowl.glb"

var _crowd: CrowdStage
var _ripple: MeshInstance3D


static func create(kit: PresentationKit, platform_radius: float, edge_warning_inset: float, spawn_offset: float, crowd_seed: int = 1) -> ArenaScaffold:
	var scaffold := ArenaScaffold.new()
	scaffold.name = "Arena"
	scaffold._build_environment()
	var layout := ArenaSection.load_layout()
	if kit.scene != null:
		## The authored arena brings the platform, cliff, and perimeter; the
		## warning ring and home marks still come from the rules. The sand disc
		## hides that plug. The brick glb stays the previous surface.
		var stage := kit.scene.instantiate()
		scaffold.add_child(stage)
		scaffold._hide_stand_in(stage)
		scaffold._hide_replaced_disc(stage)
		scaffold.add_child(ArenaSurfaceState.create(platform_radius))
		var curb := layout.curb_inner_radius if layout.issues().is_empty() else -1.0
		scaffold._build_ring(platform_radius, edge_warning_inset, curb)
	else:
		scaffold._build_floor(platform_radius, edge_warning_inset)
		scaffold._build_perimeter(platform_radius)
	scaffold._build_home_marks(spawn_offset)
	scaffold._build_presentation_ground(platform_radius)
	scaffold._build_bowl()
	scaffold._crowd = CrowdStage.create(crowd_seed, platform_radius)
	scaffold.add_child(scaffold._crowd)
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


func crowd() -> CrowdStage:
	return _crowd


func react(cue: StringName, excitement: float) -> void:
	if _crowd != null:
		_crowd.react(cue, excitement)


func hold_chant(active: bool) -> void:
	if _crowd != null:
		_crowd.hold_chant(active)


func focus_chant(side: DuelSide.Id) -> void:
	if _crowd != null:
		_crowd.focus_on_side(side)


func advance(delta: float, camera: Camera3D, reduced_motion: bool) -> void:
	if _crowd != null:
		_crowd.advance(delta, camera, reduced_motion)


func reset_poses() -> void:
	if _crowd != null:
		_crowd.reset_poses()


func ripple_at(at: Vector3) -> void:
	if _ripple == null:
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.35
		mesh.outer_radius = 0.7
		mesh.rings = 16
		mesh.ring_segments = 4
		_ripple = MeshInstance3D.new()
		_ripple.name = "Ripple"
		_ripple.mesh = mesh
		_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = RiposteTheme.STONE_BASIN
		material.roughness = 0.35
		_ripple.material_override = material
		add_child(_ripple)
	_ripple.visible = true
	_ripple.position = Vector3(at.x, RingOutWater.SURFACE_Y + 0.04, at.z)
	_ripple.scale = Vector3(0.6, 0.15, 0.6)


func _build_bowl() -> void:
	if not ResourceLoader.exists(BOWL_SCENE):
		return
	var packed := load(BOWL_SCENE) as PackedScene
	if packed == null:
		return
	var bowl := packed.instantiate()
	bowl.name = "Bowl"
	add_child(bowl)


## Temporary. These prefixes are the ornamental stand-ins in the disc glb.
## The bowl is a sibling and is not walked. Hiding is not a substitute for
## deleting those objects from `standard_arena.blend` once the import names
## are checked and the bowl is accepted. `standard_arena.glb` stays the rollback.
const STAND_IN_PREFIXES: PackedStringArray = ["Pillar", "Banner", "Fragment", "Relief", "Rubble", "Brazier"]


## The old disc plug. Hidden only while the replacement floor is instanced.
## These are not ornamental stand-ins: without the new floor they are the stage.
const REPLACED_DISC: PackedStringArray = ["PlatformTop", "PlatformCliff", "PlatformUnderside", "SpawnNorth", "SpawnSouth"]


static func is_replaced_disc(label: String) -> bool:
	if label.begins_with("Motif"):
		return true
	for disc_name: String in REPLACED_DISC:
		if label == disc_name:
			return true
	return false


static func is_stand_in(label: String) -> bool:
	for prefix: String in STAND_IN_PREFIXES:
		if label.begins_with(prefix):
			return true
	return false


func _hide_stand_in(node: Node) -> void:
	for child: Node in node.get_children():
		_hide_stand_in(child)
		if child is Node3D and is_stand_in(String(child.name)):
			(child as Node3D).visible = false
			child.queue_free()


func _hide_replaced_disc(node: Node) -> void:
	for child: Node in node.get_children():
		_hide_replaced_disc(child)
		if child is Node3D and is_replaced_disc(String(child.name)):
			(child as Node3D).visible = false
			child.queue_free()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = RiposteTheme.SKY_TOP
	sky_material.sky_horizon_color = RiposteTheme.SKY_HORIZON
	sky_material.sky_curve = RiposteTheme.SKY_CURVE
	sky_material.sky_energy_multiplier = RiposteTheme.SKY_ENERGY
	sky_material.ground_bottom_color = RiposteTheme.SKY_GROUND
	sky_material.ground_horizon_color = RiposteTheme.SKY_GROUND_HORIZON
	sky_material.ground_curve = RiposteTheme.SKY_GROUND_CURVE
	sky_material.ground_energy_multiplier = RiposteTheme.SKY_GROUND_ENERGY
	sky_material.sun_angle_max = RiposteTheme.SKY_SUN_ANGLE_MAX
	sky_material.sun_curve = RiposteTheme.SKY_SUN_CURVE
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = RiposteTheme.WORLD_AMBIENT
	environment.ambient_light_energy = RiposteTheme.WORLD_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)
	## The key owns the sun disc. The rim stays a fill, so the sky has one sun.
	var key := _light("KeyLight", RiposteTheme.WORLD_KEY, RiposteTheme.WORLD_KEY_ENERGY, RiposteTheme.WORLD_KEY_ROTATION_DEGREES)
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(key)
	var rim := _light("RimLight", RiposteTheme.WORLD_RIM, RiposteTheme.WORLD_RIM_ENERGY, RiposteTheme.WORLD_RIM_ROTATION_DEGREES)
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim)


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
func _build_ring(platform_radius: float, edge_warning_inset: float, curb_inner: float = -1.0) -> void:
	var warning_radius := platform_radius - edge_warning_inset
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = warning_radius - RING_WIDTH * 0.5
	ring_mesh.outer_radius = warning_radius + RING_WIDTH * 0.5
	ring_mesh.rings = CIRCLE_SEGMENTS
	ring_mesh.ring_segments = 6
	var ring := _add("BoundaryRing", ring_mesh, RiposteTheme.WORLD_RING, Vector3(0.0, 0.01, 0.0), RiposteTheme.WORLD_RING_EMISSION)
	ring.scale = Vector3(1.0, RING_FLATTEN, 1.0)
	## Edge strip: annular disc between warning ring and platform edge.
	## With the raised curb, it stops at the curb's inner edge and sits on
	## the paving instead of climbing the lip.
	if edge_warning_inset > 0.0:
		var edge_outer := platform_radius
		var edge_y := -EDGE_STRIP_DROP
		if curb_inner > 0.0:
			edge_outer = minf(curb_inner, platform_radius)
			edge_y = 0.012
		var edge_mesh := TorusMesh.new()
		edge_mesh.inner_radius = warning_radius
		edge_mesh.outer_radius = edge_outer
		edge_mesh.rings = CIRCLE_SEGMENTS
		edge_mesh.ring_segments = 4
		var edge := _add("EdgeStrip", edge_mesh, RiposteTheme.WORLD_FLOOR_EDGE, Vector3(0.0, edge_y, 0.0))
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
