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
## A cut-down fighter folds or sinks; a run-through one pitches harder. These
## shape the per-style death collapse so a slash and a stab death read apart.
const DEATH_KNEE_SINK := 0.45
const DEATH_STAB_PITCH := 1.2
const DEATH_CRUMPLE_PITCH := 1.1
const DEATH_WRITHE := 0.12
const DEATH_WRITHE_RATE := 8.0
const FALL_SPEED := 8.0
const FALL_TILT := 0.4
const STAGGER_WOBBLE := 0.09
const STAGGER_WOBBLE_RATE := 30.0
const CHARGE_CROUCH := 0.06
## Procedural stand-ins for clips, so a primitive kit still shows every
## semantic: a lean into footwork, a deeper lean into a dash, a carried-past
## twist on overswing, and a recoil on a hurt.
const MOVE_LEAN := 0.08
const DASH_LEAN := 0.2
const OVERSWING_TWIST := 0.18
const HURT_RECOIL := 0.16
const CRITICAL_RECOIL := 0.3
## A flinch outlasts the flash so it reads as a body reaction, not a blink.
const HURT_SECONDS := 0.22
const CRITICAL_SECONDS := 0.4
## The striker of a killing thrust holds the run-through for the kill beat
## (through the lethal slow motion and the victim's collapse).
const FINISHER_SECONDS := 0.9
## Once the sword leaves the hands, the arms ease off the empty grip over this.
const GRIP_RELEASE_SECONDS := 0.15
## Cross-fade between clips. Short on purpose: block joints snap into poses.
const BLEND_SECONDS := 0.06
## Over an authored blade, the x-ray blade is a ghost: visible through bodies,
## faint over the steel itself.
const BLADE_GHOST_ALPHA := 0.32
## High Contrast Weapons thickens the blade outline (UX §55).
const HIGH_CONTRAST_OUTLINE := Vector3(2.2, 1.6, 1.0)

var slot: int = 0
var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var _combatant: CombatantPresentationKit
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
var _rig: SwordRig3D
var _guard := GuardPoseField.new()
var _weapon_model: Node3D
var _flash: float = 0.0
var _flash_scale: float = 1.0
var _hurt: float = 0.0
var _critical: float = 0.0
var _finisher: float = 0.0
var _death: float = 0.0
var _death_style: StringName = DeathPresentationProfile.STYLE_DEAD_DROP
var _fall_offset: float = 0.0
var _is_falling: bool = false
var _fall_request: FallPresentationRequest
var _fall_time: float = 0.0
var _weapon_dropped: bool = false
var _grip_release: float = 0.0
var _time: float = 0.0
var _shown_charge: float = -1.0
var _semantic: StringName = &""
var _playing_clip: StringName = &""


static func create(
	fighter_slot: int,
	fighter_side: DuelSide.Id,
	combatant: CombatantPresentationKit,
	body_radius: float,
	hilt_radius: float,
	tip_radius: float
) -> FighterPresentation3D:
	var proxy := FighterPresentation3D.new()
	proxy.name = "Fighter%d" % fighter_slot
	proxy.slot = fighter_slot
	proxy.side = fighter_side
	proxy._combatant = combatant
	proxy._fighter_kit = combatant.fighter
	proxy._weapon_kit = combatant.weapon
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


