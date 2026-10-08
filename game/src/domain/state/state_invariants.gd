class_name StateInvariants
extends RefCounted

## Per-tick totality check over authoritative state. `check` returns the id of
## the first violated invariant in a fixed order, or an empty StringName when
## the state is sound.
##
## This exists because a closed state-transition system must be total: every
## legal state/command pair has a defined successor, and anything outside that
## set is a defect, not a state to improvise from. External and input problems
## recover (a canceled charge, a clamped axis, an ignored duplicate edge); a
## non-finite or structurally impossible authoritative value fails closed, so
## `DuelSimulation` ends the match as a no-contest rather than silently
## resetting the sword to a canonical guard.
##
## Checks are straight-line scalar comparisons with no allocation: this runs
## every tick on mobile.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md

const OK := &""

## Slack for values the simulation clamps. Floating-point accumulation can land
## a hair outside a hard bound without the state being wrong.
const BOUND_SLACK := 0.000001

const TICK_NEGATIVE := &"tick_negative"
const PHASE_TICKS_NEGATIVE := &"phase_ticks_negative"
const SCORE_NEGATIVE := &"score_negative"
const FIGHTER_COUNT := &"fighter_count"
const POSITION_NOT_FINITE := &"position_not_finite"
const VELOCITY_NOT_FINITE := &"velocity_not_finite"
const FACING_NOT_FINITE := &"facing_not_finite"
const WEAPON_NOT_FINITE := &"weapon_not_finite"
const HEALTH_RANGE := &"health_range"
const STAMINA_NOT_FINITE := &"stamina_not_finite"
const STAMINA_OVER_MAX := &"stamina_over_max"
const STABILITY_RANGE := &"stability_range"
const ANGLE_OUT_OF_GUARD := &"angle_out_of_guard"
const CHARGE_RANGE := &"charge_range"
const WINDBACK_RANGE := &"windback_range"
const COMMITMENT_RANGE := &"commitment_range"
const SWING_DIRECTION := &"swing_direction"
const STABLE_SIDE := &"stable_side"
const READINESS_RANGE := &"readiness_range"
const COUNTER_NEGATIVE := &"counter_negative"
const DEATH_PHASE_MISMATCH := &"death_phase_mismatch"
const SIDE_COLLISION := &"side_collision"
const DUEL_BASIS_DEGENERATE := &"duel_basis_degenerate"
const BURST_TOO_LONG := &"burst_too_long"
const BURST_MODE_MISMATCH := &"burst_mode_mismatch"
const BURST_HEADING_DEGENERATE := &"burst_heading_degenerate"
const DEATH_TIME_MISMATCH := &"death_time_mismatch"
const DEATH_TIME_RANGE := &"death_time_range"
const CONTACT_PAIR_STUCK := &"contact_pair_stuck"
const BODY_SPEED_IMPOSSIBLE := &"body_speed_impossible"
const WEAPON_SPEED_IMPOSSIBLE := &"weapon_speed_impossible"
const ARENA_ESCAPE := &"arena_escape"
const BODY_CONTACT_MISMATCH := &"body_contact_mismatch"


## First violated invariant, or OK. Order is fixed so a fault is reproducible.
static func check(state: MatchState, rules: DuelRules) -> StringName:
	if state.tick < 0:
		return TICK_NEGATIVE
	if state.phase_ticks < 0 or state.round_ticks < 0:
		return PHASE_TICKS_NEGATIVE
	if state.scores[0] < 0 or state.scores[1] < 0:
		return SCORE_NEGATIVE
	if state.fighters.size() != 2:
		return FIGHTER_COUNT
	## A duel has exactly one fighter per end (SIDE-001). Two Lights would put
	## both spawns in the same place and leave the camera with no honest
	## answer about who is at the bottom of the screen.
	if state.fighter(0).side == state.fighter(1).side:
		return SIDE_COLLISION
	for fighter in state.fighters:
		var violation := check_fighter(fighter, rules)
		if violation != OK:
			return violation
	## Arena escape: a living, non-falling fighter must be inside the arena.
	## Falling fighters are beyond the edge by design (RING-OUT).
	for fighter in state.fighters:
		if fighter.is_alive() and not fighter.is_falling:
			var distance := SimMath.length(fighter.x, fighter.y)
			if distance > rules.platform_radius + BOUND_SLACK:
				return ARENA_ESCAPE
	var body_contact_violation := check_body_contact(state)
	if body_contact_violation != OK:
		return body_contact_violation
	return check_contact(state, rules)


