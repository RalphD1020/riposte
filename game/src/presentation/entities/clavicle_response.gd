class_name ClavicleResponse
extends Resource

## Clavicle participation (PRES-CLAVICLE-001): how far the shoulder girdle
## (each `Shoulder.*` bone) elevates as its arm rises, so the deltoid, the
## acromion and the trapezius rise with the arm instead of the arm swinging out
## of a static chest. A bounded smooth response θc = f(θa) — a dead zone, a
## gradual onset, a ceiling — calibrated against the combat captures, not an
## anatomical law (the 2:1 scapulohumeral rhythm is only a starting idea).
##
## Presentation only. It moves the displayed shoulder before the arm IK solves,
## so the hands still land on the grip; it never reaches the simulation, reach,
## hilt track, or hit detection, which read the rig contract's rest joints.
## Read-only at runtime: a scene owns one, nothing writes it.
##
## See also: /docs/concepts/presentation.md, /docs/concepts/character-modeling.md

## Arm elevation (angle between the arm and the torso's down axis) below which
## the clavicle stays at rest.
@export_range(0.0, 180.0) var dead_zone_deg: float = 45.0
## Arm elevation at which the clavicle reaches its ceiling.
@export_range(0.0, 180.0) var full_deg: float = 170.0
## The clavicle's ceiling (degrees of elevation about the chest's forward axis).
@export_range(0.0, 45.0) var max_elevation_deg: float = 26.0


## Clavicle elevation (radians) for an arm elevation (radians).
func elevation(arm_angle: float) -> float:
	return deg_to_rad(max_elevation_deg) * smoothstep(deg_to_rad(dead_zone_deg), deg_to_rad(full_deg), arm_angle)


## Arm elevation (radians): 0 hanging along the torso, π/2 level, π overhead.
static func arm_elevation(torso_up: Vector3, arm_direction: Vector3) -> float:
	return (-torso_up).angle_to(arm_direction)


## Raise `clavicle` (a bone index) by `angle` radians: its lateral end turns
## up about the axis across the chest, from its current pose. `parent_global`
## is the parent bone's skeleton-space pose (the modifier passes the live one;
## an off-tree pose composes it).
static func raise(skeleton: Skeleton3D, clavicle: int, angle: float, parent_global: Transform3D) -> void:
	if clavicle < 0 or is_zero_approx(angle):
		return
	var current := parent_global.basis * Basis(skeleton.get_bone_pose_rotation(clavicle))
	var along := current.y.normalized()
	var axis := along.cross(parent_global.basis.y.normalized())
	if axis.length_squared() < 1e-8:
		return
	var turned := Basis(axis.normalized(), angle) * current
	skeleton.set_bone_pose_rotation(clavicle, (parent_global.basis.inverse() * turned).get_rotation_quaternion())
