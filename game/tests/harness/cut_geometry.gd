class_name CutGeometry
extends RefCounted

## Test-only vocabulary for where a cut comes from and goes to, in the plane
## (ATTACK-SIDE-001). Never "left" or "right": those do not survive a mirror
## or a camera. From the attacker's combat heading φ and the cut's direction
## (`swing_dir`, or the side a strike not yet launched will commit to):
##
## ```text
## forward     = unit(φ)
## ccw         = perp_ccw(forward)
## origin_side = ccw · (−swing_dir)   the side the blade sweeps from
## end_side    = ccw · swing_dir      the side it sweeps toward
## ```
##
## A defender stepping toward `origin_side` steps behind the blade; toward
## `end_side`, into it. `step_intent` turns either into the duel-relative
## command a human would hold, and `outcome_cause` records whether a result
## came from the line, the measure, or both.
##
## See also: /docs/reference/testing.md

const LINE := "LINE"
const MEASURE := "MEASURE"
const LINE_AND_MEASURE := "LINE+MEASURE"
const NEITHER := "NEITHER"


## The direction the attacker's cut sweeps (+1 toward +θ): the swing in flight,
## or the one its blade will commit to.
static func cut_direction(attacker: FighterState) -> float:
	var weapon := attacker.weapon
	if CombatPhase.is_swinging(weapon.phase) or weapon.phase == CombatPhase.Id.CHARGING or weapon.phase == CombatPhase.Id.LAUNCH:
		return weapon.swing_dir
	return WeaponSystem.swing_direction(weapon)


## Unit world vector toward the side the attacker's cut comes from.
static func origin_side(attacker: FighterState) -> Vector2:
	return _ccw(attacker) * -cut_direction(attacker)


## Unit world vector toward the side the attacker's cut sweeps to.
static func end_side(attacker: FighterState) -> Vector2:
	return _ccw(attacker) * cut_direction(attacker)


## The duel-relative intent (`+y` toward the opponent, `+x` its clockwise
## side, `DuelGeometry.to_world`) that moves `mover`, facing `opponent`, along
## the world direction `world` — so a step "toward the origin side" is held as
## the stick a person would hold.
static func step_intent(mover: FighterState, opponent: FighterState, world: Vector2) -> Vector2:
	var forward := Vector2(opponent.x - mover.x, opponent.y - mover.y).normalized()
	var clockwise := Vector2(forward.y, -forward.x)
	return Vector2(world.dot(clockwise), world.dot(forward))


## What changed between two placements of a defender relative to an attacker:
## the bearing (LINE) by more than `bearing_tolerance` rad, the distance
## (MEASURE) by more than `distance_tolerance` m, both, or neither.
static func outcome_cause(bearing_change: float, distance_change: float, bearing_tolerance: float = 0.02, distance_tolerance: float = 0.02) -> String:
	var line := absf(bearing_change) > bearing_tolerance
	var measure := absf(distance_change) > distance_tolerance
	if line and measure:
		return LINE_AND_MEASURE
	if line:
		return LINE
	return MEASURE if measure else NEITHER


static func _ccw(attacker: FighterState) -> Vector2:
	return Vector2(-SimMath.sine(attacker.facing), SimMath.cosine(attacker.facing))