## Pose for this frame. `world`, `facing`, and `weapon_angle` are the
## interpolated pose; `row` is the latest snapshot's facts for this fighter.
func apply_pose(world: Vector3, facing: float, weapon_angle: float, row: PresentationFighter, delta: float) -> void:
	_time += delta
	_is_falling = row.is_falling
	if not _is_falling:
		_fall_offset = 0.0
		_fall_time = 0.0
		_fall_request = null
		position = world
	elif _fall_request != null:
		## Authority stopped at the ledge; the fall owns the root from here,
		## carrying the real exit momentum outward under presentation gravity.
		_fall_time += delta
		position = _fall_request.root_at(_fall_time)
		_fall_offset = _fall_request.exit_position.y - position.y
	else:
		_fall_offset += FALL_SPEED * delta
		position = world - Vector3(0.0, _fall_offset, 0.0)
	rotation.y = ArenaTransform.yaw(facing)
	_sword_pivot.rotation.y = weapon_angle
	if _rig != null:
		_guard.update(weapon_angle)
		_rig.pose_sword(weapon_angle, row.phase, _guard.band())
	if _weapon_dropped:
		if row.is_alive() and not row.is_falling:
			_restore_weapon()
		else:
			_grip_release = maxf(_grip_release - delta, 0.0)
			if _rig != null:
				_rig.set_grip_influence(_grip_release / GRIP_RELEASE_SECONDS)
	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_critical = maxf(_critical - delta, 0.0)
	_finisher = maxf(_finisher - delta, 0.0)
	_death = clampf(_death + (delta / DEATH_SECONDS if not row.is_alive() else -_death), 0.0, 1.0)
	_animate(row)
	_update_charge_ring(row.charge if row.phase == CombatPhase.Id.CHARGING else 0.0)
	if _body_material != null:
		_body_material.emission_energy_multiplier = (_flash / FLASH_SECONDS) * FLASH_ENERGY * _flash_scale


## World positions of the blade's hilt and tip (for trails and effects).
func blade_points() -> PackedVector3Array:
	var origin := _sword_pivot.global_transform
	return PackedVector3Array([origin * Vector3(0.0, 0.0, _hilt), origin * Vector3(0.0, 0.0, _tip)])


func blade_height() -> float:
	return _weapon_kit.blade_height


## A resolved strike landed on this fighter. `critical` picks the heavier
## flinch; neither moves the body, which stays where the state says.
func flash_hit(flash_scale: float, critical: bool = false) -> void:
	_flash = FLASH_SECONDS
	_flash_scale = flash_scale
	_hurt = HURT_SECONDS
	if critical:
		_critical = CRITICAL_SECONDS


## The killing blow landed: latch the death collapse for this fighter. Called
## once, on the blow that leaves them not alive, so the style is fixed for the
## whole fall. The snapshot's `is_alive` keeps them down; this only chooses how.
func begin_death(family: DeathPresentationProfile.Family, key: int) -> void:
	_death_style = _fighter_kit.death_style(family, key)


## This fighter's thrust killed: hold the run-through for the kill beat. Only
## the death backend calls this, and only for a killing thrust.
func begin_finisher() -> void:
	_finisher = FINISHER_SECONDS


func is_finishing() -> bool:
	return _finisher > 0.0


## The hands let go: hide the held sword and return a copy of its look, laid out
## along +Z from the hilt like the pivot, for a presentation body to carry. The
## pivot itself stays where the simulation put it; only its look is hidden.
func detach_weapon() -> Node3D:
	var look := Node3D.new()
	look.name = "WeaponLook"
	var source: Node3D = _weapon_model if _weapon_model != null else _sword_pivot.get_node_or_null("Blade") as Node3D
	if source != null:
		look.add_child(source.duplicate())
	_sword_pivot.visible = false
	_weapon_dropped = true
	_grip_release = GRIP_RELEASE_SECONDS
	return look


func is_weapon_dropped() -> bool:
	return _weapon_dropped


## How the presented body is moving now (world, m/s): along the fall trajectory
## over the edge, still for a collapse in place. A released sword starts with
## this, so it leaves the hand moving with the body that held it.
func root_velocity() -> Vector3:
	if _is_falling and _fall_request != null:
		return _fall_request.exit_velocity + Vector3(0.0, -FallPresentationRequest.GRAVITY * _fall_time, 0.0)
	return Vector3.ZERO


func _restore_weapon() -> void:
	_weapon_dropped = false
	_grip_release = 0.0
	_sword_pivot.visible = true
	if _rig != null:
		_rig.set_grip_influence(1.0)


## This fighter went over the edge: from now until the next round the fall owns
## the root, along the momentum they carried out. The first request wins; a
## fighter falls once.
func begin_fall(request: FallPresentationRequest) -> void:
	if _fall_request == null:
		_fall_request = request
		_fall_time = 0.0


## The simulation-posed blade mount. Authored rigs aim their hands at
## markers under it (two-hand IK); nothing may write its transform back.
func sword_pivot() -> Node3D:
	return _sword_pivot


func visual_root() -> Node3D:
	return _visual_root