## Body-body lifecycle: ticks_in_contact must be zero when SEPARATED and
## non-negative when CONTACTING.
static func check_body_contact(state: MatchState) -> StringName:
	var bc := state.body_contact
	if bc.phase == BodyContactState.Phase.SEPARATED and bc.ticks_in_contact != 0:
		return BODY_CONTACT_MISMATCH
	if bc.ticks_in_contact < 0:
		return BODY_CONTACT_MISMATCH
	if not is_finite(bc.last_constraint_impulse):
		return BODY_CONTACT_MISMATCH
	if not is_finite(bc.last_constraint_normal_x):
		return BODY_CONTACT_MISMATCH
	if not is_finite(bc.last_constraint_normal_y):
		return BODY_CONTACT_MISMATCH
	return OK


## The contact lifecycle has to stay escapable. A pair parked in `BOUND` past
## its escape bound means the fail-safe in `ContactResolver.update_bind` did
## not fire, which is exactly the unrecoverable bind the design forbids.
##
## A one-sided bind is deliberately *not* checked here: killing or staggering
## a bound fighter legitimately leaves the other holding a bind for one tick,
## and `update_bind` releases it in-band on the next.
static func check_contact(state: MatchState, rules: DuelRules) -> StringName:
	var pair := state.blade_contact
	if pair.phase_ticks < 0:
		return COUNTER_NEGATIVE
	if pair.is_bound() and pair.phase_ticks > rules.combat.bind_escape_ticks:
		return CONTACT_PAIR_STUCK
	return OK


static func check_fighter(fighter: FighterState, rules: DuelRules) -> StringName:
	if not (is_finite(fighter.x) and is_finite(fighter.y)):
		return POSITION_NOT_FINITE
	if not (is_finite(fighter.vx) and is_finite(fighter.vy) and is_finite(fighter.ax) and is_finite(fighter.ay)):
		return VELOCITY_NOT_FINITE
	if not (is_finite(fighter.facing) and is_finite(fighter.turn_rate)):
		return FACING_NOT_FINITE
	## Footwork is rotated through this axis every tick, so a non-unit or
	## degenerate value would quietly scale or erase a fighter's movement.
	if absf(SimMath.length(fighter.duel_forward_x, fighter.duel_forward_y) - 1.0) > BOUND_SLACK:
		return DUEL_BASIS_DEGENERATE
	if fighter.health < -BOUND_SLACK or fighter.health > rules.fighter.max_health + BOUND_SLACK:
		return HEALTH_RANGE
	if not is_finite(fighter.stamina) or fighter.stamina < -BOUND_SLACK:
		return STAMINA_NOT_FINITE
	var stamina_max := StaminaModel.max_for_health(
		fighter.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat
	)
	if fighter.stamina > stamina_max + BOUND_SLACK:
		return STAMINA_OVER_MAX
	if (
		fighter.stability < rules.fighter.stability_floor - BOUND_SLACK
		or fighter.stability > 1.0 + BOUND_SLACK
	):
		return STABILITY_RANGE
	if fighter.stagger_left < 0:
		return COUNTER_NEGATIVE
	## A fighter is dead exactly when the weapon is in DEAD. One phase enum
	## makes `DEAD and CHARGING` unrepresentable; this proves the pair agrees.
	if fighter.is_alive() == (fighter.weapon.phase == CombatPhase.Id.DEAD):
		return DEATH_PHASE_MISMATCH
	## And a dead fighter knows when they fell. Trade attribution reads this,
	## so an unrecorded or out-of-tick death would silently award the round.
	if fighter.is_alive() != (fighter.lethal_fraction == FighterState.ALIVE):
		return DEATH_TIME_MISMATCH
	if not fighter.is_alive() and (fighter.lethal_fraction < 0.0 or fighter.lethal_fraction > 1.0):
		return DEATH_TIME_RANGE
	var gesture_violation := check_gesture(fighter.gesture, rules.fighter)
	if gesture_violation != OK:
		return gesture_violation
	if not SimulationGuardrails.validate_capacity(fighter, rules):
		if fighter.speed() > maxf(rules.fighter.max_speed, maxf(rules.fighter.burst_speed_axial, rules.fighter.burst_speed_lateral)) * SimulationGuardrails.CAPACITY_SAFETY_FACTOR:
			return BODY_SPEED_IMPOSSIBLE
		return WEAPON_SPEED_IMPOSSIBLE
	return check_weapon(fighter.weapon, rules.weapon)


