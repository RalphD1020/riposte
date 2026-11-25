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
## Clavicle participation (PRES-CLAVICLE-001), from the fighter scene; null
## leaves the shoulder girdle at rest. `grip_weight` is how strongly the hands
## hold the grip (the arm IK's influence): the arm's elevation is read from the
## grip it is about to reach in that share, and from the clip's arm otherwise.
var clavicle: ClavicleResponse
var grip_weight: float = 1.0
## The hands' knuckle lines in their own bones' frames (PRES-GRIP-001), set
## with the grips; each grip frame is aimed along its arm before the IK.
var grip_spans := PackedVector3Array()
## The authored elbow owns the bend plane (`ElbowGuideField.clip_pole`): the IK
## poles come from the clip's own elbows (this pass runs before the IK) instead
## of the guide field's landmark offsets. Consumed from `SwordRig3D.elbow_from_clip`
## (the one setting), never set on its own. Off on every shipping body.
var elbow_from_clip: bool = false
## Authored guard arms (PRES-GRIP-001): at each of `arm_key_degrees` (θ, ascending)
## the six local rotations of `ARM_KEY_BONES`, rest-relative, eased between keys by
## θ and held in the guard's share (`support.settled`) over the clip's arms, before
## the elbow guides read them. Consumed from `SwordRig3D`; empty on every shipping body.
var arm_key_degrees := PackedFloat64Array()
var arm_key_rotations: Array[Quaternion] = []
## Authored cut arms, the same layout keyed by the cut angle
## (`BodySupportPose.cut_angle`: −135 the load … 0 the centre … +45 through),
## one profile per launch direction (right → left, left → right), held in the
## cut's share (1 − `support.settled`): the arms follow the blade's physical
## travel, so a fast, stopped or rebounding cut shows the pose for where the
## blade is, never a clip's clock. Empty on every shipping body.
var arm_cut_degrees := PackedFloat64Array()
var arm_cut_right_rotations: Array[Quaternion] = []
var arm_cut_left_rotations: Array[Quaternion] = []
## Authored cut torso, keyed like the cut arms (`arm_cut_degrees`): the chest's
## extra yaw (radians, about its own up axis, after the body's follow) per launch
## direction, eased between keys and held in the cut's share
## (`authored_cut_share`) - the torso the arm keys were fitted around
## (ART-ANATOMY-001). A profile not authored adds nothing.
var torso_cut_right_yaw := PackedFloat64Array()
var torso_cut_left_yaw := PackedFloat64Array()
## Authored rear-hand roll, keyed like the cut arms: the off hand's turn about
## the handle axis at its station (radians), per launch direction, eased between
## keys and held in the cut's share, so it returns smoothly to the nominal
## contact and retraces on a reversal. A profile not authored adds nothing.
var rear_roll_cut_right := PackedFloat64Array()
var rear_roll_cut_left := PackedFloat64Array()
## Authored load arms (the charged cut's high guard), the same layout keyed by
## |θ|, one profile per load side (`support.cut_direction` +1 a right load), held
## in the gather's share of the guard (`settled × gather`) instead of the charge
## clip's arms. Empty on every shipping body.
var arm_load_degrees := PackedFloat64Array()
var arm_load_right_rotations: Array[Quaternion] = []
var arm_load_left_rotations: Array[Quaternion] = []
const ARM_KEY_BONES: PackedStringArray = ["UpperArm.R", "Forearm.R", "Hand.R", "UpperArm.L", "Forearm.L", "Hand.L"]
## A target this much past the arm chain's length (as a share) still counts as
## reachable: the IK's own numerical slack, not a stretch allowance.
const REACH_TOLERANCE := 0.002

## The rear-hand pivot (a body's declared presentation handling; weapon handling
## data adopts it later): the off hand keeps its contact station on the handle
## but turns about the handle's axis to the angle that best continues its
## forearm, chosen afresh each update from the authored pose (no history). The
## sword, the front hand and every physical quantity are untouched. Consumed
## from `SwordRig3D.rear_hand_pivot` with the off hand's station (sword frame)
## and inverse contact; off on every shipping body.
var rear_pivot: bool = false
var rear_station := Vector3.ZERO
var rear_contact_inverse := Transform3D.IDENTITY
## The last chosen turn (radians), for captures and tests.
var rear_pivot_angle: float = 0.0
## The turn search: a coarse sweep then a fine one around the best.
const PIVOT_COARSE := deg_to_rad(5.0)
const PIVOT_FINE := deg_to_rad(0.5)

