class_name FighterPresentation3D
extends Node3D

## Passive fighter proxy built from the fighter and weapon kits. MatchPresenter
## poses it every frame; it never reads simulation state and never decides
## anything (PRES-001).
##
## Hierarchy: root (ground pose, yaw) → VisualRoot (kit transform, procedural
## motion) → body / outline / facing notch or the kit's authored scene;
## SwordPivot (hand height, relative sword yaw) → blade + guard; Shadow and
## ChargeRing stay on the ground outside VisualRoot. The blade ignores depth so
## its position is always readable (UX §18).
##
## See also: /docs/concepts/presentation.md

const SHADOW_HEIGHT := 0.012
const RING_HEIGHT := 0.02
const RING_GAP := 0.14
const RING_WIDTH := 0.06
const RING_SEGMENTS := 32
## Tessellation of the primitive cylinders. Low on purpose: this is a mobile
## budget, and an authored kit scene replaces these meshes entirely.
const RADIAL_SEGMENTS := 24
const OUTLINE_GROW := 0.028
const FLASH_SECONDS := 0.12
## Peak emission of the hit flash (scaled down by Reduced Flash).
const FLASH_ENERGY := 1.6
const DEATH_SECONDS := 0.45
const DEATH_TILT := 1.35
const FALL_SPEED := 8.0
const FALL_TILT := 0.4
const STAGGER_WOBBLE := 0.09
const STAGGER_WOBBLE_RATE := 30.0
const CHARGE_CROUCH := 0.06
## High Contrast Weapons thickens the blade outline (UX §55).
const HIGH_CONTRAST_OUTLINE := Vector3(2.2, 1.6, 1.0)
## Ground speed (m/s) above which the MOVE clip plays.
const MOVE_SPEED := 0.6
## A jump this large in one frame is a teleport (round reset), not movement.
const TELEPORT_DISTANCE := 1.0

var slot: int = 0
var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var _fighter_kit: PresentationKit
var _weapon_kit: PresentationKit
var _hilt: float = 0.0
var _tip: float = 0.0
var _visual_root: Node3D
var _body_material: StandardMaterial3D
var _sword_pivot: Node3D
var _blade_core: StandardMaterial3D
var _blade_edge: StandardMaterial3D
var _blade_outline: MeshInstance3D
var _charge_ring: MeshInstance3D
var _charge_mesh: ImmediateMesh
var _animation: AnimationPlayer
var _flash: float = 0.0
var _flash_scale: float = 1.0
var _death: float = 0.0
var _fall_offset: float = 0.0
var _is_falling: bool = false
var _time: float = 0.0
var _shown_charge: float = -1.0
var _semantic: StringName = &""
var _ground_speed: float = 0.0
var _posed: bool = false


static func create(
	fighter_slot: int,
	fighter_side: DuelSide.Id,
	fighter_kit: PresentationKit,
	weapon_kit: PresentationKit,
	body_radius: float,
	hilt_radius: float,
	tip_radius: float
) -> FighterPresentation3D:
	var proxy := FighterPresentation3D.new()
	proxy.name = "Fighter%d" % fighter_slot
	proxy.slot = fighter_slot
	proxy.side = fighter_side
	proxy._fighter_kit = fighter_kit
	proxy._weapon_kit = weapon_kit
	proxy._hilt = hilt_radius
	proxy._tip = tip_radius
	proxy._build(body_radius)
	return proxy


func body_color() -> Color:
	return RiposteTheme.body_for(side)


func outline_color() -> Color:
	return RiposteTheme.outline_for(side)


func blade_color() -> Color:
	return RiposteTheme.blade_for(side)


