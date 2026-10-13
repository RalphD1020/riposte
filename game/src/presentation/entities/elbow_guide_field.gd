class_name ElbowGuideField
extends RefCounted

## Where each elbow should bend (PRES-ARMS-001): a pure, deterministic mapping
## from the displayed hands, the fighter's bladed stance frame, and the guard
## or cut landmark to one IK pole target per arm. The chain is
##
##   stance (torso basis) → carriage (hilt, point) → grip targets
##     → elbow guides (this) → TwoBoneIK3D poles → arms
##
## The bend plane is the arm's own shoulder→hand line. The pole direction is
## the arm's own side of the posed shoulder line (never a position measured
## from the body's axis, which a coiled chest carries a shoulder across),
## projected off the shoulder→hand line (its dot with the
## outward horizontal is non-negative, so it never needs a sign flip), plus a
## downward hang and the landmark bulge with any inward part removed. Nothing
## here renormalizes a vanishing projection — that whirl is what flipped the
## right elbow as a cut released. The offsets blend through the landmarks with
## Longpoint as the bridge between sides. A guide inside the torso is pushed
## out to the clearance; the pole sits further along the same bulge.
##
## Inputs are VisualRoot space (+X the fighter's left, +Y up, +Z combat
## forward); `stance_yaw` turns combat forward into the torso's forward.
##
## See also: /docs/concepts/presentation.md

const ARM_RIGHT := 0
const ARM_LEFT := 1
## Longpoint owns the guides inside this corridor and hands back by its edge.
const LONGPOINT_ENTER := 12.0
const LONGPOINT_EXIT := 30.0
## Past centre, the follow-through structure takes over by this cut angle.
const FOLLOW_START := 15.0
const FOLLOW_END := 45.0

