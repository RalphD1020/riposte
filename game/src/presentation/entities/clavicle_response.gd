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
## Protraction: the girdle comes forward as its arm reaches forward and across
## the chest (a two-handed grip in front of the body), so the upper arm swings
## from a shoulder that travelled with it instead of sweeping through the
## pectoral and front deltoid. Measured as the arm's horizontal reach from its
## own outward side (`arm_reach_across`): 0° straight out, 90° straight ahead,
## more across the chest. A ceiling of 0 keeps the girdle where elevation put
## it: a body that does not declare protraction is unchanged.
@export_range(0.0, 180.0) var protraction_dead_zone_deg: float = 60.0
@export_range(0.0, 180.0) var protraction_full_deg: float = 120.0
@export_range(0.0, 45.0) var max_protraction_deg: float = 0.0


## Clavicle elevation (radians) for an arm elevation (radians).
func elevation(arm_angle: float) -> float:
	return deg_to_rad(max_elevation_deg) * smoothstep(deg_to_rad(dead_zone_deg), deg_to_rad(full_deg), arm_angle)


## Clavicle protraction (radians) for an arm's `arm_reach_across` reading:
## `reach.x` the reach angle, `reach.y` how level the arm is (an arm hanging
## along the torso or held overhead does not pull the girdle forward).
func protraction(reach: Vector2) -> float:
	if max_protraction_deg <= 0.0:
		return 0.0
	return deg_to_rad(max_protraction_deg) * smoothstep(deg_to_rad(protraction_dead_zone_deg), deg_to_rad(protraction_full_deg), reach.x) * clampf(reach.y, 0.0, 1.0)


## How far an arm reaches forward and across, in the torso's horizontal plane:
## x the angle (radians) of the arm's horizontal part from its own `outward`
## side, 0 straight out, π/2 straight ahead, up to π across the chest (0 when
## the arm points behind the body); y the length of that horizontal part (0
## hanging or overhead, 1 level). `forward` is the torso's forward.
static func arm_reach_across(torso_up: Vector3, outward: Vector3, forward: Vector3, arm_direction: Vector3) -> Vector2:
	var up := torso_up.normalized()
	var level := arm_direction.normalized() - up * arm_direction.normalized().dot(up)
	var side := outward - up * outward.dot(up)
	if level.length_squared() < 1e-8 or side.length_squared() < 1e-8 or level.dot(forward) < 0.0:
		return Vector2(0.0, level.length())
	return Vector2(side.angle_to(level), level.length())


## Bring `clavicle` (a bone index) forward by `angle` radians: its lateral end
## turns toward `forward` (skeleton space) from its current pose. `parent_global`
## is the parent bone's skeleton-space pose, as for `raise`.
static func protract(skeleton: Skeleton3D, clavicle: int, angle: float, parent_global: Transform3D, forward: Vector3) -> void:
	if clavicle < 0 or is_zero_approx(angle):
		return
	var current := parent_global.basis * Basis(skeleton.get_bone_pose_rotation(clavicle))
	var axis := current.y.normalized().cross(forward.normalized())
	if axis.length_squared() < 1e-8:
		return
	var turned := Basis(axis.normalized(), angle) * current
	skeleton.set_bone_pose_rotation(clavicle, (parent_global.basis.inverse() * turned).get_rotation_quaternion())


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