## The wrist nodes the IK reaches, one per grip (dominant, off hand), set with
## the grips: with a grip frame's basis they are the Hand bone's wanted pose.
var wrists: Array[Node3D] = []
## Both hands' resolved targets for this update (`ResolvedHandTarget`): the one
## record the IK and the hand pass consume. Preallocated, refreshed in place.
var hand_targets: Array[ResolvedHandTarget] = [ResolvedHandTarget.new(), ResolvedHandTarget.new()]

var _chain_bones := PackedInt32Array()
var _arm_key_bones := PackedInt32Array()
var _arm_lengths := PackedFloat64Array()
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
	_arm_key_bones = PackedInt32Array()
	_arm_lengths = PackedFloat64Array()


func _cache(skeleton: Skeleton3D) -> void:
	if _chain_bones.size() == CHAIN.size() and _foot_bones.size() == foot_bones.size() and _arm_key_bones.size() == ARM_KEY_BONES.size():
		return
	_arm_key_bones.resize(ARM_KEY_BONES.size())
	for index in ARM_KEY_BONES.size():
		_arm_key_bones[index] = skeleton.find_bone(ARM_KEY_BONES[index])
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
	var torso := _cut_torso_yaw()
	for index in CHAIN.size():
		var bone := _chain_bones[index]
		if bone < 0:
			continue
		var link := CHAIN[index]
		var extra := torso if link == &"Chest" else 0.0
		var twist := Quaternion(Vector3.UP, float(LOCAL_SHARES[link]) * sword_angle * effort + _blade_for(link) + extra)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * twist)
	_turn_feet(skeleton)
	_raise_clavicles(skeleton)
	_hold_guard_arms(skeleton)
	_pivot_rear_hand(skeleton)
	_roll_rear_hand()
	_guide_elbows(skeleton)
	_aim_grips()
	_resolve_hand_targets(skeleton)


## Both hands' targets as the weapon decides them, before the IK: the wrist and
## orientation from the grip frames, the elbow preference just placed, the grip
## influence, reach, and the wrist bend the arm's pose will ask for.
func _resolve_hand_targets(skeleton: Skeleton3D) -> void:
	if grips.size() != 2 or wrists.size() != 2 or _arm_bones.size() != 2:
		return
	if _arm_lengths.size() != 2:
		_arm_lengths.resize(2)
		for arm in 2:
			_arm_lengths[arm] = _chain_length(skeleton, _arm_bones[arm])
	var skeleton_to_world := skeleton.global_transform
	for arm in 2:
		var resolved := hand_targets[arm]
		resolved.valid = true
		resolved.target = Transform3D(grips[arm].global_transform.basis.orthonormalized(), wrists[arm].global_position)
		resolved.elbow_pole = poles[arm].global_position if poles.size() == 2 else resolved.elbow_pole
		resolved.influence = clampf(grip_weight, 0.0, 1.0)
		var upper := _arm_bones[arm]
		if upper < 0:
			continue
		var shoulder := (skeleton_to_world * skeleton.get_bone_global_pose(upper)).origin
		resolved.reach = shoulder.distance_to(resolved.target.origin) / maxf(_arm_lengths[arm], 1e-6)
		resolved.feasible = resolved.reach <= 1.0 + REACH_TOLERANCE
		var fore := skeleton.get_bone_children(upper)
		if fore.is_empty():
			continue
		var elbow := (skeleton_to_world * skeleton.get_bone_global_pose(fore[0])).origin
		var forearm := resolved.target.origin - elbow
		resolved.predicted_wrist_bend = forearm.angle_to(resolved.target.basis.y) if forearm.length_squared() > 1e-10 else 0.0


