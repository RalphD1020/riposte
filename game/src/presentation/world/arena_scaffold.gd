class_name ArenaScaffold
extends Node3D

## The duel space: Compatibility environment, a warm key that may cast one
## directional shadow map and a cool rim that never does, and the arena floor,
## or the arena kit's authored scene. The kit's `StagePresentationProfile`
## says which ground, sky, marks, and shadow policy; nothing here compares a
## stage name. The only presentation collider is the sword floor, the same
## outline as the visible ground. It does not hold a fighter.
## `arena_floor.glb`, when present, used to replace the visible plug. The
## fighting surface is now the sand disc on this scaffold. The brick file
## stays on disk. `arena_bowl.glb` carries the arches and the treads. Neither
## mesh adds a collider. The authoritative boundary is ArenaConstraints.
##
## See also: /docs/concepts/presentation.md

## The dark home mark is a torus flattened to a painted line.
const RING_FLATTEN := 0.15
## A thick slab, so the missing-scene fallback reads as a drop.
const FLOOR_THICKNESS := 1.6
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
## Metres from the camera the key's orthogonal shadow map covers. The duel
## camera sits 14–18 m out and the bowl starts at the combat radius, so the
## far stone is about 26 m along the view. 24 m sharpened the map and clipped
## that wall. 32 m keeps the wall in the map. Desktop resolution is 2048, so
## the texel is still about half the old 1024-at-32 m shadow.
const KEY_SHADOW_DISTANCE := 32.0

var _crowd: CrowdStage
var _ripple: MeshInstance3D
## The visible ground in plan (world XZ). The sword floor and a fall's ledge.
var _outline := PackedVector2Array()


static func create(kit: PresentationKit, platform_radius: float, _edge_warning_inset: float, spawn_offset: float, crowd_seed: int = 1) -> ArenaScaffold:
	var scaffold := ArenaScaffold.new()
	scaffold.name = "Arena"
	var profile := profile_of(kit)
	scaffold._build_environment(profile)
	if profile.ground == StagePresentationProfile.Ground.DECK:
		## The deck kit's own scene. No sand, no bowl, no crowd. The mesh is not a collider.
		if kit.scene != null:
			var stage := kit.scene.instantiate()
			stage.name = "Deck"
			scaffold.add_child(stage)
			_cast(stage, profile.stage_casts)
		if profile.home_marks:
			scaffold._build_home_marks(spawn_offset)
		scaffold._outline = profile.deck_outline()
		scaffold._build_presentation_ground(scaffold._outline, platform_radius)
		return scaffold
	var layout := ArenaSection.load_layout()
	if kit != null and kit.scene != null:
		## The authored arena brings the old plug. The sand floor hides it.
		## The product pit does not paint a boundary ring.
		var stage := kit.scene.instantiate()
		scaffold.add_child(stage)
		scaffold._hide_stand_in(stage)
		scaffold._hide_replaced_disc(stage)
		scaffold.add_child(ArenaSurfaceState.create(platform_radius, layout))
	else:
		scaffold._build_floor(platform_radius)
		scaffold._build_perimeter(platform_radius)
	if profile.home_marks:
		scaffold._build_home_marks(spawn_offset)
	if layout.pit and layout.bay_count >= 3 and layout.issues().is_empty():
		for point: Vector3 in ArenaSurfaceState.rim_points(layout.bay_count, ArenaSurfaceState.face_distance(layout.wall_inner), layout.angular_zero):
			scaffold._outline.append(Vector2(point.x, point.z))
	scaffold._build_presentation_ground(scaffold._outline, platform_radius)
	var bowl := scaffold._build_bowl()
	if bowl != null:
		_cast(bowl, profile.stage_casts)
	if profile.crowd != null:
		scaffold._crowd = CrowdStage.create(profile.crowd, crowd_seed)
		scaffold.add_child(scaffold._crowd)
	return scaffold