## The authored rig, when the kit scene has one (two-hand IK + chest follow).
func rig() -> SwordRig3D:
	return _rig


func weapon_model() -> Node3D:
	return _weapon_model


func set_charge_indicator(visible_now: bool) -> void:
	_charge_ring.visible = visible_now


func set_high_contrast(enabled: bool) -> void:
	var alpha := _blade_core.albedo_color.a
	_blade_core.albedo_color = Color(RiposteTheme.BLADE_HIGH_CONTRAST_CORE if enabled else blade_color(), 1.0 if enabled else alpha)
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
	var scene := _combatant.body_scene()
	if scene != null:
		_build_scene(scene)
	else:
		_build_primitive_body(body_radius)
	_build_sword()
	_build_ground(body_radius)


func _build_scene(scene: PackedScene) -> void:
	var model := scene.instantiate()
	_visual_root.add_child(model)
	if _combatant.fighter_skin != null:
		_combatant.fighter_skin.apply(model)
	## Colorway before the side accent, so the SideAccent channel always wins
	## and side stays legible even in a mirror (COLORWAY).
	_apply_colorway(model)
	_rig = model as SwordRig3D
	_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation != null:
		for semantic in PresentationKit.LOOPING_SEMANTICS:
			var clip := _fighter_kit.clip_for(semantic)
			if clip != &"" and _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	## An authored body keeps its own palette; only its accent pieces take the
	## side's colour — the same pair the HUD's side bars use.
	for target in _fighter_kit.color_targets:
		var mesh := model.find_child(target, true, false) as MeshInstance3D
		if mesh != null:
			mesh.material_override = _material(RiposteTheme.accent_for(side), false)


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
	var weapon_scene := _combatant.weapon_scene()
	if weapon_scene != null:
		_weapon_model = weapon_scene.instantiate() as Node3D
		_weapon_model.name = "WeaponModel"
		_sword_pivot.add_child(_weapon_model)
		if _combatant.weapon_skin != null:
			_combatant.weapon_skin.apply(_weapon_model)
		## The weapon follows the fighter's colorway (COLORWAY).
		_apply_colorway(_weapon_model)
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
	if _weapon_model != null:
		## The authored steel is the look; the x-ray blade stays as a faint
		## ghost so the sword still reads through bodies (combat-critical).
		for ghost: StandardMaterial3D in [_blade_edge, _blade_core]:
			ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost.albedo_color.a = BLADE_GHOST_ALPHA
	else:
		var guard_mesh := BoxMesh.new()
		guard_mesh.size = Vector3(0.2, 0.04, 0.04)
		var guard := _material(RiposteTheme.BLADE_OUTLINE, true)
		_x_ray(guard, 0)
		_add_mesh(_sword_pivot, "Guard", guard_mesh, guard, Vector3(0.0, 0.0, _hilt))
	if _rig != null:
		_rig.bind_sword(_sword_pivot, _weapon_model)


## The combatant's colorway override for this side (empty for DEFAULT), by
## authored material name, on either the body or the weapon model.
func _apply_colorway(model: Node) -> void:
	var profile := _combatant.colorway()
	if profile == null:
		return
	profile.apply(model, ColorwayResolver.variant_for(side, _combatant.mirror))


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


## Authored scenes play the mapped clip; a semantic with no clip, and every
## primitive kit, gets the procedural stand-in so nothing freezes.
## The procedural collapse for a death style, as (pitch, roll, sink) over the
## 0→1 death ramp. Pure, so a slash death (backward drop) and a stab death
## (pitched forward, run through) are provably distinct silhouettes. Positive
## pitch falls backward, negative folds forward; sink lowers the body. An
## authored DEATH clip, when a kit maps one, overrides all of this upstream.
static func death_pose(style: StringName, progress: float, time: float) -> Vector3:
	var d := clampf(progress, 0.0, 1.0)
	match style:
		DeathPresentationProfile.STYLE_KNEES_FLOP:
			return Vector3(-DEATH_TILT * d, 0.0, DEATH_KNEE_SINK * d)
		DeathPresentationProfile.STYLE_GROUND_WRITHE:
			return Vector3(-DEATH_TILT * d, sin(time * DEATH_WRITHE_RATE) * DEATH_WRITHE * d, DEATH_KNEE_SINK * 0.5 * d)
		DeathPresentationProfile.STYLE_STAB_CRUMPLE:
			return Vector3(-DEATH_TILT * DEATH_CRUMPLE_PITCH * d, 0.0, DEATH_KNEE_SINK * d)
		DeathPresentationProfile.STYLE_STAB_PITCH:
			return Vector3(-DEATH_TILT * DEATH_STAB_PITCH * d, 0.0, 0.0)
		_:
			return Vector3(DEATH_TILT * d, 0.0, 0.0)