## Turn the off hand about the handle through its station (`rear_pivot`): the
## grip node's frame becomes station · R_handle(ψ) · contact⁻¹ for the ψ that
## best continues the forearm from the authored elbow.
func _pivot_rear_hand(skeleton: Skeleton3D) -> void:
	if not rear_pivot or grips.size() != 2 or _arm_bones.size() != 2 or _arm_bones[1] < 0:
		return
	var fore := skeleton.get_bone_children(_arm_bones[1])
	if fore.is_empty():
		return
	var elbow := (skeleton.global_transform * skeleton.get_bone_global_pose(fore[0])).origin
	var sword := (grips[1].get_parent() as Node3D).global_transform
	rear_pivot_angle = best_shaft_turn(sword, rear_station, rear_contact_inverse, elbow)
	grips[1].transform = shaft_turned(rear_station, rear_contact_inverse, rear_pivot_angle)


## The off hand's grip frame (sword frame) turned `angle` about the handle's
## axis (sword +Z) through `station`.
static func shaft_turned(station: Vector3, contact_inverse: Transform3D, angle: float) -> Transform3D:
	return Transform3D(Basis(SwordGripFrame.BLADE_AXIS, angle), station) * contact_inverse


## The hand's wrist bend for a grip frame: the angle between the forearm (elbow
## → wrist) and the hand bone's +Y.
static func grip_wrist_bend(sword: Transform3D, grip: Transform3D, elbow: Vector3) -> float:
	var hand := sword * grip
	var forearm := hand.origin - elbow
	return forearm.angle_to(hand.basis.y) if forearm.length_squared() > 1e-10 else 0.0


## The turn about the handle that minimises the wrist bend from `elbow`: a
## coarse full-turn sweep, then a fine sweep around the best; the smaller turn
## wins a tie. Pure: the same pose gives the same turn.
static func best_shaft_turn(sword: Transform3D, station: Vector3, contact_inverse: Transform3D, elbow: Vector3) -> float:
	var best := 0.0
	var best_bend := grip_wrist_bend(sword, shaft_turned(station, contact_inverse, 0.0), elbow)
	var steps := int(round(TAU / PIVOT_COARSE))
	for index in steps:
		var angle := -PI + index * PIVOT_COARSE
		var bend := grip_wrist_bend(sword, shaft_turned(station, contact_inverse, angle), elbow)
		if bend < best_bend - 1e-9 or (absf(bend - best_bend) <= 1e-9 and absf(angle) < absf(best)):
			best = angle
			best_bend = bend
	var centre := best
	for index in range(-10, 11):
		var angle := centre + index * PIVOT_FINE
		var bend := grip_wrist_bend(sword, shaft_turned(station, contact_inverse, angle), elbow)
		if bend < best_bend - 1e-9:
			best = angle
			best_bend = bend
	return best


## Upper arm + forearm length at rest (the IK's chain), from the arm root.
static func _chain_length(skeleton: Skeleton3D, upper: int) -> float:
	if upper < 0:
		return 0.0
	var fore := skeleton.get_bone_children(upper)
	if fore.is_empty():
		return 0.0
	var hand := skeleton.get_bone_children(fore[0])
	var length := skeleton.get_bone_rest(fore[0]).origin.length()
	if not hand.is_empty():
		length += skeleton.get_bone_rest(hand[0]).origin.length()
	return length


## The authored arms over the clip's: the guard keys at θ in the guard's share
## (out of a cut, `settled`, less a charge's gather), the load keys at |θ| in the
## gather's share, the cut keys at the cut angle in the cut's share, and all of
## it only while the hands hold the grip — as the sword is released (a fall, a
## death's own release time) the arms return to the clip. A profile not authored
## leaves its share to the clip.
func _hold_guard_arms(skeleton: Skeleton3D) -> void:
	if not authored_arms_own(support):
		return
	var count := ARM_KEY_BONES.size()
	var settled := clampf(support.settled, 0.0, 1.0)
	var has_guard := not arm_key_degrees.is_empty() and arm_key_rotations.size() == arm_key_degrees.size() * count
	var cut_rotations := arm_cut_right_rotations if support.cut_direction >= 0.0 else arm_cut_left_rotations
	var has_cut := not arm_cut_degrees.is_empty() and cut_rotations.size() == arm_cut_degrees.size() * count
	var load_rotations := arm_load_right_rotations if support.cut_direction >= 0.0 else arm_load_left_rotations
	var has_load := not arm_load_degrees.is_empty() and load_rotations.size() == arm_load_degrees.size() * count
	var shares := authored_arm_shares(settled, support.gather, has_guard, has_cut)
	var load_share := authored_load_share(settled, support.gather, has_load)
	if cut_continues(support.phase, support.cut_angle, has_cut):
		shares = Vector2(0.0, shares.x + shares.y + load_share)
		load_share = 0.0
	var total := shares.x + shares.y + load_share
	var hold := total * clampf(grip_weight, 0.0, 1.0)
	if hold <= 0.0:
		return
	var degrees := rad_to_deg(support.sword_angle)
	for index in count:
		var bone := _arm_key_bones[index]
		if bone < 0:
			continue
		var clip := skeleton.get_bone_pose_rotation(bone)
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var target := rest * guard_arm_rotation(arm_key_degrees, arm_key_rotations, index, degrees) if has_guard else clip
		var held := shares.x
		if has_cut and shares.y > 0.0:
			held += shares.y
			target = target.slerp(rest * guard_arm_rotation(arm_cut_degrees, cut_rotations, index, support.cut_angle), shares.y / held)
		if has_load and load_share > 0.0:
			held += load_share
			target = target.slerp(rest * guard_arm_rotation(arm_load_degrees, load_rotations, index, absf(degrees)), load_share / held)
		skeleton.set_bone_pose_rotation(bone, clip.slerp(target, hold))


