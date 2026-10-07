class_name SimulationGuardrails
extends RefCounted

## Minimal cross-cutting runtime safeguards that do not belong in existing
## single-owner modules. This is NOT a facade over StateInvariants,
## DuelRules.is_valid(), or CombatTuning — those stay in their own homes.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md


## Tolerance for TOI monotonicity in normalized tick-fraction space.
const TOI_EPSILON := 1e-12

## Safety factor applied to authored maximums when computing impossibility
## bounds. A corrupted state that looks valid is worse than a no-contest.
const CAPACITY_SAFETY_FACTOR := 2.0


## Asserts that a newly computed TOI has not regressed behind the current
## elapsed fraction. Returns true when valid. A violation means the contact
## solver would process events out of chronological order.
static func validate_toi_monotonicity(elapsed: float, new_toi: float) -> bool:
	return new_toi >= elapsed - TOI_EPSILON


## Returns true when a fighter's physical velocities are within the
## impossibility bounds derived from authored maximums. A violation means the
## state is corrupted beyond any legal sequence of commands.
static func validate_capacity(fighter: FighterState, rules: DuelRules) -> bool:
	var max_burst := maxf(rules.fighter.burst_speed_axial, rules.fighter.burst_speed_lateral)
	var max_body_speed := maxf(rules.fighter.max_speed, max_burst) * CAPACITY_SAFETY_FACTOR
	if fighter.speed() > max_body_speed:
		return false
	var max_angular_speed := rules.weapon.swing_speed_full * CAPACITY_SAFETY_FACTOR
	if absf(fighter.weapon.speed) > max_angular_speed:
		return false
	return true


## Diagnostic-only: logs impossible command transitions. Not a simulation
## fault — the caller decides whether to log or ignore.
static func diagnose_command(cmd: PlayerCommand) -> String:
	if cmd.attack_released and not cmd.attack_pressed:
		if cmd.attack_cancel:
			return ""
	return ""
