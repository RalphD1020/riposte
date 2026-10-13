class_name FighterShowcaseActor
extends Node3D

## A display-only fighter for the set's cinematic beats — the introduction and
## the winner's showcase. Built fresh from a resolved combatant kit through
## `CombatantVisuals` (body, skin, the side's colorway and accent; weapon,
## weapon skin, colorway), so it always wears exactly what the match proxy
## wore — and it is *never* a match proxy: no simulation pose drives it, no
## live combat state (flashes, IK history, a dropped sword) can leak into it,
## and nothing here can collide or score (PRES-INTRO-001, PRES-VICTORY-001).
##
## The sword it holds is a display sword. While the playing clip keys the
## rig's `SwordMount` bone, the sword rides that bone — true pitch, overhead
## guards, diagonal cuts, none of which the gameplay blade may show. Otherwise
## it sits at hand height and the director may turn it with `set_display_yaw`.
## Either way the hands follow it through the same two-hand IK as in a duel.
##
## Its clips run on an `AnimationPlayer` in manual mode, advanced only by
## `advance(delta)` from the director, so a cinematic is exact in headless
## tests and has no timer to outlive its screen. Directors orchestrate it; it
## has no notion of "intro" or "victory".
##
## See also: /docs/concepts/presentation.md

signal clip_finished(clip: StringName)

## The rig bone an authored cinematic clip drives the display sword with.
const SWORD_MOUNT_BONE := &"SwordMount"
const PRIMITIVE_HEIGHT := 1.4
## The mount bone's head is the pommel and it points down the blade; glTF bones
## point along local +Y, while a sword pivot lays its blade along local +Z.
const MOUNT_TO_PIVOT := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0))

var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var _combatant: CombatantPresentationKit
var _model: Node3D
var _animation: AnimationPlayer
var _rig: SwordRig3D
var _support := BodySupportPose.new()
var _pivot: Node3D
var _skeleton: Skeleton3D
var _mount_bone: int = -1
var _riding: bool = false
var _weapon_model: Node3D
var _blade_height: float = 1.0
var _clip: StringName = &""


static func create(combatant: CombatantPresentationKit, fighter_side: DuelSide.Id, push_radius: float, hilt: float, tip: float) -> FighterShowcaseActor:
	var actor := FighterShowcaseActor.new()
	actor.name = "ShowcaseActor"
	actor.side = fighter_side
	actor._combatant = combatant
	actor._blade_height = combatant.weapon.blade_height
	actor._build(push_radius, hilt, tip)
	return actor


func _build(push_radius: float, hilt: float, tip: float) -> void:
	_model = CombatantVisuals.body_model(_combatant, side)
	if _model != null:
		add_child(_model)
		_rig = _model as SwordRig3D
		_animation = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _animation != null:
			_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_animation.animation_finished.connect(_on_animation_finished)
	else:
		var body := MeshInstance3D.new()
		body.name = "Body"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = push_radius
		cylinder.bottom_radius = push_radius
		cylinder.height = PRIMITIVE_HEIGHT
		body.mesh = cylinder
		body.material_override = CombatantVisuals.material(RiposteTheme.body_for(side))
		body.position.y = PRIMITIVE_HEIGHT * 0.5
		add_child(body)
	_pivot = Node3D.new()
	_pivot.name = "DisplaySword"
	add_child(_pivot)
	_rest_pivot()
	var look := CombatantVisuals.weapon_look(_combatant, side, hilt, tip)
	_pivot.add_child(look)
	_weapon_model = look.get_child(0) as Node3D if look.get_child_count() > 0 and look.get_child(0).name == &"WeaponModel" else null
	_skeleton = _rig.skeleton() if _rig != null else null
	_mount_bone = _skeleton.find_bone(SWORD_MOUNT_BONE) if _skeleton != null else -1
	if _rig != null:
		_rig.bind_sword(_pivot, _weapon_model)


## Start `clip` from its first frame (no blend). Returns false when this body
## has no such clip; the primitive body never does.
func play(clip: StringName, looping: bool = false) -> bool:
	if _animation == null or clip == &"" or not _animation.has_animation(clip):
		return false
	var anim := _animation.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	_animation.play(clip, 0.0)
	_animation.seek(0.0, true)
	_clip = clip
	_riding = _mount_bone >= 0 and _keys_sword_mount(anim)
	if not _riding:
		_rest_pivot()
	_follow_mount()
	return true


func has_clip(clip: StringName) -> bool:
	return _animation != null and clip != &"" and _animation.has_animation(clip)


func current_clip() -> StringName:
	return _clip


func is_playing() -> bool:
	return _animation != null and _animation.is_playing()


## Advance the clip by `delta` seconds and let the body support the display
## sword. The only clock this actor has.
func advance(delta: float) -> void:
	if _animation != null and _clip != &"":
		_animation.advance(maxf(delta, 0.0))
	_follow_mount()
	if _rig != null:
		_rig.pose_sword(_support.sample(display_sword_angle()))


## Turn the hand-height display sword (radians about up, the gameplay
## convention). Ignored while a clip carries the sword on its mount.
func set_display_yaw(angle: float) -> void:
	if not rides_mount():
		_pivot.rotation.y = angle


func display_sword_angle() -> float:
	return wrapf(_pivot.global_rotation.y - global_rotation.y, -PI, PI) if is_inside_tree() else _pivot.rotation.y


func display_pivot() -> Node3D:
	return _pivot


## True while the playing clip drives the sword through `SwordMount`.
func rides_mount() -> bool:
	return _riding


func combatant_kit() -> CombatantPresentationKit:
	return _combatant


func model() -> Node3D:
	return _model


func rig() -> SwordRig3D:
	return _rig


func animation_player() -> AnimationPlayer:
	return _animation


## Carry the display sword on the mount bone's animated pose. The pivot keeps
## one parent for life (the IK targets under it are bound by path), so the
## bone's pose is copied onto it rather than the pivot being reparented.
func _follow_mount() -> void:
	if not _riding:
		return
	var bone := _skeleton.get_bone_global_pose(_mount_bone)
	var in_actor := _skeleton.transform * bone
	var host := _skeleton.get_parent() as Node3D
	while host != null and host != self:
		in_actor = host.transform * in_actor
		host = host.get_parent() as Node3D
	_pivot.transform = Transform3D(in_actor.basis.orthonormalized() * MOUNT_TO_PIVOT, in_actor.origin)


func _rest_pivot() -> void:
	_pivot.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _blade_height, 0.0))


static func _keys_sword_mount(anim: Animation) -> bool:
	for track in anim.get_track_count():
		if String(anim.track_get_path(track)).ends_with(":" + String(SWORD_MOUNT_BONE)):
			return true
	return false


func _on_animation_finished(clip: StringName) -> void:
	clip_finished.emit(clip)
