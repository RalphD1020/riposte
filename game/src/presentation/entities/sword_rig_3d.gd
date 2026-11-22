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
## shares, head counter-rotates to the opponent — the cut's body support — and,
## when the scene names a `clavicle_response`, each shoulder girdle rises with
## its arm) → TwoBoneIK3D (both wrists to the wrists the grip frames imply,
## elbows poled so they never flip) → GripHandsModifier3D (each hand turned to
## its grip frame, so the palm lands on the grip and the hand wraps the handle,
## PRES-GRIP-001). Nothing here writes the carriage; IK reads it.
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
## Each hand mesh's wide axis (its knuckle line) in its own bone's frame,
## dominant then off hand, measured from the body (PRES-GRIP-001 holds it to
## the mesh). The default is the blockout's hand blocks.
@export var hand_span_axes: PackedVector3Array = PackedVector3Array([Vector3(0.0, 0.0, 1.0), Vector3(0.105, 0.0, 0.995)])
## The grip's maximum corrective deviation from its grip frame (degrees; 0 =
## the frame exactly, every shipping body): a bounded tolerance a candidate
## body may declare so its continuous skin is not twisted at the wrist further
## than the grasp requires. Not the grip's geometry; see `GripHandsModifier3D`.
@export_range(0.0, 45.0) var grip_diagonal_deg: float = 0.0
## Authored hand contacts (PRES-GRIP-001), dominant then off hand: each the
## handle's frame in its Hand bone's space (`SwordGripFrame.contact_frame`).
## Empty (every shipping body) keeps the legacy grip: the palm on the station,
## the wrist `HAND_LENGTH` back, the hand re-aimed along the forearm. Set, each
## hand is held at `station · contact⁻¹` — orientation and wrist from the
## contact alone, never re-aimed — and `grip_diagonal_deg` should be 0 (the
## authored contact carries the palm's diagonal).
@export var grip_contacts: Array[Transform3D] = []
## The authored pose's elbows own the IK bend plane (PRES-GRIP-001; see
## `CombatPoseModifier3D.elbow_from_clip`). Off on every shipping body.
@export var elbow_from_clip: bool = false
## This body's Long Guard lift, as deltas on the shared centre key
## (`CombatPresentationField.configure_centre`): hands' height (m) and blade
## pitch (degrees, + point up). Presentation only — the carriage and yaw stay
## the authoritative ones. Zero on every shipping body.
@export var centre_raise_delta: float = 0.0
@export var centre_pitch_delta_deg: float = 0.0
## Authored guard arms (PRES-GRIP-001; `CombatPoseModifier3D.arm_key_degrees`):
## guard angles θ in degrees, ascending, and per angle the rest-relative local
## rotations of the right upper arm, forearm, hand, then the left's. Held in the
## guard's share before the arm IK. Empty on every shipping body.
@export var arm_guard_degrees := PackedFloat64Array()
@export var arm_guard_rotations: Array[Quaternion] = []
## Authored cut arms (`CombatPoseModifier3D.arm_cut_degrees`): cut angles in
## degrees, ascending, and per angle the same six rotations, one profile per
## launch direction. Empty on every shipping body.
@export var arm_cut_degrees := PackedFloat64Array()
@export var arm_cut_right_rotations: Array[Quaternion] = []
@export var arm_cut_left_rotations: Array[Quaternion] = []
## The combat-aligned projection (`CombatPresentationField.configure_projection`):
## the drawn sword level at one fixed interaction height in every phase, its
## hands `interaction_raise` above the blade plane, no contact snap. The
## footprint-parity reference, not the product X. Off on every shipping body.
@export var combat_aligned_projection: bool = false
@export var interaction_raise: float = 0.0
## This body's charged-cut high guard (`CombatPresentationField.configure_load`):
## hands' height above the blade plane (m) and blade pitch (degrees) at full
## gather, and, when `load_roll_authored`, the blade's roll about its own axis
## at a right load (degrees); the left load is its mirror image plus at most
## `CombatPresentationField.LOAD_ROLL_CORRECTION_LIMIT` of right-handed
## correction (`load_roll_left_correction_deg`) - both sides are one weapon
## action. Charged cuts only. The shared load on every shipping body.
@export var load_raise: float = CombatPresentationField.LOAD_RAISE
@export var load_pitch_deg: float = CombatPresentationField.LOAD_PITCH_DEGREES
@export var load_roll_authored: bool = false
@export var load_roll_deg: float = 0.0
@export var load_roll_left_correction_deg: float = 0.0
## The long edge leads the motion (`CombatPresentationField.configure_edge`):
## the blade's roll follows the strike region's direction of travel, the strike
## region `edge_strike_from_carriage` metres beyond the carriage (the sword's
## centre of percussion: 0.864 − 0.1875 m). Off on every shipping body.
@export var edge_leads_motion: bool = false
@export var edge_strike_from_carriage: float = 0.6765
## Which sword-frame edge is this body's cutting (long) edge under its approved
## front-hand grip: the edge away from the front hand's thumb web, on the
## knuckle side. On the v7 contacts the right thumb web lies over edge B
## (radial · −X = +0.46), so the long edge is A.
@export var cutting_edge: SwordGripFrame.Edge = SwordGripFrame.Edge.A
## The rear-hand pivot (`CombatPoseModifier3D.rear_pivot`): the off hand keeps
## its contact station and turns about the handle to continue its forearm; the
## front hand stays the weapon's rigid anchor. Needs authored contacts. Off on
## every shipping body.
@export var rear_hand_pivot: bool = false
## Authored load arms (`CombatPoseModifier3D.arm_load_degrees`): |θ| in degrees,
## ascending, and per key the same six rotations, one profile per load side,
## held in the gather's share of the guard. Empty on every shipping body.
@export var arm_load_degrees := PackedFloat64Array()
@export var arm_load_right_rotations: Array[Quaternion] = []
@export var arm_load_left_rotations: Array[Quaternion] = []
## Clavicle participation (PRES-CLAVICLE-001): a body skinned to its
## `Shoulder.*` bones names one; a rigid-part body leaves it null and its
## shoulders stay at rest. Presentation only.
@export var clavicle_response: ClavicleResponse

