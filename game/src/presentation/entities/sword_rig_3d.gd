class_name SwordRig3D
extends Node3D

## Rig glue for an authored fighter scene: the hands follow the sword, never
## the reverse. Attach to the root of a fighter wrapper scene; the proxy calls
## `bind_sword` once with its simulation-posed `SwordPivot` and the weapon's
## display model, then `pose_sword` every frame with the authoritative angle.
##
## Stack on the Skeleton3D, in order: animation (feet, hips, spine, head) →
## KineticChainModifier3D (chest → spine → hips follow the sword in decreasing
## shares, head counter-rotates to the opponent — the Mittelhut/Mittelhau
## support) → TwoBoneIK3D (both hands locked to the grip markers, elbows poled
## from the chest so they never flip). Nothing here writes the pivot; IK reads
## it. Guard contract: /docs/concepts/presentation.md (Mittelhut).
##
## See also: /docs/reference/godot.md

const GRIP_DOMINANT := &"GripDominant"
const GRIP_OFFHAND := &"GripOffhand"
## Elbow poles relative to the chest. Lateral dominates, and forward is +Z
## (Wolf faces +Z after the glTF y-up conversion), so the elbows open away
## from the ribs into a triangle toward the hilt in front of the chest — not
## tucked behind it. A little down. Tuned by silhouette, not by this number.
const POLE_RIGHT := Vector3(-0.62, -0.12, 0.38)
const POLE_LEFT := Vector3(0.62, -0.12, 0.38)
## Wrist to palm, for a hand bone with no child to measure against.
const HAND_LENGTH := 0.06

@export var skeleton_path: NodePath
@export var chest_bone: StringName = &"Chest"
## Dominant (right) arm: upper arm → forearm → hand.
@export var dominant_bones: PackedStringArray = ["UpperArm.R", "Forearm.R", "Hand.R"]
@export var offhand_bones: PackedStringArray = ["UpperArm.L", "Forearm.L", "Hand.L"]
## Fallback grip distances along the blade axis when the weapon model has no
## markers (the primitive blade).
@export var dominant_grip: float = 0.225
@export var offhand_grip: float = 0.15

var _skeleton: Skeleton3D
var _chain: KineticChainModifier3D
var _ik: TwoBoneIK3D
var _targets: Array[Node3D] = []


## The rig's skeleton: `skeleton_path` if set, else the first Skeleton3D below.
func skeleton() -> Skeleton3D:
	if _skeleton == null and not skeleton_path.is_empty():
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		var found := find_children("*", "Skeleton3D", true, false)
		_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	return _skeleton


## Build the modifier stack against `pivot`. `weapon_model` may carry
## GripDominant / GripOffhand markers; otherwise the exported fallbacks are
## used. Idempotent.
func bind_sword(pivot: Node3D, weapon_model: Node = null) -> void:
	var skel := skeleton()
	if skel == null or _ik != null:
		return
	_targets = [
		_target(pivot, "GripDominantTarget", _marker(weapon_model, GRIP_DOMINANT, dominant_grip)),
		_target(pivot, "GripOffhandTarget", _marker(weapon_model, GRIP_OFFHAND, offhand_grip)),
	]
	_chain = KineticChainModifier3D.new()
	_chain.name = "KineticChain"
	skel.add_child(_chain)
	var chest_mount := BoneAttachment3D.new()
	chest_mount.name = "ChestPoles"
	chest_mount.bone_name = chest_bone
	skel.add_child(chest_mount)
	var poles: Array[Node3D] = [_pole(chest_mount, "PoleRight", POLE_RIGHT), _pole(chest_mount, "PoleLeft", POLE_LEFT)]
	_ik = TwoBoneIK3D.new()
	_ik.name = "ArmIK"
	_ik.set_setting_count(2)
	skel.add_child(_ik)
	for index in 2:
		var bones := dominant_bones if index == 0 else offhand_bones
		_ik.set_root_bone_name(index, bones[0])
		_ik.set_middle_bone_name(index, bones[1])
		_ik.set_end_bone_name(index, bones[2])
		## The hand bone's tail is the grip: extend the end bone so the
		## palm, not the wrist, lands on the marker.
		_ik.set_extend_end_bone(index, true)
		## Along the hand's own axis (glTF bones point down +Y), not the
		## default continuation of the forearm, or the palm misses by a hand.
		_ik.set_end_bone_direction(index, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		_ik.set_end_bone_length(index, skel.get_bone_global_rest(skel.find_bone(bones[2])).origin.distance_to(_tail(skel, bones[2])))
		_ik.set_target_node(index, _ik.get_path_to(_targets[index]))
		_ik.set_pole_node(index, _ik.get_path_to(poles[index]))


## The authoritative relative sword angle for this frame, plus the combat phase
## and guard band the body supports it in (both set the follow effort).
func pose_sword(weapon_angle: float, phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL, band: GuardPoseField.Band = GuardPoseField.Band.READY) -> void:
	if _chain != null:
		_chain.sword_angle = weapon_angle
		_chain.combat_phase = phase
		_chain.guard_band = band


## How strongly the hands hold the grip (1 = locked, 0 = let go). Fading it
## out after the sword drops hands the arms back to the body's own animation
## instead of leaving them clutching the empty pivot.
func set_grip_influence(value: float) -> void:
	if _ik != null:
		_ik.influence = clampf(value, 0.0, 1.0)


func is_bound() -> bool:
	return _ik != null


func grip_target(index: int) -> Node3D:
	return _targets[index]


func ik() -> TwoBoneIK3D:
	return _ik


static func _marker(model: Node, marker_name: StringName, fallback: float) -> Vector3:
	if model != null:
		var marker := model.find_child(String(marker_name), true, false) as Node3D
		if marker != null:
			return marker.transform.origin if marker.get_parent() == model else _local_to(model, marker)
	return Vector3(0.0, 0.0, fallback)


static func _local_to(model: Node, marker: Node3D) -> Vector3:
	var offset := marker.transform
	var node := marker.get_parent()
	while node != null and node != model:
		if node is Node3D:
			offset = (node as Node3D).transform * offset
		node = node.get_parent()
	return offset.origin


static func _target(pivot: Node3D, target_name: String, at: Vector3) -> Node3D:
	var existing := pivot.get_node_or_null(target_name) as Node3D
	if existing != null:
		return existing
	var target := Node3D.new()
	target.name = target_name
	target.position = at
	pivot.add_child(target)
	return target


static func _pole(mount: Node3D, pole_name: String, at: Vector3) -> Node3D:
	var pole := Node3D.new()
	pole.name = pole_name
	pole.position = at
	mount.add_child(pole)
	return pole


## Rest-space tail of a bone: the head of its first child, or one bone length
## along its own axis when it has none (the hand).
static func _tail(skel: Skeleton3D, bone_name: String) -> Vector3:
	var bone := skel.find_bone(bone_name)
	var rest := skel.get_bone_global_rest(bone)
	var children := skel.get_bone_children(bone)
	if children.size() > 0:
		return skel.get_bone_global_rest(children[0]).origin
	return rest.origin + rest.basis.y.normalized() * HAND_LENGTH
