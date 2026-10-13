class_name SwordRig3D
extends Node3D

## Rig glue for an authored fighter scene: the hands follow the displayed
## sword, never the reverse. Attach to the root of a fighter wrapper scene; the
## proxy calls `bind_sword` once with the node that carries its displayed sword
## (the `SwordCarriage` node: the authoritative carriage and yaw, lifted by
## `CombatPresentationField`) and the weapon's
## display model, then `pose_sword` every frame.
##
## Stack on the Skeleton3D, in order: animation (feet, hips, spine, head) →
## CombatPoseModifier3D (chest → spine → hips follow the sword in decreasing
## shares, head counter-rotates to the opponent — the cut's body support) →
## TwoBoneIK3D (both hands locked to the grip markers, elbows poled from the
## chest so they never flip). Nothing here writes the carriage; IK reads it.
## Guard contract: /docs/concepts/presentation.md.
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
## When the hands carry to the far side, the arm reaching across the body is
## poled forward instead of outward, so its elbow stays in front of the chest
## rather than folding the forearm through it. Two stable bases, blended by
## where the hands are — never by the raw ±135° angle — so a pole never jumps
## behind the body or goes colinear with the arm.
const POLE_RIGHT_ACROSS := Vector3(-0.25, 0.05, 0.85)
const POLE_LEFT_ACROSS := Vector3(0.25, 0.05, 0.85)
## When the hands carry to an arm's own side, that near arm's elbow opens
## outward and a little down, clear of the bladed flank.
const POLE_RIGHT_OUT := Vector3(-0.9, 0.05, 0.35)
const POLE_LEFT_OUT := Vector3(0.9, 0.05, 0.35)
## Lateral hand offset (m, toward the far side) over which the reaching arm's
## pole moves to its across base (and the near arm's to its out base).
const ACROSS_START := 0.02
const ACROSS_END := 0.22
## Wrist to palm, for a hand bone with no child to measure against.
const HAND_LENGTH := 0.06

@export var skeleton_path: NodePath
@export var chest_bone: StringName = &"Chest"
## Dominant (right) arm: upper arm → forearm → hand.
@export var dominant_bones: PackedStringArray = ["UpperArm.R", "Forearm.R", "Hand.R"]
@export var offhand_bones: PackedStringArray = ["UpperArm.L", "Forearm.L", "Hand.L"]
## The feet the stance aims (STANCE-FOOT-001).
@export var right_foot_bone: StringName = &"Foot.R"
@export var left_foot_bone: StringName = &"Foot.L"
## Fallback grip distances along the blade axis when the weapon model has no
## markers (the primitive blade).
@export var dominant_grip: float = PhysicalBaseline.GRIP_DOMINANT_M
@export var offhand_grip: float = PhysicalBaseline.GRIP_OFFHAND_M

var _skeleton: Skeleton3D
var _chain: CombatPoseModifier3D
var _ik: TwoBoneIK3D
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _guided: Array[Node3D] = []


## The rig's skeleton: `skeleton_path` if set, else the first Skeleton3D below.
func skeleton() -> Skeleton3D:
	if _skeleton == null and not skeleton_path.is_empty():
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		var found := find_children("*", "Skeleton3D", true, false)
		_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	return _skeleton


## Build the modifier stack against `carriage`, the node the displayed sword
## hangs from. `weapon_model` may carry GripDominant / GripOffhand markers;
## otherwise the exported fallbacks are used. Idempotent.
func bind_sword(carriage: Node3D, weapon_model: Node = null) -> void:
	var skel := skeleton()
	if skel == null or _ik != null:
		return
	_targets = [
		_target(carriage, "GripDominantTarget", _marker(weapon_model, GRIP_DOMINANT, dominant_grip)),
		_target(carriage, "GripOffhandTarget", _marker(weapon_model, GRIP_OFFHAND, offhand_grip)),
	]
	_chain = CombatPoseModifier3D.new()
	_chain.name = "KineticChain"
	skel.add_child(_chain)
	var chest_mount := BoneAttachment3D.new()
	chest_mount.name = "ChestPoles"
	chest_mount.bone_name = chest_bone
	skel.add_child(chest_mount)
	var poles: Array[Node3D] = [_pole(chest_mount, "PoleRight", POLE_RIGHT), _pole(chest_mount, "PoleLeft", POLE_LEFT)]
	_poles = poles
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


