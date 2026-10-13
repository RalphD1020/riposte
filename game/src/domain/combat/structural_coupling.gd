class_name StructuralCoupling
extends RefCounted

## How well the fighter's structure supports the cut at an impact (COMBAT §36,
## §62): a reading of the body's current motion taken at the moment of contact,
## derived, never persisted. No movement state carries a damage bonus or
## penalty — the differences between planted, advancing and retreating strikes
## fall out of the ingredients below.
##
## Coupling is never a mass and never an inertia. Bodies answer every contact
## with their real mass, and the held sword's inertia is the sword plus the
## hands on the grip (rules v33, PHYS-002). How hard a planted or committed
## fighter pushes back is the bounded actuators' answer. Coupling remains a
## reading of structure for presentation and the CPU.
##
## Commitment is a different question. Commitment asks "how hard is this
## action to change?"; coupling asks "how well is the body supporting this
## impact?". A fully charged swing thrown mid-sidestep is maximally committed
## and badly structured at the same time, and that gap is where skill lives.
##
## Implements: /spec/invariants.md#phys-002
## See also: /docs/concepts/combat.md


## How settled the body is, 1 = feet planted and quiet. Speed, violent
## acceleration and fast rotation each erode it, so a fighter who merely
## stopped moving is not instantly as planted as one who has been still.
static func plant_quality(fighter: FighterState, definition: FighterDefinition, tuning: CombatTuning) -> float:
	var speed_debt := SimMath.clamp01(fighter.speed() / definition.max_speed)
	var turn_debt := SimMath.clamp01(absf(fighter.turn_rate) / definition.turn_speed_max)
	return clampf(
		1.0
		- tuning.plant_speed_weight * speed_debt
		- tuning.plant_accel_weight * acceleration_debt(fighter, definition)
		- tuning.plant_turn_weight * turn_debt,
		0.0,
		1.0
	)


## Control authority currently being spent changing the body's own motion
## rather than holding a coherent structure (COMBAT §62).
static func acceleration_debt(fighter: FighterState, definition: FighterDefinition) -> float:
	return SimMath.clamp01(fighter.acceleration() / definition.brake_accel())


## Does the body's motion support this strike? `+1` is driving straight
## through it, `0` is perpendicular, `-1` is moving away from it. Normalized
## into `[0, 1]` so a standing fighter sits at the neutral midpoint rather
## than being penalised for not moving.
##
## `strike_x` / `strike_y` must be a unit vector in the direction the
## contact point is travelling.
static func movement_coherence(fighter: FighterState, strike_x: float, strike_y: float) -> float:
	var speed := fighter.speed()
	if speed <= SimMath.EPSILON:
		return 0.5
	return SimMath.clamp01(0.5 + 0.5 * (fighter.vx * strike_x + fighter.vy * strike_y) / speed)


## Structural coupling `C_s ∈ [floor, 1]`.
##
## Plant quality is the dominant ingredient but not the whole story: a smooth
## advancing drive can be only moderately planted and still couple well,
## which is what the fencing evidence on rear-leg propulsion describes. The
## floor keeps lateral attacks and retreating counters viable — planted is the
## most *controlled* stance, not the universally optimal one.
static func coupling(fighter: FighterState, strike_x: float, strike_y: float, definition: FighterDefinition, tuning: CombatTuning) -> float:
	var plant := plant_quality(fighter, definition, tuning)
	var coherence := movement_coherence(fighter, strike_x, strike_y)
	var structure := SimMath.mix(plant, coherence, tuning.coupling_coherence_share)
	return clampf(structure, tuning.coupling_floor, 1.0)
