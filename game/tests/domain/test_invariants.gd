extends TestCase

## INVARIANT: proves the simulation is total. Sound states pass every tick of a
## real match; an impossible authoritative value is detected by id and ends the
## match as a no-contest instead of being silently repaired.
##
## Also pins the canonical tick order, both as a version constant and through
## two behavioral consequences of the documented sequence.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/reference/testing.md

const LONG_RUN_TICKS := 1800
const PUSH_TICKS := 240


func _init() -> void:
	suite_name = "INVARIANT"


func test_fresh_state_is_sound() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "a freshly set-up duel satisfies every invariant")


func test_full_match_never_violates_an_invariant() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 20261004)
	runner.run(Pilot.wander(20261004, 0), Pilot.wander(20261004, 1), LONG_RUN_TICKS)
	assert_true(runner.is_sound(), "a long contested match stays inside the legal state set (%s)" % runner.violation_summary())
	assert_eq(runner.count(DuelEventTypes.SIMULATION_FAULT), 0, "a sound match emits no simulation fault")
	assert_true(runner.state.tick > 0, "the match actually advanced")


func test_negative_score_is_detected_by_id() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.scores[0] = -1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.SCORE_NEGATIVE, "a negative score names the score invariant")


func test_missing_fighter_is_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighters.remove_at(1)
	assert_eq(StateInvariants.check(state, rules), StateInvariants.FIGHTER_COUNT, "a duel without two fighters is not a duel")


func test_negative_tick_and_counters_are_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.round_ticks = -1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.PHASE_TICKS_NEGATIVE, "a negative round counter is rejected")
	state.round_ticks = 0
	state.tick = -5
	assert_eq(StateInvariants.check(state, rules), StateInvariants.TICK_NEGATIVE, "a negative tick is rejected")


func test_non_finite_body_values_are_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighter(0).x = NAN
	assert_eq(StateInvariants.check(state, rules), StateInvariants.POSITION_NOT_FINITE, "a NaN position is rejected")
	state.fighter(0).x = 0.0
	state.fighter(0).vy = INF
	assert_eq(StateInvariants.check(state, rules), StateInvariants.VELOCITY_NOT_FINITE, "an infinite velocity is rejected")
	state.fighter(0).vy = 0.0
	state.fighter(0).turn_rate = NAN
	assert_eq(StateInvariants.check(state, rules), StateInvariants.FACING_NOT_FINITE, "a NaN turn rate is rejected")


func test_out_of_range_health_and_stability_are_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighter(1).health = -5.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.HEALTH_RANGE, "negative health is rejected")
	state.fighter(1).health = rules.fighter.max_health + 1.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.HEALTH_RANGE, "health above the authored maximum is rejected")
	state.fighter(1).health = rules.fighter.max_health
	state.fighter(1).stability = 1.5
	assert_eq(StateInvariants.check(state, rules), StateInvariants.STABILITY_RANGE, "stability above one is rejected")
	state.fighter(1).stability = rules.fighter.stability_floor - 0.1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.STABILITY_RANGE, "stability below the authored floor is rejected")


func test_non_finite_or_negative_stamina_is_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighter(0).stamina = NAN
	assert_eq(StateInvariants.check(state, rules), StateInvariants.STAMINA_NOT_FINITE, "NaN stamina is rejected")
	state.fighter(0).stamina = -1.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.STAMINA_NOT_FINITE, "negative stamina is rejected")
	state.fighter(0).stamina = rules.fighter.base_stamina
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "full stamina is sound")


func test_death_and_weapon_phase_must_agree() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighter(0).health = 0.0
	state.fighter(0).stamina = 0.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.DEATH_PHASE_MISMATCH, "a fighter at zero health outside DEAD is impossible")
	state.fighter(0).weapon.set_phase(CombatPhase.Id.DEAD)
	state.fighter(0).lethal_fraction = 0.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "zero health with a DEAD weapon is sound")
	state.fighter(0).health = rules.fighter.max_health
	state.fighter(0).stamina = rules.fighter.base_stamina
	assert_eq(StateInvariants.check(state, rules), StateInvariants.DEATH_PHASE_MISMATCH, "a living fighter in DEAD is impossible")


## Trade attribution is decided by the moment of death, so an unrecorded
## moment — or one from outside the tick it happened in — would quietly hand
## someone a round.
func test_a_death_must_record_when_it_happened() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	DuelFixture.kill(state.fighter(0))
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "a recorded death is sound")
	state.fighter(0).lethal_fraction = FighterState.ALIVE
	assert_eq(StateInvariants.check(state, rules), StateInvariants.DEATH_TIME_MISMATCH, "a death with no moment is impossible")
	state.fighter(0).lethal_fraction = 1.5
	assert_eq(StateInvariants.check(state, rules), StateInvariants.DEATH_TIME_RANGE, "a death outside its own tick is impossible")
	var standing := DuelFixture.state(rules)
	standing.fighter(1).lethal_fraction = 0.3
	assert_eq(StateInvariants.check(standing, rules), StateInvariants.DEATH_TIME_MISMATCH, "and a fighter still on their feet never fell")


