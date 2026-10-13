class_name AuditedRigidSolver
extends RigidContactSolver

## Test-only: the real persistent-contact solver, with its actuators frozen and
## its effect measured. Substituted into a live duel, it collects the contact
## configurations real play produces — held blades, swords resting on torsos,
## a sword pinned between both — and records, for every solve:
##
## - the velocity stage's change in kinetic energy, in the solve's own mass
##   metric (each body and sword at the mass and inertia the solve used) — a
##   passive constraint can only remove it;
## - the change in total linear momentum in that metric, from either stage —
##   equal and opposite impulses move none.
##
## A turning fighter is a moving constraint that may do work, and that work is
## the facing actuator's, not the contact's. So the heading rates are zeroed
## for the duration of each velocity solve and restored after it.
##
## See also: /docs/reference/testing.md

var velocity_solves: int = 0
var position_solves: int = 0
## Largest kinetic-energy increase any velocity solve produced (J; ≤ 0 is passive).
var worst_energy_gain: float = -INF
## Largest change in total momentum any velocity solve produced (N·s).
var worst_momentum_change: float = 0.0
## Largest change any position solve made to a velocity (it should make none,
## so it can move neither kinetic energy nor momentum).
var worst_velocity_touch: float = 0.0
## Solves in which the body/body row took part, per stage. Body/body velocity
## response has one owner (`ContactResolver`, BODY-CONTACT-OWNERSHIP-001), so the
## velocity stage must count none; the position stage still keeps the bodies
## apart while it clears a sword.
var velocity_body_rows: int = 0
var position_body_rows: int = 0
## Velocity solves in which a sword's guard stop took part, and the most any
## of them left that sword set to turn past its stop within the tick (rad/s;
## ≤ 0 means the stop was honoured).
var stop_solves: int = 0
var worst_stop_overrun: float = -INF


func solve_velocity(state: MatchState, rules: DuelRules, warm: bool = false) -> float:
	var a := state.fighter(0)
	var b := state.fighter(1)
	var turns := PackedFloat64Array([a.turn_rate, b.turn_rate])
	a.turn_rate = 0.0
	b.turn_rate = 0.0
	var before := _snapshot(state)
	var impulse := super.solve_velocity(state, rules, warm)
	velocity_body_rows += _active[ROW_BODIES]
	for slot in 2:
		if _active[ROW_STOP + slot] == 1:
			stop_solves += 1
			var sword := state.fighter(slot).weapon
			var room := rules.combatant(0).weapon.guard_limit - absf(sword.angle)
			worst_stop_overrun = maxf(worst_stop_overrun, signf(sword.angle) * sword.speed - room / SimulationTimebase.TICK_SECONDS)
	if impulse > 0.0:
		velocity_solves += 1
		var after := _snapshot(state)
		worst_energy_gain = maxf(worst_energy_gain, _energy(after) - _energy(before))
		worst_momentum_change = maxf(worst_momentum_change, SimMath.length(
			body_mass(0) * (after[2] - before[2]) + body_mass(1) * (after[7] - before[7]),
			body_mass(0) * (after[3] - before[3]) + body_mass(1) * (after[8] - before[8])
		))
	a.turn_rate = turns[0]
	b.turn_rate = turns[1]
	return impulse


func project(state: MatchState, rules: DuelRules) -> void:
	var before := _snapshot(state)
	super.project(state, rules)
	var after := _snapshot(state)
	if before == after:
		return
	position_solves += 1
	position_body_rows += _active[ROW_BODIES]
	for i: int in [2, 3, 4, 7, 8, 9]:
		worst_velocity_touch = maxf(worst_velocity_touch, absf(after[i] - before[i]))


## [x, y, vx, vy, θ̇] for slot 0 then slot 1.
func _snapshot(state: MatchState) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for fighter in state.fighters:
		out.append_array([fighter.x, fighter.y, fighter.vx, fighter.vy, fighter.weapon.speed])
	return out


func _energy(s: PackedFloat64Array) -> float:
	var bodies := 0.5 * body_mass(0) * (s[2] * s[2] + s[3] * s[3]) + 0.5 * body_mass(1) * (s[7] * s[7] + s[8] * s[8])
	return bodies + 0.5 * sword_inertia(0) * s[4] * s[4] + 0.5 * sword_inertia(1) * s[9] * s[9]