## Pose for this frame. `facing` and `weapon_angle` are gameplay radians.
func apply_pose(world: Vector3, facing: float, weapon_angle: float, charge: float, phase: CombatPhase.Id, alive: bool, falling: bool, delta: float) -> void:
	_time += delta
	var step := world.distance_to(position) if _posed else 0.0
	_ground_speed = step / delta if delta > 0.0 and step < TELEPORT_DISTANCE else 0.0
	_posed = true
	_is_falling = falling
	if _is_falling:
		_fall_offset += FALL_SPEED * delta
	else:
		_fall_offset = 0.0
	position = world - Vector3(0.0, _fall_offset, 0.0)
	rotation.y = ArenaTransform.yaw(facing)
	_sword_pivot.rotation.y = weapon_angle
	_flash = maxf(_flash - delta, 0.0)
	_death = clampf(_death + (delta / DEATH_SECONDS if not alive else -_death), 0.0, 1.0)
	_animate(charge, phase, alive)
	_update_charge_ring(charge if phase == CombatPhase.Id.CHARGING else 0.0)
	if _body_material != null:
		_body_material.emission_energy_multiplier = (_flash / FLASH_SECONDS) * FLASH_ENERGY * _flash_scale


## World positions of the blade's hilt and tip (for trails and effects).
func blade_points() -> PackedVector3Array:
	var origin := _sword_pivot.global_transform
	return PackedVector3Array([origin * Vector3(0.0, 0.0, _hilt), origin * Vector3(0.0, 0.0, _tip)])


func blade_height() -> float:
	return _weapon_kit.blade_height


func flash_hit(flash_scale: float) -> void:
	_flash = FLASH_SECONDS
	_flash_scale = flash_scale


func set_charge_indicator(visible_now: bool) -> void:
	_charge_ring.visible = visible_now


func set_high_contrast(enabled: bool) -> void:
	_blade_core.albedo_color = RiposteTheme.BLADE_HIGH_CONTRAST_CORE if enabled else blade_color()
	_blade_outline.scale = HIGH_CONTRAST_OUTLINE if enabled else Vector3.ONE


func is_falling() -> bool:
	return _is_falling


func fall_offset() -> float:
	return _fall_offset


func current_semantic() -> StringName:
	return _semantic


func _build(body_radius: float) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.transform = _fighter_kit.visual_transform
	add_child(_visual_root)
	if _fighter_kit.scene != null:
		_build_scene()
	else:
		_build_primitive_body(body_radius)
	_build_sword()
	_build_ground(body_radius)


func _build_scene() -> void:
	var model := _fighter_kit.scene.instantiate()
	_visual_root.add_child(model)
	_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for target in _fighter_kit.color_targets:
		var mesh := model.find_child(target, true, false) as MeshInstance3D
		if mesh != null:
			mesh.material_override = _material(body_color(), false)


func _build_primitive_body(body_radius: float) -> void:
	var height := _fighter_kit.body_height
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = body_radius
	body_mesh.bottom_radius = body_radius
	body_mesh.height = height
	body_mesh.radial_segments = RADIAL_SEGMENTS
	_body_material = _material(body_color(), false)
	_body_material.emission_enabled = true
	_body_material.emission = RiposteTheme.CRITICAL
	_body_material.emission_energy_multiplier = 0.0
	_add_mesh(_visual_root, "Body", body_mesh, _body_material, Vector3(0.0, height * 0.5, 0.0))
	var outline_mesh := CylinderMesh.new()
	outline_mesh.top_radius = body_radius + OUTLINE_GROW
	outline_mesh.bottom_radius = body_radius + OUTLINE_GROW
	outline_mesh.height = height + OUTLINE_GROW
	outline_mesh.radial_segments = RADIAL_SEGMENTS
	var outline := _material(outline_color(), true)
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_add_mesh(_visual_root, "Outline", outline_mesh, outline, Vector3(0.0, height * 0.5, 0.0))
	var notch_mesh := BoxMesh.new()
	notch_mesh.size = Vector3(body_radius * 0.6, 0.05, body_radius * 0.55)
	_add_mesh(_visual_root, "FacingNotch", notch_mesh, _material(outline_color(), true), Vector3(0.0, height + 0.01, body_radius * 0.55))


