class_name StaminaModel
extends RefCounted

## Pure stamina arithmetic (STAMINA-004). Every function reads its inputs and
## returns a plain value: no allocation, no side effects, no state.
##
## Stamina s ∈ [0, 1] is a physical resource. The motors' own work drains it,
## a dash's start costs a fixed amount once, and easing off recovers it. It
## settles once at the end of a live tick, so a tick's capability comes from
## its starting stamina and the settled value decides the next tick's.
##
## ```text
## e = Σ_c k_c · (W⁺_c + β·W⁻_c) / R_c      c ∈ {footwork, heading, blade}
## s ← clamp(s − e − d + r, 0, 1)
## ```
##
## Implements: /spec/invariants.md#stamina-004
## See also: /docs/concepts/combat.md


## Whether a dash may start from stamina `s`. A refused dash costs nothing.
static func can_dash(s: float, combat: CombatTuning) -> bool:
	return s >= combat.stamina_dash_cost


## Whether a held charge may earn wind-back credit from stamina `s`.
static func can_charge(s: float) -> bool:
	return s > 0.0


## Footwork's reference energy: bringing the body from rest to its top speed.
static func move_reference(body: FighterDefinition) -> float:
	return 0.5 * body.mass * body.max_speed * body.max_speed


## The heading's reference energy: spinning the body up to its top turn rate.
static func turn_reference(body: FighterDefinition) -> float:
	return 0.5 * body.moment_of_inertia() * body.turn_speed_max * body.turn_speed_max


## The blade's reference energy: the held sword at its guard, moving at a
## full charge's swing speed.
static func swing_reference(spec: CombatantPhysicsSpec) -> float:
	var inertia := WeaponKinematics.motor_inertia(spec, -spec.weapon.guard_angle)
	return 0.5 * inertia * spec.weapon.swing_speed_full * spec.weapon.swing_speed_full


## One motor's stamina cost for a tick whose power was `power` (W) over `dt`:
## its driving work at full weight, its braking work at `brake_share`, per
## `reference_energy` joules, at `cost` stamina per reference.
static func channel(power: float, dt: float, reference_energy: float, cost: float, combat: CombatTuning) -> float:
	if reference_energy <= 0.0:
		return 0.0
	var work := power * dt
	return cost * (maxf(work, 0.0) + combat.stamina_brake_share * maxf(-work, 0.0)) / reference_energy


## Stamina after a live tick that cost `exertion`, started a dash or not, at
## `dt` seconds. Recovery only while the tick's exertion stayed at or under
## the recovery ceiling (easing off), never while exerting.
static func settle(s: float, exertion: float, dashed: bool, dt: float, combat: CombatTuning) -> float:
	var recovered := combat.stamina_recovery_rate * dt if exertion <= combat.stamina_recovery_effort_ceiling * dt else 0.0
	var dash := combat.stamina_dash_cost if dashed else 0.0
	return SimMath.clamp01(s - exertion - dash + recovered)