var _skeleton: Skeleton3D
var _chain: CombatPoseModifier3D
var _rear_station := Vector3.ZERO
var _ik: TwoBoneIK3D
var _hands: GripHandsModifier3D
var _targets: Array[Node3D] = []
var _wrists: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _guided: Array[Node3D] = []


## What this body's grip settings get wrong against the weapon-outward contract
## (PRES-GRIP-001), empty when they hold: the weapon places both hands through
## authored contacts (proper rotations, no second correction on top), and the
## authored-pose settings — clip elbows, guard arms — exist only with them.
## Every shipping body (legacy grip, none of those settings) passes.
func contract_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	if not grip_contacts.is_empty() and not has_contacts():
		problems.append("grip_contacts must name both hands (%d given)" % grip_contacts.size())
	for index in grip_contacts.size():
		var contact_basis := grip_contacts[index].basis
		if absf(contact_basis.determinant() - 1.0) > 1e-3 or not contact_basis.is_equal_approx(contact_basis.orthonormalized()):
			problems.append("grip contact %d is not a proper rotation (det %.4f)" % [index, contact_basis.determinant()])
	if has_contacts() and grip_diagonal_deg > 0.0:
		problems.append("authored contacts carry the grip's diagonal; grip_diagonal_deg %.1f would correct it twice" % grip_diagonal_deg)
	if elbow_from_clip and not has_contacts():
		problems.append("elbow_from_clip needs authored contacts: an authored elbow is calibrated to an authored grip")
	_key_problems(problems, "arm_guard", arm_guard_degrees, [arm_guard_rotations])
	_key_problems(problems, "arm_cut", arm_cut_degrees, [arm_cut_right_rotations, arm_cut_left_rotations])
	_key_problems(problems, "arm_load", arm_load_degrees, [arm_load_right_rotations, arm_load_left_rotations])
	if combat_aligned_projection and (centre_raise_delta != 0.0 or centre_pitch_delta_deg != 0.0):
		problems.append("a combat-aligned projection fixes the sword's lift; centre deltas would be ignored")
	if combat_aligned_projection and (load_raise != CombatPresentationField.LOAD_RAISE or load_pitch_deg != CombatPresentationField.LOAD_PITCH_DEGREES or load_roll_authored):
		problems.append("a combat-aligned projection fixes the sword's lift; a declared high guard would be ignored")
	if rear_hand_pivot and not has_contacts():
		problems.append("the rear-hand pivot turns an authored contact; it needs authored contacts")
	if combat_aligned_projection and edge_leads_motion:
		problems.append("a combat-aligned projection fixes the roll at 0; the edge cannot also lead the motion")
	if edge_leads_motion and edge_strike_from_carriage <= 0.0:
		problems.append("the edge's strike region must lie beyond the carriage (%.3f m)" % edge_strike_from_carriage)
	if load_roll_authored and absf(load_roll_deg) > 180.0:
		problems.append("load roll is one turn about the blade axis at most (%.1f)" % load_roll_deg)
	if absf(load_roll_left_correction_deg) > CombatPresentationField.LOAD_ROLL_CORRECTION_LIMIT:
		problems.append("the left load mirrors the right; a correction of %.1f° is past the %.0f° limit (an independent pose, not a correction)" % [load_roll_left_correction_deg, CombatPresentationField.LOAD_ROLL_CORRECTION_LIMIT])
	return problems


