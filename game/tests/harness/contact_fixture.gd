class_name ContactFixture
extends RefCounted

## Test-only builders for collision and contact scenarios.
##
## See also: /docs/reference/testing.md


static func pose(x: float, y: float, facing: float, weapon_angle: float) -> FighterPose:
	var fighter := FighterState.new()
	DuelFixture.place(fighter, x, y, facing)
	fighter.weapon.angle = weapon_angle
	return FighterPose.capture(fighter)


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


static func start_poses(state: MatchState) -> Array[FighterPose]:
	return poses(FighterPose.capture(state.fighter(0)), FighterPose.capture(state.fighter(1)))


static func blade_report(ax: float, ay: float, bx: float, by: float) -> ContactReport:
	var report := ContactReport.new()
	report.blade = true
	report.blade_ax = ax
	report.blade_ay = ay
	report.blade_bx = bx
	report.blade_by = by
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
