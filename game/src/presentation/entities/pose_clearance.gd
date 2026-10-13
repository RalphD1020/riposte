class_name PoseClearance
extends RefCounted

## Pure geometry over a posed fighter (PRES-POSE-001): how much air every limb
## sample and the weapon keep from the fighter's own clearance proxies
## (`SelfClearanceProfile`). Deterministic, allocation-light, no physics:
## proxies are read in their own bones' rest frames, so a coiled or bladed
## torso carries its shells with it.
##
## Used by PRES-RIG's sweeps and by the capture tools' debug overlay; nothing
## at runtime moves the sword by it (WEAPON-ORBIT-005). A negative gap is a
## penetration.
##
## See also: /docs/concepts/presentation.md

## Samples along a rigid segment (limb or blade): ends included.
const SEGMENT_SAMPLES := 5


## Air between `point` (skeleton space) and the nearest torso shell; +INF when
## no shell's height band contains it.
static func torso_gap(profile: SelfClearanceProfile, skeleton: Skeleton3D, point: Vector3) -> float:
	var nearest := INF
	for shell: Array in profile.torso_shells:
		var bone := skeleton.find_bone(String(shell[0]))
		if bone < 0:
			continue
		var at := skeleton.get_bone_global_rest(bone) * (skeleton.get_bone_global_pose(bone).affine_inverse() * point)
		if at.y < float(shell[1]) or at.y > float(shell[2]):
			continue
		var a := float(shell[3])
		var b := float(shell[4])
		var reach := sqrt(pow(at.x / a, 2.0) + pow(at.z / b, 2.0))
		nearest = minf(nearest, (reach - 1.0) * minf(a, b))
	return nearest


## Air between `point` (skeleton space) and the head sphere.
static func head_gap(profile: SelfClearanceProfile, skeleton: Skeleton3D, point: Vector3) -> float:
	var bone := skeleton.find_bone(String(profile.head_bone))
	if bone < 0:
		return INF
	var rest := skeleton.get_bone_global_rest(bone)
	var centre_rest := Vector3(rest.origin.x, profile.head_center_height, rest.origin.z)
	var centre := skeleton.get_bone_global_pose(bone) * (rest.affine_inverse() * centre_rest)
	return point.distance_to(centre) - profile.head_radius


## The least torso air along the rigid segment `from` → `to`.
static func segment_torso_gap(profile: SelfClearanceProfile, skeleton: Skeleton3D, from: Vector3, to: Vector3) -> float:
	var nearest := INF
	for index in SEGMENT_SAMPLES:
		nearest = minf(nearest, torso_gap(profile, skeleton, from.lerp(to, float(index) / float(SEGMENT_SAMPLES - 1))))
	return nearest


## The least air the weapon (pommel → tip, skeleton space) keeps from the
## torso and the head.
static func weapon_gap(profile: SelfClearanceProfile, skeleton: Skeleton3D, pommel: Vector3, tip: Vector3) -> float:
	var nearest := INF
	var samples := SEGMENT_SAMPLES * 3
	for index in samples:
		var at := pommel.lerp(tip, float(index) / float(samples - 1))
		nearest = minf(nearest, minf(torso_gap(profile, skeleton, at), head_gap(profile, skeleton, at)))
	return nearest