## The kit's stage profile. A kit without one is the pit.
static func profile_of(kit: PresentationKit) -> StagePresentationProfile:
	if kit != null and kit.stage != null:
		return kit.stage
	return StagePresentationProfile.new()


## The visible ground in plan (world XZ), convex. Empty on a fallback disc.
func ground_outline() -> PackedVector2Array:
	return _outline


static func _cast(root: Node, casts: bool) -> void:
	var setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = setting
	for child: Node in root.get_children():
		_cast(child, casts)


## A dropped sword lands on this and nothing else. It is the visible ground's
## outline (the sand polygon, the deck octagon), not the combat radius. A
## fighter never reads it (PresentationPhysicsLayers). Without an outline it
## is one disc at the support radius.
func _build_presentation_ground(outline: PackedVector2Array, platform_radius: float) -> void:
	var collider := CollisionShape3D.new()
	if outline.size() >= 3:
		var shape := ConvexPolygonShape3D.new()
		var prism := PackedVector3Array()
		for point: Vector2 in outline:
			prism.append(Vector3(point.x, 0.0, point.y))
			prism.append(Vector3(point.x, -GROUND_THICKNESS, point.y))
		shape.points = prism
		collider.shape = shape
	else:
		scaffold_disc(collider, platform_radius)
	var ground := StaticBody3D.new()
	ground.name = "PresentationGround"
	ground.collision_layer = PresentationPhysicsLayers.PRESENTATION_GROUND
	ground.collision_mask = 0
	ground.add_child(collider)
	add_child(ground)


static func scaffold_disc(collider: CollisionShape3D, platform_radius: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = platform_radius
	shape.height = GROUND_THICKNESS
	collider.shape = shape
	collider.position = Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)


func presentation_ground() -> StaticBody3D:
	return get_node_or_null("PresentationGround") as StaticBody3D


func crowd() -> CrowdStage:
	return _crowd


func sand() -> ArenaSurfaceState:
	return get_node_or_null("SandSurface") as ArenaSurfaceState


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
	_ripple.position = Vector3(at.x, at.y + 0.04, at.z)
	_ripple.scale = Vector3(0.6, 0.15, 0.6)


func _build_bowl() -> Node:
	if not ResourceLoader.exists(BOWL_SCENE):
		return null
	var packed := load(BOWL_SCENE) as PackedScene
	if packed == null:
		return null
	var bowl := packed.instantiate()
	bowl.name = "Bowl"
	add_child(bowl)
	return bowl


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


func _build_environment(profile: StagePresentationProfile) -> void:
	var void_sky := profile.backdrop == StagePresentationProfile.Backdrop.VOID
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	if void_sky:
		## The duel camera looks down, so its void is the lower half: a faint
		## lift near the horizon, near-black under the deck. No sun disc.
		sky_material.sky_top_color = RiposteTheme.END_SKY
		sky_material.sky_horizon_color = RiposteTheme.END_VOID_HORIZON
		sky_material.sky_curve = RiposteTheme.END_VOID_CURVE
		sky_material.sky_energy_multiplier = 1.0
		sky_material.ground_bottom_color = RiposteTheme.END_VOID_DEEP
		sky_material.ground_horizon_color = RiposteTheme.END_VOID_HORIZON
		sky_material.ground_curve = RiposteTheme.END_VOID_CURVE
		sky_material.ground_energy_multiplier = 1.0
		sky_material.sun_angle_max = 0.0
		sky_material.sun_curve = 0.0
	else:
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
	## The void has no sun. The Arena key still draws the one disc.
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY if void_sky else DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	if profile.key_shadow:
		## One orthogonal split. Desktop map is 2048. Distance stays 32 m so the
		## bowl casts onto the floor from the far camera. Mobile stays 1024.
		## The filter stays hard: Compatibility's soft filter smears, and blur
		## does not run there.
		key.shadow_enabled = true
		key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		key.directional_shadow_max_distance = KEY_SHADOW_DISTANCE
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


func _build_floor(platform_radius: float) -> void:
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