## The authored cut torso's yaw this frame: the launch direction's profile at
## the cut angle in the cut's share of the authored arms, and nothing while a
## death or a fall owns the body or no profile is authored.
func _cut_torso_yaw() -> float:
	return _cut_profile_value(torso_cut_right_yaw if support.cut_direction >= 0.0 else torso_cut_left_yaw)


## Turn the off hand about the handle by the authored roll (station fixed, the
## same grip-frame form as the pivot); untouched where no roll is authored.
func _roll_rear_hand() -> void:
	var rolls := rear_roll_cut_right if support.cut_direction >= 0.0 else rear_roll_cut_left
	if rear_pivot or grips.size() != 2 or rolls.is_empty() or rolls.size() != arm_cut_degrees.size():
		return
	rear_pivot_angle = _cut_profile_value(rolls)
	grips[1].transform = shaft_turned(rear_station, rear_contact_inverse, rear_pivot_angle)


## A per-cut-key profile's value this frame, in the cut's share of the authored arms.
func _cut_profile_value(values: PackedFloat64Array) -> float:
	var yaws := values
	if not authored_arms_own(support) or yaws.is_empty() or yaws.size() != arm_cut_degrees.size():
		return 0.0
	var count := ARM_KEY_BONES.size()
	var cut_rotations := arm_cut_right_rotations if support.cut_direction >= 0.0 else arm_cut_left_rotations
	var load_rotations := arm_load_right_rotations if support.cut_direction >= 0.0 else arm_load_left_rotations
	var has_guard := not arm_key_degrees.is_empty() and arm_key_rotations.size() == arm_key_degrees.size() * count
	var has_load := not arm_load_degrees.is_empty() and load_rotations.size() == arm_load_degrees.size() * count
	var share := authored_cut_share(support.settled, support.gather, has_guard, cut_rotations.size() == arm_cut_degrees.size() * count, has_load, support.phase, support.cut_angle)
	return share * clampf(grip_weight, 0.0, 1.0) * cut_torso_yaw(arm_cut_degrees, yaws, support.cut_angle)


## The cut's share of the authored arms (as `_hold_guard_arms` holds them): the
## unsettled share, or everything the authored keys hold while the cut
## continues (`cut_continues`).
static func authored_cut_share(settled: float, gather: float, has_guard: bool, has_cut: bool, has_load: bool, phase: CombatPhase.Id, cut_angle_degrees: float) -> float:
	var shares := authored_arm_shares(settled, gather, has_guard, has_cut)
	if cut_continues(phase, cut_angle_degrees, has_cut):
		return shares.x + shares.y + authored_load_share(settled, gather, has_load)
	return shares.y


## A torso profile's yaw at `degrees`: eased between the bracketing keys as the
## arm keys are, held at the end keys beyond them.
static func cut_torso_yaw(degrees_keys: PackedFloat64Array, yaws: PackedFloat64Array, degrees: float) -> float:
	if degrees <= degrees_keys[0]:
		return yaws[0]
	for key in range(1, degrees_keys.size()):
		if degrees <= degrees_keys[key]:
			return lerpf(yaws[key - 1], yaws[key], smoothstep(degrees_keys[key - 1], degrees_keys[key], degrees))
	return yaws[yaws.size() - 1]