func test_weapon_bounds_are_detected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var weapon := state.fighter(0).weapon
	weapon.angle = rules.weapon.guard_limit + 0.05
	assert_eq(StateInvariants.check(state, rules), StateInvariants.ANGLE_OUT_OF_GUARD, "an angle past the guard limit is rejected")
	weapon.angle = -rules.weapon.guard_angle
	weapon.speed = NAN
	assert_eq(StateInvariants.check(state, rules), StateInvariants.WEAPON_NOT_FINITE, "a NaN angular speed is rejected")
	weapon.speed = 0.0
	weapon.charge = 1.4
	assert_eq(StateInvariants.check(state, rules), StateInvariants.CHARGE_RANGE, "charge above one is rejected")
	weapon.charge = 0.0
	weapon.earned_windback = -0.2
	assert_eq(StateInvariants.check(state, rules), StateInvariants.WINDBACK_RANGE, "negative wind-back is rejected")
	weapon.earned_windback = rules.weapon.windback_span() * 2.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.WINDBACK_RANGE, "wind-back beyond the span that buys full charge is rejected")
	weapon.earned_windback = 0.0
	weapon.commitment = -0.3
	assert_eq(StateInvariants.check(state, rules), StateInvariants.COMMITMENT_RANGE, "negative commitment is rejected")
	weapon.commitment = 0.0
	weapon.swing_dir = 0.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.SWING_DIRECTION, "a swing direction must be exactly plus or minus one")
	weapon.swing_dir = 1.0
	weapon.bind_left = -2
	assert_eq(StateInvariants.check(state, rules), StateInvariants.COUNTER_NEGATIVE, "a negative bind counter is rejected")
	weapon.bind_left = 0


func test_an_inescapable_bind_is_detected() -> void:
	## The contact lifecycle must stay escapable (COMBAT §45). Park the pair
	## in BOUND past its escape bound and the totality check must say so,
	## rather than letting a duel sit in a deadlock nobody can leave.
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.blade_contact.set_phase(ContactPairState.Phase.BOUND)
	state.blade_contact.phase_ticks = rules.combat.bind_escape_ticks
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "a bind at its escape bound is still legal")
	state.blade_contact.phase_ticks = rules.combat.bind_escape_ticks + 1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.CONTACT_PAIR_STUCK, "one tick past it is not")
	state.blade_contact.set_phase(ContactPairState.Phase.SEPARATED)
	state.blade_contact.phase_ticks = -1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.COUNTER_NEGATIVE, "and a negative pair counter is rejected")


func test_clamped_bounds_tolerate_float_slack() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var weapon := state.fighter(0).weapon
	weapon.angle = rules.weapon.guard_limit + StateInvariants.BOUND_SLACK * 0.5
	weapon.charge = 1.0 + StateInvariants.BOUND_SLACK * 0.5
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "accumulation a hair outside a clamped bound is not a fault")


func test_violation_ends_the_match_as_no_contest() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 7)
	runner.skip_intro()
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_ACTIVE, "the round is live before the perturbation")
	runner.state.scores[1] = -3
	runner.idle(1)
	var fault := runner.first(DuelEventTypes.SIMULATION_FAULT)
	assert_ne(fault, null, "an impossible score emits a simulation fault")
	assert_eq(fault.text(DuelEventKeys.INVARIANT), String(StateInvariants.SCORE_NEGATIVE), "the fault names the invariant that failed")
	assert_eq(runner.state.end_reason, MatchPhase.REASON_NO_CONTEST, "a faulted match is void, not a result")
	assert_eq(runner.state.match_winner, MatchPhase.DRAW, "a no-contest crowns nobody")
	assert_true(runner.state.is_finished(), "a faulted match accepts no further steps")


func test_fault_does_not_repair_the_offending_state() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 9)
	runner.skip_intro()
	runner.state.fighter(0).weapon.charge = 5.0
	runner.idle(1)
	assert_eq(runner.count(DuelEventTypes.SIMULATION_FAULT), 1, "the fault fires exactly once")
	assert_eq(runner.state.fighter(0).weapon.charge, 5.0, "failing closed preserves the evidence instead of resetting the sword")
	assert_false(runner.is_sound(), "the runner audit records the violated tick")


func test_finished_match_emits_no_further_faults() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 11)
	runner.skip_intro()
	runner.state.scores[0] = -1
	runner.idle(5)
	assert_eq(runner.count(DuelEventTypes.SIMULATION_FAULT), 1, "a finished match is not re-faulted every tick")


func test_tick_order_version_is_pinned() -> void:
	assert_eq(DuelSimulation.TICK_ORDER_VERSION, 7, "the canonical tick order is version 7; bump this deliberately")


func test_input_edges_resolve_before_the_motor() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var resting := runner.state.fighter(0).weapon.angle
	runner.simulation.step(
		runner.state,
		PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true),
		PlayerCommand.idle(runner.state.tick)
	)
	var weapon := runner.state.fighter(0).weapon
	assert_true(CombatPhase.is_swinging(weapon.phase), "step 5 consumes the tap before step 8 drives the motor, so the swing is live on the same tick")
	assert_ne(weapon.angle, resting, "the motor already moved the blade on the launching tick")
	assert_eq(StateInvariants.check(runner.state, rules), StateInvariants.OK, "a same-tick tap leaves a sound state")


func test_arena_confinement_runs_after_footwork() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var limit := rules.arena_radius - rules.fighter.body_radius
	var worst := 0.0
	for _i in PUSH_TICKS:
		runner.simulation.step(
			runner.state,
			PlayerCommand.create(runner.state.tick, -1.0, 0.0),
			PlayerCommand.create(runner.state.tick, 1.0, 0.0)
		)
		for slot in 2:
			var fighter := runner.state.fighter(slot)
			worst = maxf(worst, SimMath.length(fighter.x, fighter.y))
	assert_true(worst > limit * 0.9, "both fighters were actually driven into the boundary")
	assert_true(worst <= limit + StateInvariants.BOUND_SLACK, "step 9 confines bodies after step 7 moves them, so no tick ends outside the arena")