## A burst is a bounded push in a frozen heading. Mode and counter have to
## agree, or a fighter would either be shoved forever or be in BURST with
## nothing driving them; the heading has to be a real direction, or the push
## would scale or vanish.
static func check_gesture(gesture: MovementGestureState, definition: FighterDefinition) -> StringName:
	if gesture.sector_ticks < 0 or gesture.burst_ticks_remaining < 0:
		return COUNTER_NEGATIVE
	if gesture.burst_ticks_remaining > definition.burst_ticks:
		return BURST_TOO_LONG
	if gesture.is_bursting() != (gesture.burst_ticks_remaining > 0):
		return BURST_MODE_MISMATCH
	if gesture.is_bursting() != (gesture.burst_kind != MovementGestureState.BurstKind.NONE):
		return BURST_MODE_MISMATCH
	if gesture.is_bursting() and absf(SimMath.length(gesture.burst_dir_x, gesture.burst_dir_y) - 1.0) > BOUND_SLACK:
		return BURST_HEADING_DEGENERATE
	if gesture.recovery_ticks_remaining < 0:
		return COUNTER_NEGATIVE
	if gesture.is_recovering() != (gesture.recovery_ticks_remaining > 0):
		return BURST_MODE_MISMATCH
	return OK


static func check_weapon(weapon: WeaponState, definition: WeaponDefinition) -> StringName:
	if not (
		is_finite(weapon.angle)
		and is_finite(weapon.speed)
		and is_finite(weapon.swing_start)
		and is_finite(weapon.swing_end)
		and is_finite(weapon.hold_start_angle)
		and is_finite(weapon.earned_windback)
	):
		return WEAPON_NOT_FINITE
	if absf(weapon.angle) > definition.guard_limit + BOUND_SLACK:
		return ANGLE_OUT_OF_GUARD
	if not _unit_range(weapon.charge) or not _unit_range(weapon.swing_charge):
		return CHARGE_RANGE
	## Wind-back is travel, so it is non-negative and cannot exceed the span
	## that buys full charge.
	if weapon.earned_windback < -BOUND_SLACK or weapon.earned_windback > definition.windback_span() + BOUND_SLACK:
		return WINDBACK_RANGE
	if not _unit_range(weapon.commitment) or not _unit_range(weapon.recovery_commitment):
		return COMMITMENT_RANGE
	if not _unit_range(weapon.launch_readiness):
		return READINESS_RANGE
	if weapon.swing_dir != 1.0 and weapon.swing_dir != -1.0:
		return SWING_DIRECTION
	if weapon.stable_side != 1.0 and weapon.stable_side != -1.0:
		return STABLE_SIDE
	if weapon.phase_ticks < 0 or weapon.recovery_left < 0 or weapon.bind_left < 0:
		return COUNTER_NEGATIVE
	return OK


static func _unit_range(value: float) -> bool:
	return is_finite(value) and value >= -BOUND_SLACK and value <= 1.0 + BOUND_SLACK
