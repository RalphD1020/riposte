class_name ContactFixture
extends RefCounted

## Test-only builders for collision and contact scenarios. Poses default to
## the revolute (fixed-pivot) weapon the hand-built scenes are written for.
##
## See also: /docs/reference/testing.md


static func pose(x: float, y: float, facing: float, weapon_angle: float, spec: CombatantPhysicsSpec = null) -> FighterPose:
	var fighter := FighterState.new()
	DuelFixture.place(fighter, x, y, facing)
	fighter.weapon.angle = weapon_angle
	return FighterPose.capture(fighter, spec if spec != null else DuelFixture.revolute_rules().combatant(0))


static func poses(first: FighterPose, second: FighterPose) -> Array[FighterPose]:
	var pair: Array[FighterPose] = [first, second]
	return pair


## Configure a fighter's spatial state and weapon for a contact scenario.
static func arm(
	fighter: FighterState,
	x: float,
	y: float,
	facing: float,
	weapon_angle: float,
	angular_speed: float,
	phase: CombatPhase.Id,
	charge: float,
	weapon: WeaponDefinition
) -> void:
	DuelFixture.place(fighter, x, y, facing)
	fighter.weapon.angle = weapon_angle
	fighter.weapon.speed = angular_speed
	fighter.weapon.swing_dir = 1.0 if angular_speed >= 0.0 else -1.0
	fighter.weapon.swing_start = weapon_angle
	fighter.weapon.swing_end = clampf(weapon_angle + fighter.weapon.swing_dir * weapon.arc(charge), -weapon.guard_limit, weapon.guard_limit)
	DuelFixture.commit(fighter, phase, charge, weapon)


## How far up the y axis fighter 1 (facing −y, sword at −`side`·45°) must stand
## from fighter 0 (at the origin facing +y, sword at +`side`·45°) for their
## crossed diagonal guards to sit `surface_gap` apart (m; negative overlaps) —
## the swords' nearest features, as `SwordContactGeometry.measure` reads them.
## Derived from the track rather than pinned, so a rules change to `C(θ)` moves
## the scene with it instead of silently pulling the guards apart. `offset_x`
## stands fighter 1 that far along x.
static func crossed_guard_separation(spec: CombatantPhysicsSpec, surface_gap: float, side: float = 1.0, offset_x: float = 0.0) -> float:
	var low := 0.5
	var high := 5.0
	var geometry := SwordContactGeometry.new()
	var a := FighterState.new()
	var b := FighterState.new()
	DuelFixture.place(a, 0.0, 0.0, PI / 2.0)
	a.weapon.angle = side * deg_to_rad(45.0)
	var pose_a := WeaponKinematics.pose_of(a, spec, BladePose.new())
	var pose_b := BladePose.new()
	for _iteration in 80:
		var mid := (low + high) * 0.5
		DuelFixture.place(b, offset_x, mid, -PI / 2.0)
		b.weapon.angle = side * deg_to_rad(-45.0)
		WeaponKinematics.pose_of(b, spec, pose_b)
		var gap := geometry.measure(a.x, a.y, pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, pose_b.origin_x, pose_b.origin_y, pose_b.ux, pose_b.uy, spec.weapon, spec.weapon)
		if gap < surface_gap:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


static func start_poses(state: MatchState, spec: CombatantPhysicsSpec = null) -> Array[FighterPose]:
	var definition := spec if spec != null else DuelFixture.revolute_rules().combatant(0)
	return poses(FighterPose.capture(state.fighter(0), definition), FighterPose.capture(state.fighter(1), definition))


## A first blade contact whose closest points are (`ax`, `ay`) on fighter 0's
## blade and (`bx`, `by`) on fighter 1's: recorded on `state`'s manifold as the
## sweep would (one blade-on-blade point at their midpoint, normal from b toward
## a), and reported.
static func blade_report(state: MatchState, ax: float, ay: float, bx: float, by: float) -> ContactReport:
	var report := ContactReport.new()
	report.blade = true
	report.blade_ax = ax
	report.blade_ay = ay
	report.blade_bx = bx
	report.blade_by = by
	var length := SimMath.length(ax - bx, ay - by)
	var manifold := state.blade_contact
	manifold.begin_substep()
	manifold.record_point(0, SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE, (ax + bx) * 0.5, (ay + by) * 0.5, 0.5, 0.5, (ax - bx) / length, (ay - by) / length)
	return report


static func body_report(attacker: int, x: float, y: float) -> ContactReport:
	var report := ContactReport.new()
	report.body[attacker] = true
	report.body_x[attacker] = x
	report.body_y[attacker] = y
	return report


static func body_push_report(nx: float, ny: float) -> ContactReport:
	var report := ContactReport.new()
	report.body_push = true
	report.body_push_nx = nx
	report.body_push_ny = ny
	return report
