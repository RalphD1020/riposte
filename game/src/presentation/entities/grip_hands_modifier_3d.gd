class_name GripHandsModifier3D
extends SkeletonModifier3D

## The last pass of the fighter's stack (PRES-GRIP-001): after the arm IK has
## brought each wrist to the wrist its grip frame implies, turn each hand to
## that frame. The IK never sees the hand's roll; this never moves a joint
## position, so the palm lands on the grip and the hand is turned around the
## handle the way the grip says. Bone indices cached; nothing allocated per
## frame.
##
## The ideal orientation is the grip frame (the signed hand frame against the
## weapon's grip station). `diagonal_limit` (radians, 0 = the grip frame
## exactly) is a maximum corrective deviation on top of it: the hand may take
## back up to that much of its roll about its own long axis against the
## forearm, as the handle crossing the palm diagonally allows, so a wrist is
## not twisted further than the grasp requires. A bounded tolerance, never the
## grip's geometry. The wrist does not move: the hand turns about the line it
## already lies on. Influence is the base class's: this pass never applies it.
##
## See also: /docs/concepts/presentation.md

## The hand bones, dominant then off hand.
var hand_bones: PackedStringArray = PackedStringArray()
## Each hand's grip frame node (on the displayed sword): its global basis is
## the hand's global orientation. Read only when no resolved targets are given.
var frames: Array[Node3D] = []
## Both hands' resolved targets (`CombatPoseModifier3D.hand_targets`): when set,
## the orientation comes from them — the one record the IK also reached — and
## the rotation this pass applies is written back as each target's
## `orientation_residual` (a diagnostic, never a correction).
var targets: Array[ResolvedHandTarget] = []
## How far the handle may cross the palm off the knuckle line (radians).
var diagonal_limit: float = 0.0

var _bones := PackedInt32Array()


func _validate_bone_names() -> void:
	_bones = PackedInt32Array()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	var resolved := targets.size() == hand_bones.size()
	for target in targets:
		resolved = resolved and target.valid
	if skeleton == null or (not resolved and frames.size() != hand_bones.size()):
		return
	if _bones.size() != hand_bones.size():
		_bones.resize(hand_bones.size())
		for index in hand_bones.size():
			_bones[index] = skeleton.find_bone(hand_bones[index])
	var into_skeleton := skeleton.global_transform.basis.inverse()
	for index in _bones.size():
		var bone := _bones[index]
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var orientation := targets[index].target.basis if resolved else frames[index].global_transform.basis
		var wanted := (into_skeleton * orientation).orthonormalized()
		var local := (parent_basis.orthonormalized().inverse() * wanted).get_rotation_quaternion()
		if diagonal_limit > 0.0:
			local = untwisted(local, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(), diagonal_limit)
		if resolved:
			targets[index].orientation_residual = skeleton.get_bone_pose_rotation(bone).angle_to(local)
		skeleton.set_bone_pose_rotation(bone, local)


## The hand's local rotation `local` (against its parent) with up to `limit`
## radians of its twist about its own long axis (+Y), measured from its rest
## rotation `rest`, taken back out. The hand's long axis keeps its direction.
static func untwisted(local: Quaternion, rest: Quaternion, limit: float) -> Quaternion:
	var delta := rest.inverse() * local
	if is_zero_approx(delta.y) and is_zero_approx(delta.w):
		return local
	var twist := wrapf(2.0 * atan2(delta.y, delta.w), -PI, PI)
	var undo := clampf(twist, -limit, limit)
	return (local * Quaternion(Vector3.UP, -undo)).normalized()


## A hand's twist about its own long axis (radians, in [-π, π]) in `local`
## against its rest rotation `rest`.
static func twist_of(local: Quaternion, rest: Quaternion) -> float:
	var delta := rest.inverse() * local
	return wrapf(2.0 * atan2(delta.y, delta.w), -PI, PI)