## Degrees to radians for a profile, `reflection` -1 mirroring it (the sagittal mirror of a yaw negates it).
static func radians_of(degrees_values: PackedFloat64Array, reflection: float = 1.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for value in degrees_values:
		out.append(deg_to_rad(value) * reflection)
	return out


## The guard keys' and the cut keys' shares of the arms (x guard, y cut) for a
## pose `settled` into the stance with a charge `gather`: the guard owns the
## settled share outside a gather, the cut the rest; a profile not authored
## owns nothing (the clip keeps it).
static func authored_arm_shares(settled: float, gather: float, has_guard: bool, has_cut: bool) -> Vector2:
	var s := clampf(settled, 0.0, 1.0)
	return Vector2(s * (1.0 - clampf(gather, 0.0, 1.0)) if has_guard else 0.0, (1.0 - s) if has_cut else 0.0)


## Whether the cut owns the arms whatever the stance share says (WEAPON-PATH-004
## handling context): a swing in flight (launch through overswing) and a
## recovery on the cut's far side (cut angle > 0) are the active cut, not a
## resting guard or a charged preparation, so a body with authored cut keys keeps
## them there. Guard and load keys are fitted to their own contexts - a resting
## guard's raised sword, a charge's coil - and reusing them in a swing missed the
## sword by up to 0.16 m (the swing's torso drives harder than the charge's) or,
## on the far side, put the pre-IK elbow and the pole read from it across the
## chest. Bodies without cut keys are unchanged.
static func cut_continues(phase: CombatPhase.Id, cut_angle_degrees: float, has_cut: bool) -> bool:
	if not has_cut:
		return false
	if CombatPhase.is_striking(phase):
		return true
	return phase == CombatPhase.Id.RECOVERY and cut_angle_degrees > 0.0


## Whether a body's authored arm keys may own the arms this frame: never while
## a death or a fall owns the body (`BodySupportPose.clip_owns_arms`) — the
## terminal clip is the base pose then, and two systems never compete for the
## same joints.
static func authored_arms_own(pose: BodySupportPose) -> bool:
	return not pose.clip_owns_arms


## The load keys' share of the arms: the gather's part of the settled guard
## (the charge's high guard, and the loaded cut's start until it leaves the
## stance); nothing when no load profile is authored.
static func authored_load_share(settled: float, gather: float, has_load: bool) -> float:
	return clampf(settled, 0.0, 1.0) * clampf(gather, 0.0, 1.0) if has_load else 0.0


## The mirror of an arm-key profile (the `ARM_KEY_BONES` layout, keys in a
## row): each key's right and left bones swap and every rest-relative rotation
## is reflected through the body's sagittal plane, (x, y, z, w) → (x, −y, −z, w)
## — exact for a rest skeleton whose arms are mirror images (S·G_R·S = G_L).
static func mirror_arm_rotations(rotations: Array[Quaternion]) -> Array[Quaternion]:
	var count := ARM_KEY_BONES.size()
	var half := floori(count / 2.0)
	var mirrored: Array[Quaternion] = []
	for key in floori(rotations.size() / float(count)):
		for index in count:
			var q := rotations[key * count + (index + half) % count]
			mirrored.append(Quaternion(q.x, -q.y, -q.z, q.w))
	return mirrored


## Guard keys from one canonical profile: every key at θ > 0 is the mirror of
## its sword-right partner at −θ; keys at θ ≤ 0 (the centre the grip's own) are
## kept as authored.
static func mirrored_guard_keys(degrees_keys: PackedFloat64Array, rotations: Array[Quaternion]) -> Array[Quaternion]:
	var count := ARM_KEY_BONES.size()
	var out: Array[Quaternion] = rotations.duplicate()
	for key in degrees_keys.size():
		var partner := degrees_keys.find(-degrees_keys[key])
		if degrees_keys[key] <= 0.0 or partner < 0:
			continue
		var source: Array[Quaternion] = []
		source.assign(rotations.slice(partner * count, (partner + 1) * count))
		var mirrored := mirror_arm_rotations(source)
		for index in count:
			out[key * count + index] = mirrored[index]
	return out


## Bone `index`'s authored rest-relative rotation at `degrees`: eased between the
## bracketing keys (as the lift keys are), held at the end keys beyond them.
static func guard_arm_rotation(degrees_keys: PackedFloat64Array, rotations: Array[Quaternion], index: int, degrees: float) -> Quaternion:
	var count := ARM_KEY_BONES.size()
	if degrees <= degrees_keys[0]:
		return rotations[index]
	for key in range(1, degrees_keys.size()):
		if degrees <= degrees_keys[key]:
			var t := smoothstep(degrees_keys[key - 1], degrees_keys[key], degrees)
			return rotations[(key - 1) * count + index].slerp(rotations[key * count + index], t)
	return rotations[(degrees_keys.size() - 1) * count + index]


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


## Elevate each clavicle by the response to its arm's elevation, after the
## torso is posed and before the elbow guides and the arm IK read the
## shoulders, so the IK solves from the girdle's final position.
func _raise_clavicles(skeleton: Skeleton3D) -> void:
	if clavicle == null or _arm_bones.size() != 2:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for arm in 2:
		var upper := _arm_bones[arm]
		var collar := skeleton.get_bone_parent(upper) if upper >= 0 else -1
		if collar < 0:
			continue
		var torso := skeleton.get_bone_parent(collar)
		var torso_pose := skeleton.get_bone_global_pose(torso)
		var root := skeleton.get_bone_global_pose(upper)
		var direction := root.basis.y.normalized()
		if grips.size() == 2 and grip_weight > 0.0:
			var reach := (to_skeleton * grips[arm].global_position) - root.origin
			if reach.length_squared() > 1e-8:
				direction = direction.lerp(reach.normalized(), clampf(grip_weight, 0.0, 1.0)).normalized()
		var up := torso_pose.basis.y.normalized()
		var lift := clavicle.elevation(ClavicleResponse.arm_elevation(up, direction))
		ClavicleResponse.raise(skeleton, collar, lift, torso_pose)
		if clavicle.max_protraction_deg > 0.0:
			## This arm's own side of the torso; forward follows from it (+X is the
			## fighter's left, so left × up is forward and the right side flips).
			var outward := root.origin - torso_pose.origin
			outward = (outward - up * outward.dot(up)).normalized()
			var forward := outward.cross(up) * (1.0 if arm == 1 else -1.0)
			var turn := clavicle.protraction(ClavicleResponse.arm_reach_across(up, outward, forward, direction))
			ClavicleResponse.protract(skeleton, collar, turn, torso_pose, forward)


## Turn each grip frame on the handle toward its forearm (PRES-GRIP-001), after
## the elbow guides are placed from this pose's shoulders: the palm stays on
## the grip and the knuckle line on the handle; the hand's tilt and turn follow
## the line from the elbow's guide to the palm inside the common grip, so the
## wrist the IK reaches sits along the forearm. (The shoulder → palm line is
## no forearm when the elbow folds: it measured 110–170° of wrist bend at the
## near arm's own-side loads.)
func _aim_grips() -> void:
	if grips.size() != 2 or grip_spans.size() != 2 or frame == null or stance == null:
		return
	var out_of_frame := frame.global_transform
	for arm in 2:
		var grip := grips[arm]
		var sword := (grip.get_parent() as Node3D).global_transform
		var forearm := sword.basis.inverse() * (grip.global_position - out_of_frame * _elbows.guides[arm])
		grip.basis = SwordGripFrame.hand_basis(SwordGripFrame.aimed_hand_axis(forearm), grip_spans[arm])


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
		var pole := _elbows.poles[arm]
		if elbow_from_clip:
			var fore := skeleton.get_bone_children(_arm_bones[arm])
			if not fore.is_empty():
				var elbow := into_frame * (skeleton.global_transform * skeleton.get_bone_global_pose(fore[0])).origin
				pole = ElbowGuideField.clip_pole(_shoulders[arm], elbow, _hands[arm], ElbowGuideField.CLIP_POLE_OFFSET, pole)
		poles[arm].global_position = out_of_frame * pole


## The elbow guides from the last solve (for tests, captures, debug).
func elbow_guides() -> ElbowGuideField:
	return _elbows