## How the body holds the sword this frame: the proxy's one `BodySupportPose`
## sample, sampled from the same interpolated θ as the hilt. Its hand lateral
## (toward the fighter's left +, right −) sets where the reaching arm's elbow
## is poled when no stance guides the elbows.
func pose_sword(support: BodySupportPose) -> void:
	if _chain != null:
		_chain.support = support
	if _poles.size() == 2 and _guided.is_empty():
		var left := smoothstep(ACROSS_START, ACROSS_END, support.hand_lateral)
		var right := smoothstep(ACROSS_START, ACROSS_END, -support.hand_lateral)
		_poles[0].position = POLE_RIGHT.lerp(POLE_RIGHT_ACROSS, left).lerp(POLE_RIGHT_OUT, right)
		_poles[1].position = POLE_LEFT.lerp(POLE_LEFT_ACROSS, right).lerp(POLE_LEFT_OUT, left)


## Turn the head toward the target bearing: `offset` is τ − φ (radians, + to
## the fighter's left).
func look_toward(offset: float) -> void:
	if _chain != null:
		_chain.look_offset = offset


## The combat-pose pass (torso support and elbow guidance), for tests.
func combat_pose() -> CombatPoseModifier3D:
	return _chain


## Stand the body in `stance` (PRES-STANCE-001): the whole rig turns by the
## pelvis's blade, the chain adds the shoulders' blade above it and turns the
## head back onto the opponent, and held loads coil per side. The combat frame
## — and with it the carriage and the hands' targets — does not turn.
func apply_stance(stance: FighterStanceProfile) -> void:
	if stance == null:
		return
	rotation.y = stance.hip_yaw()
	if _chain == null:
		return
	_chain.upper_blade = stance.upper_yaw()
	_chain.head_counter = -(stance.hip_yaw() + stance.upper_yaw())
	_chain.load_coil_right = stance.load_coil(-1.0)
	_chain.load_coil_left = stance.load_coil(1.0)
	_chain.guard_coil = stance.guard_coil()
	var right_leads := stance.lead_side == FighterStanceProfile.LeadSide.RIGHT
	_chain.foot_bones = PackedStringArray([right_foot_bone if right_leads else left_foot_bone, left_foot_bone if right_leads else right_foot_bone])
	_chain.foot_turns = PackedFloat64Array([stance.lead_foot_turn(), stance.rear_foot_turn()])
	## The elbows are the combat-pose pass's from here on (PRES-ARMS-001):
	## it places these poles each update, from this update's shoulders.
	if _guided.is_empty():
		for index in 2:
			var guided := Node3D.new()
			guided.name = "ElbowGuide%s" % ("Right" if index == 0 else "Left")
			add_child(guided)
			_guided.append(guided)
			_ik.set_pole_node(index, _ik.get_path_to(guided))
	_chain.stance = stance
	_chain.grips = _targets
	_chain.poles = _guided
	_chain.frame = get_parent() as Node3D
	_chain.arm_roots = PackedStringArray([dominant_bones[0], offhand_bones[0]])


## How strongly the hands hold the grip (1 = locked, 0 = let go). Fading it
## out after the sword drops hands the arms back to the body's own animation
## instead of leaving them clutching the empty pivot.
func set_grip_influence(value: float) -> void:
	if _ik != null:
		_ik.influence = clampf(value, 0.0, 1.0)


func grip_influence() -> float:
	return _ik.influence if _ik != null else 0.0


## How strongly the body follows the sword (chest → spine → hips; 1 = fully,
## 0 = the animation alone). A terminal fades it out so the fall or collapse
## clip owns the body instead of a guard pose painted over it.
func set_pose_influence(value: float) -> void:
	if _chain != null:
		_chain.influence = clampf(value, 0.0, 1.0)


func pose_influence() -> float:
	return _chain.influence if _chain != null else 0.0


func is_bound() -> bool:
	return _ik != null


func grip_target(index: int) -> Node3D:
	return _targets[index]


func ik() -> TwoBoneIK3D:
	return _ik


## The elbow pole arm `index` bends toward (0 dominant / right, 1 off-hand /
## left): the combat-pose pass's guided one once a stance is applied, else the
## chest-mounted fallback.
func elbow_pole(index: int) -> Node3D:
	return _guided[index] if not _guided.is_empty() else _poles[index]


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