## One authored arm profile family: contacts, six rotations per key in every
## profile, ascending keys.
func _key_problems(problems: PackedStringArray, label: String, degrees: PackedFloat64Array, profiles: Array) -> void:
	var authored := not degrees.is_empty()
	for rotations: Array[Quaternion] in profiles:
		authored = authored or not rotations.is_empty()
	if not authored:
		return
	if not has_contacts():
		problems.append("authored %s keys need authored contacts" % label)
	var count := CombatPoseModifier3D.ARM_KEY_BONES.size()
	for rotations: Array[Quaternion] in profiles:
		## An empty profile is a direction not yet authored: the clip keeps it.
		if not rotations.is_empty() and rotations.size() != degrees.size() * count:
			problems.append("%s rotations hold %d for %d keys (%d each)" % [label, rotations.size(), degrees.size(), count])
	for index in range(1, degrees.size()):
		if degrees[index] <= degrees[index - 1]:
			problems.append("%s degrees must ascend (%.1f after %.1f)" % [label, degrees[index], degrees[index - 1]])


## Both hands' resolved targets for the last update (`ResolvedHandTarget`).
func hand_targets() -> Array[ResolvedHandTarget]:
	return _chain.hand_targets if _chain != null else [] as Array[ResolvedHandTarget]


## Whether this body holds the sword through authored contacts (both hands).
func has_contacts() -> bool:
	return grip_contacts.size() == 2


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
	_wrists = []
	for index in 2:
		var grip := _targets[index]
		if has_contacts():
			if index == 1:
				_rear_station = grip.position
			grip.transform = SwordGripFrame.contact_target(grip.position, grip_contacts[index])
			_wrists.append(_target(grip, "Wrist", Vector3.ZERO))
		else:
			grip.transform = SwordGripFrame.frame(grip.position, SwordGripFrame.COMMON_HAND_AXIS, hand_span_axes[index])
			_wrists.append(_target(grip, "Wrist", SwordGripFrame.wrist_offset(HAND_LENGTH)))
	_chain = CombatPoseModifier3D.new()
	_chain.name = "KineticChain"
	_chain.clavicle = clavicle_response
	if rear_hand_pivot and has_contacts():
		_chain.rear_pivot = true
		_chain.rear_station = _rear_station
		_chain.rear_contact_inverse = grip_contacts[1].affine_inverse()
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
		## The wrist the grip frame implies, not the palm: the hand's turn
		## around the handle is the grip's, set after the IK.
		_ik.set_extend_end_bone(index, false)
		_ik.set_target_node(index, _ik.get_path_to(_wrists[index]))
		_ik.set_pole_node(index, _ik.get_path_to(poles[index]))
	_hands = GripHandsModifier3D.new()
	_hands.name = "GripHands"
	_hands.hand_bones = PackedStringArray([dominant_bones[2], offhand_bones[2]])
	_hands.frames = _targets
	_hands.targets = _chain.hand_targets
	_chain.wrists = _wrists
	_hands.diagonal_limit = deg_to_rad(grip_diagonal_deg)
	skel.add_child(_hands)


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
	## An authored contact fixes the hand on the handle: no re-aim along the arm.
	_chain.grip_spans = PackedVector3Array() if has_contacts() else hand_span_axes
	_chain.poles = _guided
	_chain.elbow_from_clip = elbow_from_clip
	_chain.arm_key_degrees = arm_guard_degrees
	_chain.arm_key_rotations = arm_guard_rotations
	_chain.arm_cut_degrees = arm_cut_degrees
	_chain.arm_cut_right_rotations = arm_cut_right_rotations
	_chain.arm_cut_left_rotations = arm_cut_left_rotations
	_chain.arm_load_degrees = arm_load_degrees
	_chain.arm_load_right_rotations = arm_load_right_rotations
	_chain.arm_load_left_rotations = arm_load_left_rotations
	_chain.frame = get_parent() as Node3D
	_chain.arm_roots = PackedStringArray([dominant_bones[0], offhand_bones[0]])
	_chain.wrists = _wrists


## How strongly the hands hold the grip (1 = locked, 0 = let go). Fading it
## out after the sword drops hands the arms back to the body's own animation
## instead of leaving them clutching the empty pivot.
func set_grip_influence(value: float) -> void:
	if _ik != null:
		_ik.influence = clampf(value, 0.0, 1.0)
	if _hands != null:
		_hands.influence = clampf(value, 0.0, 1.0)
	if _chain != null:
		_chain.grip_weight = clampf(value, 0.0, 1.0)


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


## The final hand-orientation pass, for tests.
func grip_hands() -> GripHandsModifier3D:
	return _hands


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
