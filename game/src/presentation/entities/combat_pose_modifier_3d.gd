class_name CombatPoseModifier3D
extends SkeletonModifier3D

## The fighter's single procedural combat-pose pass. The runtime stack is one
## clip layer, this, and one native two-arm `TwoBoneIK3D`: everything else —
## carriage, cut curve, elbow guides, clearance — is pure math and data this
## (and the proxy) consume, and is validated offline by PRES-RIG's sweeps.
## Typed, bone indices cached, nothing allocated per frame.
##
## The body supports the authoritative sword as a kinetic chain, so a Mittelhau
## (Meyer's horizontal cut) reads as a trained cut rather than a wrist flick: the chest
## follows the sword most, the spine less, and the head counter-rotates to stay
## on the opponent. The pelvis is the stance's, never the sword's: it carries
## the legs, and turning it with the blade would swivel the planted feet
## (PRES-STANCE-001, PRES-LOCO-001). Runs after animation mixing and before arm
## IK, so the hands still lock to the grip and the blade is never moved by this
## (PRES-001).
##
## Shares are LOCAL yaw per bone, about each bone's own (vertical) axis. Because
## the spine chain nests Spine → Chest → Head, the cumulative WORLD yaw falls
## off down the chain: chest ends up turned most, spine less, and the head — a
## negative local share — ends up barely turned, i.e. still facing the
## opponent. These are presentation interpretation values, not Meyer
## measurements; what matters is the falloff ordering.
##
## See also: /docs/reference/godot.md, /docs/concepts/presentation.md

## bone → local share of the sword angle, at full (active-swing) effort.
## Cumulative world targets this implies at scale 1.0: spine 0.20, chest 0.35,
## head 0.10 (counter-rotated). `BodySupportPose.effort` scales these down.
const LOCAL_SHARES := {
	&"Spine": 0.20,
	&"Chest": 0.15,
	&"Head": -0.25,
}
## Parents before children, so each bone's local pose is set before the next.
const CHAIN: Array[StringName] = [&"Spine", &"Chest", &"Head"]

## The most the chest may turn (cumulative world yaw) by phase. A charge stores
## a compact coil — the hips and shoulders load, the front of the chest does
## not swing round into the arms — and the released cut gets the full chain.
## Without the cap a full wind-back (±135°) would turn the chest ~34° toward
## the hands.
const COIL_LIMIT_GUARD := deg_to_rad(18.0)
const COIL_LIMIT_SWING := deg_to_rad(35.0)
## The most the head glances off the combat heading toward the target bearing.
## Head and stance face φ — the centre of the weapon's 270° domain — so a
## committed fighter who has not turned back onto the opponent visibly has
## not (PRES-HEADING-001); the glance only says where the eyes are.
const LOOK_LIMIT := deg_to_rad(12.0)

## How the body holds the sword this frame (`BodySupportPose`), set by the
## rig from the proxy's one sample: the angle, phase, effort and elbow inputs.
var support := BodySupportPose.new()
## The bladed stance above the pelvis (radians; the pelvis's own blade turns
## the whole body model), split between spine and chest, with the head
## counter-rotated by all of the body's blade so it stays on the opponent
## (PRES-STANCE-001). Zero stands square.
var upper_blade: float = 0.0
var head_counter: float = 0.0
## How far the target bearing τ sits from the combat heading φ (radians, + to
## the fighter's left), set by the proxy each frame: the head glances toward
## the opponent by at most `LOOK_LIMIT`, and otherwise faces φ.
var look_offset: float = 0.0
## The held-load coil caps toward the right (−) and left (+) sword sides; zero
## uses `COIL_LIMIT_GUARD` for both.
var load_coil_right: float = 0.0
var load_coil_left: float = 0.0
## The coil cap in a settled guard (NEUTRAL), either side; zero falls back to
## the load caps. Keeps the torso bladed wherever the sword rests.
var guard_coil: float = 0.0
## The feet, lead then rear, and how far each turns about the vertical at its
## ankle after the clip (STANCE-FOOT-001): the stance's toe directions,
## constant, so a planted foot never skates, the clip's foot placement and
## stance width are untouched, and no gait clip can square the feet.
var foot_bones: PackedStringArray = PackedStringArray()
var foot_turns := PackedFloat64Array()
## The chest's coil cap for this phase: the full chain only while a cut is in
## the air.
static func coil_limit(phase: CombatPhase.Id) -> float:
	match phase:
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE, CombatPhase.Id.OVERSWING:
			return COIL_LIMIT_SWING
		_:
			return COIL_LIMIT_GUARD


## The share of the raw follow the body commits so the chest stays within
## `limit`: 1 when it already does, less when the sword is wound far round.
## Scaling every link by it keeps the falloff ordering intact.
static func coil_scale(angle: float, effort: float, limit: float) -> float:
	var chest := absf(world_follow(&"Chest", angle, effort))
	return 1.0 if chest <= limit else limit / chest