## Results of the last `sample` (VisualRoot space): the preferred elbow
## positions and the pole targets beyond them, per arm.
var guides: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var poles: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Per arm: the unit direction the elbow is asked to bulge (perpendicular to
## shoulder→hand), and the shoulder→hand distance — the debug overlay and
## PRES-RIG read both.
var bends: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var reaches: Array[float] = [0.0, 0.0]


## `hands`: [right hand, left hand] targets; `angle`: the authoritative sword
## angle; `gather`/`stance_weight`/`cut_angle` from `CombatPresentationField` and
## `CutPresentationCurve`; `load_side` −1 right, +1 left (the loaded side's
## elbow is the attacking one).
func sample(profile: ArmStructureProfile, stance_yaw: float, shoulders: Array[Vector3], hands: Array[Vector3], angle: float, gather: float, stance_weight: float, cut_angle: float, load_side: float) -> ElbowGuideField:
	var basis := Basis(Vector3.UP, stance_yaw)
	var forward := basis.z
	var right := -basis.x
	## Outward is along the shoulder line as posed: a coiled or shifted chest
	## carries the shoulders across the body's axis, never past each other.
	var shoulder_line := Vector3(shoulders[ARM_RIGHT].x - shoulders[ARM_LEFT].x, 0.0, shoulders[ARM_RIGHT].z - shoulders[ARM_LEFT].z)
	if shoulder_line.length_squared() > 1e-6:
		right = shoulder_line.normalized()
	var degrees := rad_to_deg(absf(angle))
	var longpoint := 1.0 - smoothstep(LONGPOINT_ENTER, LONGPOINT_EXIT, degrees)
	var follow := smoothstep(FOLLOW_START, FOLLOW_END, cut_angle) * (1.0 - stance_weight)
	for arm in 2:
		var side := right if arm == ARM_RIGHT else -right
		var arm_sign := -1.0 if arm == ARM_RIGHT else 1.0
		var attacking := load_side * arm_sign > 0.0
		var offset := Vector3(profile.mid_behind, profile.mid_outward, profile.mid_below)
		offset = offset.lerp(Vector3(profile.follow_behind, profile.follow_outward, profile.follow_below), follow)
		offset = offset.lerp(Vector3(profile.longpoint_behind, profile.longpoint_outward, profile.longpoint_below), longpoint)
		var loaded := Vector3(profile.load_attack_behind, profile.load_attack_outward, profile.load_attack_below) if attacking else Vector3(profile.load_support_behind, profile.load_support_outward, profile.load_support_below)
		offset = offset.lerp(loaded, gather)
		var hand := hands[arm]
		var shoulder := shoulders[arm]
		var line := hand - shoulder
		var reach := line.length()
		var along := line / reach if reach > 1e-6 else forward
		## Projected onto the plane and kept at that length. Normalizing a
		## vanishing projection is the whirl that flipped the elbow on release.
		var side_perp := _perpendicular(side, along)
		var down := _perpendicular(Vector3.DOWN, along)
		var back := _perpendicular(-forward, along)
		var middle := shoulder + line * 0.5
		## This arm's own side of the shoulder line: a hand that crosses the
		## centre, or a shoulder carried over the body's axis, cannot reverse it.
		var away := Vector3(side.x, 0.0, side.z)
		## `away` projected off the arm has a non-negative dot with `away`,
		## so this direction never needs a sign flip.
		var away_plane := _perpendicular(away, along)
		var shaped := side_perp * offset.y + down * offset.z + back * offset.x
		if away_plane.length_squared() > 1e-6:
			var plane_n := away_plane.normalized()
			var against := shaped.dot(plane_n)
			if against < 0.0:
				shaped -= plane_n * against
		## When the outward plane is well defined it owns the pole. A short
		## projection must fade out (weight → 0) rather than be normalized up
		## to a full reach — that whirl flipped the elbow on release. Down
		## only fills in as the outward plane disappears, and only on the
		## outward side of it.
		if away_plane.length_squared() > 1e-6:
			var inward_n := -away_plane.normalized()
			var hanging_in := down.dot(inward_n)
			if hanging_in > 0.0:
				down -= inward_n * hanging_in
		var outward_weight := clampf(away_plane.length() * 2.0, 0.0, 1.0)
		var forward_plane := _perpendicular(forward, along)
		## Extra forward on the support arm while gathered. The high load brings
		## that forearm against the ribs; the same bias on the striking arm
		## folds its elbow back toward the torso.
		var support := 1.0 if load_side * arm_sign < 0.0 else 0.0
		var pole_vec := down * 0.15 * (1.0 - outward_weight) + forward_plane * (0.16 + 0.12 * gather * support)
		if away_plane.length_squared() > 1e-6:
			pole_vec += away_plane.normalized() * profile.pole_reach * outward_weight + shaped * 0.1 * outward_weight
		if pole_vec.length_squared() < 1e-6:
			pole_vec = side
		var bend := pole_vec.normalized()
		guides[arm] = _clear_torso(profile, basis, middle + shaped)
		poles[arm] = middle + bend * profile.pole_reach
		bends[arm] = bend
		reaches[arm] = reach
	return self


## The component of `direction` perpendicular to the unit `axis`.
static func _perpendicular(direction: Vector3, axis: Vector3) -> Vector3:
	return direction - axis * direction.dot(axis)





## Bring `guide` out in front of the torso ellipse (stance frame, inflated by
## the clearance): elbows support the hands from in front of the ribs, so a
## guide inside is moved forward to the front surface — never slid sideways
## across the chest.
static func _clear_torso(profile: ArmStructureProfile, basis: Basis, guide: Vector3) -> Vector3:
	var local := basis.inverse() * guide
	var a := profile.torso_half_width + profile.elbow_clearance
	var b := profile.torso_half_depth + profile.elbow_clearance
	var inside := pow(local.x / a, 2.0) + pow(local.z / b, 2.0)
	if inside <= 1.0:
		var front := b * sqrt(maxf(0.0, 1.0 - pow(local.x / a, 2.0)))
		local.z = front if local.z >= 0.0 else -front
	return basis * local