## The clip this body plays for `semantic`. A death plays the clip authored for
## its latched style when this scene has it (a run-through and a cut-down fall
## differently), else the generic DEATH clip; the striker of a killing thrust
## holds the authored run-through rather than the dash lunge, which returns to
## guard on its own. Every other semantic maps directly.
func animation_clip(semantic: StringName) -> StringName:
	if _animation != null:
		var special := &""
		if semantic == PresentationKit.ANIM_DEATH:
			special = _fighter_kit.death_clip(_death_style)
		elif semantic == PresentationKit.ANIM_DASH_FORWARD and _finisher > 0.0:
			special = _fighter_kit.finisher_clip()
		if special != &"" and _animation.has_animation(special):
			return special
	return _fighter_kit.clip_for(semantic)


func animation_player() -> AnimationPlayer:
	return _animation


func _animate(row: PresentationFighter) -> void:
	var semantic := FighterAnimationSelector.select(row, _hurt > 0.0, _critical > 0.0, _finisher > 0.0)
	_semantic = semantic
	if _animation != null:
		var clip := animation_clip(semantic)
		if clip != &"" and _animation.has_animation(clip):
			## Start a clip when it changes, never because the last one ended:
			## a finished one-shot clears `current_animation`, and replaying it
			## then would stand a dead body back up to fall again.
			if _playing_clip != clip:
				_animation.play(clip, BLEND_SECONDS)
				_playing_clip = clip
			return
		_playing_clip = &""
	var pitch := 0.0
	var roll := 0.0
	var twist := 0.0
	var sink := 0.0
	if not row.is_alive():
		var collapse := death_pose(_death_style, _death, _time)
		pitch = collapse.x
		roll = collapse.y
		sink = collapse.z
	if _is_falling:
		pitch += FALL_TILT * clampf(_fall_offset, 0.0, 1.0)
	match semantic:
		PresentationKit.ANIM_STAGGER:
			roll = sin(_time * STAGGER_WOBBLE_RATE) * STAGGER_WOBBLE
		PresentationKit.ANIM_MOVE_FORWARD:
			pitch -= MOVE_LEAN
		PresentationKit.ANIM_MOVE_BACKWARD:
			pitch += MOVE_LEAN
		PresentationKit.ANIM_ORBIT_LEFT:
			roll -= MOVE_LEAN
		PresentationKit.ANIM_ORBIT_RIGHT:
			roll += MOVE_LEAN
		PresentationKit.ANIM_DASH_FORWARD:
			pitch -= DASH_LEAN
		PresentationKit.ANIM_DASH_BACK:
			pitch += DASH_LEAN
		PresentationKit.ANIM_DASH_LEFT:
			roll -= DASH_LEAN
		PresentationKit.ANIM_DASH_RIGHT:
			roll += DASH_LEAN
		PresentationKit.ANIM_OVERSWING:
			twist = OVERSWING_TWIST * -row.swing_dir
		PresentationKit.ANIM_HURT:
			pitch += HURT_RECOIL * (_hurt / HURT_SECONDS)
		PresentationKit.ANIM_CRITICAL:
			pitch += CRITICAL_RECOIL * (_critical / CRITICAL_SECONDS)
	var scale_y := clampf(1.0 - CHARGE_CROUCH * row.charge - sink, 0.1, 1.0)
	var pose := Basis.from_euler(Vector3(pitch, twist, roll)).scaled(Vector3(1.0, scale_y, 1.0))
	_visual_root.transform = _fighter_kit.visual_transform * Transform3D(pose, Vector3.ZERO)


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