func _build_sword() -> void:
	_sword_pivot = Node3D.new()
	_sword_pivot.name = "SwordPivot"
	_sword_pivot.position = Vector3(0.0, _weapon_kit.blade_height, 0.0)
	_visual_root.add_child(_sword_pivot)
	var length := _tip - _hilt
	var center := Vector3(0.0, 0.0, _hilt + length * 0.5)
	var outline_mesh := BoxMesh.new()
	outline_mesh.size = Vector3(_weapon_kit.blade_width + 0.03, 0.03, length + 0.03)
	_blade_edge = _material(RiposteTheme.BLADE_OUTLINE, true)
	_x_ray(_blade_edge, 0)
	_blade_outline = _add_mesh(_sword_pivot, "BladeOutline", outline_mesh, _blade_edge, center)
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(_weapon_kit.blade_width, 0.035, length)
	_blade_core = _material(blade_color(), true)
	_x_ray(_blade_core, 1)
	_add_mesh(_sword_pivot, "Blade", blade_mesh, _blade_core, center)
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.2, 0.04, 0.04)
	var guard := _material(RiposteTheme.BLADE_OUTLINE, true)
	_x_ray(guard, 0)
	_add_mesh(_sword_pivot, "Guard", guard_mesh, guard, Vector3(0.0, 0.0, _hilt))


func _build_ground(body_radius: float) -> void:
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = body_radius * 1.2
	shadow_mesh.bottom_radius = body_radius * 1.2
	shadow_mesh.height = 0.002
	shadow_mesh.radial_segments = RADIAL_SEGMENTS
	var shadow := _material(RiposteTheme.SHADOW, true)
	shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_mesh(self, "Shadow", shadow_mesh, shadow, Vector3(0.0, SHADOW_HEIGHT, 0.0))
	_charge_mesh = ImmediateMesh.new()
	_charge_ring = MeshInstance3D.new()
	_charge_ring.name = "ChargeRing"
	_charge_ring.mesh = _charge_mesh
	_charge_ring.material_override = _material(RiposteTheme.CHARGE_RING, true)
	_charge_ring.position = Vector3(0.0, RING_HEIGHT, 0.0)
	_charge_ring.visible = false
	_charge_ring.set_meta("inner", body_radius + RING_GAP)
	add_child(_charge_ring)


## Primitive kits get procedural motion; authored scenes play mapped clips.
func _animate(charge: float, phase: CombatPhase.Id, alive: bool) -> void:
	var semantic := PresentationKit.ANIM_IDLE
	if not alive:
		semantic = PresentationKit.ANIM_DEATH
	elif phase == CombatPhase.Id.STAGGER:
		semantic = PresentationKit.ANIM_STAGGER
	elif _flash > 0.0:
		semantic = PresentationKit.ANIM_HIT
	elif phase == CombatPhase.Id.CHARGING:
		semantic = PresentationKit.ANIM_CHARGE
	elif CombatPhase.is_striking(phase):
		semantic = PresentationKit.ANIM_SWING
	elif _ground_speed > MOVE_SPEED:
		semantic = PresentationKit.ANIM_MOVE
	_semantic = semantic
	if _animation != null:
		var clip := _fighter_kit.clip_for(semantic)
		if clip != &"" and _animation.has_animation(clip) and _animation.current_animation != clip:
			_animation.play(clip)
		return
	var tilt := DEATH_TILT * _death
	var fall_tilt := FALL_TILT * clampf(_fall_offset, 0.0, 1.0) if _is_falling else 0.0
	var wobble := sin(_time * STAGGER_WOBBLE_RATE) * STAGGER_WOBBLE if semantic == PresentationKit.ANIM_STAGGER else 0.0
	_visual_root.rotation = Vector3(tilt + fall_tilt, 0.0, wobble)
	_visual_root.scale = Vector3(1.0, 1.0 - CHARGE_CROUCH * charge, 1.0)


func _update_charge_ring(charge: float) -> void:
	if not _charge_ring.visible or is_equal_approx(charge, _shown_charge):
		return
	_shown_charge = charge
	_charge_mesh.clear_surfaces()
	if charge <= 0.0:
		return
	var inner := float(_charge_ring.get_meta("inner"))
	var outer := inner + RING_WIDTH
	var segments := maxi(2, ceili(RING_SEGMENTS * charge))
	_charge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var angle := TAU * charge * float(i) / float(segments)
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		_charge_mesh.surface_add_vertex(direction * inner)
		_charge_mesh.surface_add_vertex(direction * outer)
	_charge_mesh.surface_end()


static func _material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Always drawn on top so the blade reads through bodies.
static func _x_ray(material: StandardMaterial3D, priority: int) -> void:
	material.no_depth_test = true
	material.render_priority = priority


static func _add_mesh(parent: Node3D, mesh_name: String, mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
