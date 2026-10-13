class_name ContactGauge
extends RefCounted

## Contact readings shared by CONTACT-INTEGRITY (the designed witnesses) and
## CONTACT-INTEGRITY-SHIP (the long corpora): how far two swords, or a sword
## and a torso, are apart, and whether one blade has crossed the other. Test
## measurement only; nothing here is solved on.
##
## See also: /docs/reference/testing.md

## The development corpus the solver was built against (adversarial: a
## fallback is legal there, only bounded).
const DEVELOPMENT_SEEDS := [3, 5, 9, 17, 21, 33, 41, 57]
## The ship corpus: forty more duels nothing was tuned against.
const SHIP_SEEDS_FROM := 100
const SHIP_SEEDS := 40
const DUEL_TICKS := 1800
## What a held contact may sit beyond the slop at a tick boundary (m): the
## position stage's last linearized pass.
const NUMERICAL_TOLERANCE := 2.0e-4


## Surface gap between the two swords' nearest features — blade, guard or hilt
## (m, negative = overlap) — and which side of blade 0's line blade 1's tip
## lies on.
static func blades(rules: DuelRules, state: MatchState) -> Vector2:
	var w := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var gap := SwordContactGeometry.new().measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, w, w)
	var side := a.ux * (b.point_y(w.tip_radius) - a.origin_y) - a.uy * (b.point_x(w.tip_radius) - a.origin_x)
	return Vector2(gap, signf(side))


## Distance between the two blades' centrelines (m): zero means one blade has
## crossed through the other.
static func centrelines(rules: DuelRules, state: MatchState) -> float:
	var w := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		a.point_x(w.hilt_radius), a.point_y(w.hilt_radius), a.point_x(w.tip_radius), a.point_y(w.tip_radius),
		b.point_x(w.hilt_radius), b.point_y(w.hilt_radius), b.point_x(w.tip_radius), b.point_y(w.tip_radius),
		contact
	)
	return contact.distance


## Surface gap between `wielder`'s blade and `target`'s hurt torso (m).
static func body(rules: DuelRules, wielder: FighterState, target: FighterState) -> float:
	var w := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var pose := WeaponKinematics.pose_of(wielder, spec, BladePose.new())
	var hx := pose.point_x(w.hilt_radius)
	var hy := pose.point_y(w.hilt_radius)
	var tx := pose.point_x(w.tip_radius)
	var ty := pose.point_y(w.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, target.x, target.y)
	return SimMath.length(SimMath.mix(hx, tx, t) - target.x, SimMath.mix(hy, ty, t) - target.y) - rules.combatant(0).fighter.hurt_radius - w.blade_radius


## The most a held contact may overlap after any tick (m).
static func allowed(rules: DuelRules) -> float:
	return rules.combat.contact_slop + NUMERICAL_TOLERANCE
