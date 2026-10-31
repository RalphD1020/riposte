class_name ClipPose
extends RefCounted

## Poses a skeleton from a clip and skins a mesh on it, without the scene tree.
## Clips name bones, so a clip authored on WolfRig drives any skeleton that
## carries WolfRig's bone names. `PRES-PRODUCTION` poses with it and
## `tools/capture_production.gd` poses the capture rig with it, so the gate and
## the review pictures share one definition of every pose.


## Pose `skeleton` at `time` of `clip`, starting from rest.
static func apply(skeleton: Skeleton3D, clip: Animation, time: float) -> void:
	skeleton.reset_bone_poses()
	for track in clip.get_track_count():
		var path := String(clip.track_get_path(track))
		var bone := skeleton.find_bone(path.get_slice(":", path.get_slice_count(":") - 1))
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, clip.position_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, clip.scale_track_interpolate(track, time))


## Bend `bone` from its rest by `degrees` about its local `axis`.
static func bend(skeleton: Skeleton3D, bone_name: String, axis: Vector3, degrees: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, rest * Quaternion(axis, deg_to_rad(degrees)))


## Turn `bone_name` so its length (local +Y) points along the skeleton-space
## `direction`, by the shortest rotation from where it points now.
static func aim(skeleton: Skeleton3D, bone_name: String, direction: Vector3) -> void:
	var bone := skeleton.find_bone(bone_name)
	var parent := skeleton.get_bone_parent(bone)
	var parent_global := global_poses(skeleton)[parent] if parent >= 0 else Transform3D.IDENTITY
	var current := (parent_global * skeleton.get_bone_pose(bone)).basis
	var wanted := Basis(Quaternion(current.y.normalized(), direction.normalized())) * current
	skeleton.set_bone_pose_rotation(bone, (parent_global.basis.inverse() * wanted).get_rotation_quaternion())


## Aim a whole arm (upper arm, forearm, hand) straight along `direction`.
static func aim_arm(skeleton: Skeleton3D, side: String, direction: Vector3) -> void:
	for bone_name: String in ["UpperArm." + side, "Forearm." + side, "Hand." + side]:
		aim(skeleton, bone_name, direction)


## Roll `bone_name` about its own length by `degrees` from its current pose.
static func twist(skeleton: Skeleton3D, bone_name: String, degrees: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	var current := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, current * Quaternion(Vector3.UP, deg_to_rad(degrees)))


## Raise both clavicles by `response` to their arms' current elevation, as
## `CombatPoseModifier3D` does at runtime for clip-driven arms (no grip).
static func raise_clavicles(skeleton: Skeleton3D, response: ClavicleResponse) -> void:
	for side: String in ["L", "R"]:
		var upper := skeleton.find_bone("UpperArm." + side)
		var collar := skeleton.get_bone_parent(upper)
		var torso := skeleton.get_bone_parent(collar)
		var poses := global_poses(skeleton)
		var lift := response.elevation(ClavicleResponse.arm_elevation(poses[torso].basis.y.normalized(), poses[upper].basis.y.normalized()))
		ClavicleResponse.raise(skeleton, collar, lift, poses[torso])


## Every bone's skeleton-space pose, composed from its local pose and its
## parent's. Composed here rather than read from `get_bone_global_pose`, whose
## cache a skeleton outside the scene tree does not refresh on a pose write:
## reading it would skin the rest pose at every frame and prove nothing.
static func global_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	poses.resize(skeleton.get_bone_count())
	var done := PackedByteArray()
	done.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():
		_compose(skeleton, bone, poses, done)
	return poses


static func _compose(skeleton: Skeleton3D, bone: int, poses: Array[Transform3D], done: PackedByteArray) -> Transform3D:
	if done[bone] == 1:
		return poses[bone]
	var parent := skeleton.get_bone_parent(bone)
	var local := skeleton.get_bone_pose(bone)
	poses[bone] = local if parent < 0 else _compose(skeleton, parent, poses, done) * local
	done[bone] = 1
	return poses[bone]