## The stance's own local yaw for `link`: the upper blade shared between spine
## and chest, the head turned back by the whole body's blade.
func _blade_for(link: StringName) -> float:
	match link:
		&"Spine", &"Chest":
			return upper_blade * 0.5
		&"Head":
			return head_counter + clampf(look_offset, -LOOK_LIMIT, LOOK_LIMIT)
		_:
			return 0.0


## Cumulative world yaw a bone reaches, following `CHAIN` order (0 for a bone
## off the chain, such as the pelvis). Diagnostic and tested: proves the
## falloff (chest most, spine less, head counter-rotated).
## `effort` is the phase effort; the default (1.0) is full active-swing follow.
static func world_follow(bone: StringName, angle: float, effort: float = 1.0) -> float:
	var cumulative := 0.0
	for link: StringName in CHAIN:
		cumulative += float(LOCAL_SHARES[link]) * angle * effort
		if link == bone:
			return cumulative
	return 0.0


## Elbow guidance (PRES-ARMS-001), set once by `SwordRig3D.apply_stance`:
## the stance, the two grip targets on the displayed sword, the two pole nodes
## the arm IK bends toward, the frame the guide field works in (VisualRoot),
## and the arms' root bones. Without a stance the IK keeps its own poles.
var stance: FighterStanceProfile
var grips: Array[Node3D] = []
var poles: Array[Node3D] = []
var frame: Node3D
var arm_roots: PackedStringArray = PackedStringArray()

var _chain_bones := PackedInt32Array()
var _arm_bones := PackedInt32Array()
var _foot_bones := PackedInt32Array()
var _elbows := ElbowGuideField.new()
var _hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _shoulders: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## Bone indices are resolved once per skeleton, never per frame.
func _validate_bone_names() -> void:
	_chain_bones = PackedInt32Array()
	_arm_bones = PackedInt32Array()
	_foot_bones = PackedInt32Array()


func _cache(skeleton: Skeleton3D) -> void:
	if _chain_bones.size() == CHAIN.size() and _foot_bones.size() == foot_bones.size():
		return
	_chain_bones.resize(CHAIN.size())
	for index in CHAIN.size():
		_chain_bones[index] = skeleton.find_bone(CHAIN[index])
	_arm_bones.resize(arm_roots.size())
	for index in arm_roots.size():
		_arm_bones[index] = skeleton.find_bone(arm_roots[index])
	_foot_bones.resize(foot_bones.size())
	for index in foot_bones.size():
		_foot_bones[index] = skeleton.find_bone(foot_bones[index])


## The one procedural upper-body solve, after the clip and before the arm IK:
## the torso supports the sword (stance blade, capped coil, head counter), and
## then — from the shoulders this very pose puts them at — each elbow's bend
## plane is placed for the IK that follows.
func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_cache(skeleton)
	var sword_angle := support.sword_angle
	var effort := support.effort
	var limit := coil_limit(support.phase)
	if limit == COIL_LIMIT_GUARD:
		var side_cap := load_coil_right if sword_angle < 0.0 else load_coil_left
		if support.phase == CombatPhase.Id.NEUTRAL and guard_coil > 0.0:
			side_cap = guard_coil
		if side_cap > 0.0:
			limit = side_cap
	effort *= coil_scale(sword_angle, effort, limit)
	for index in CHAIN.size():
		var bone := _chain_bones[index]
		if bone < 0:
			continue
		var link := CHAIN[index]
		var twist := Quaternion(Vector3.UP, float(LOCAL_SHARES[link]) * sword_angle * effort + _blade_for(link))
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * twist)
	_turn_feet(skeleton)
	_guide_elbows(skeleton)


## Turn each foot about the skeleton's vertical at its ankle by the stance's
## toe direction (+ toward the fighter's left), expressed in the foot's parent
## space so the sole stays flat whatever the clip's leg pose. A dead fighter's
## feet are the death clip's.
func _turn_feet(skeleton: Skeleton3D) -> void:
	if support.phase == CombatPhase.Id.DEAD:
		return
	for index in mini(_foot_bones.size(), foot_turns.size()):
		var bone := _foot_bones[index]
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var turn := parent_rotation.inverse() * Quaternion(Vector3.UP, foot_turns[index]) * parent_rotation
		skeleton.set_bone_pose_rotation(bone, turn * skeleton.get_bone_pose_rotation(bone))


func _guide_elbows(skeleton: Skeleton3D) -> void:
	if stance == null or frame == null or grips.size() != 2 or poles.size() != 2 or _arm_bones.size() != 2:
		return
	var into_frame := frame.global_transform.affine_inverse()
	var out_of_frame := frame.global_transform
	for arm in 2:
		_hands[arm] = into_frame * grips[arm].global_position
		_shoulders[arm] = into_frame * (skeleton.global_transform * skeleton.get_bone_global_pose(_arm_bones[arm])).origin
	_elbows.sample(stance.arm_structure(), stance.chest_yaw(), _shoulders, _hands, support.sword_angle, support.gather, support.settled, support.cut_angle, support.load_side)
	for arm in 2:
		poles[arm].global_position = out_of_frame * _elbows.poles[arm]


## The elbow guides from the last solve (for tests, captures, debug).
func elbow_guides() -> ElbowGuideField:
	return _elbows
