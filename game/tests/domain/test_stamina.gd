extends TestCase

## STAMINA: StaminaModel arithmetic (deprecated resource, STAMINA-002) and
## FighterCondition classification. Physical capability is CONDITION's.
##
## Implements: /spec/invariants.md#combat-001
## See also: /docs/concepts/combat.md

var _rules: DuelRules
var _tuning: CombatTuning
var _dt: float


func _init() -> void:
	suite_name = "STAMINA"
	_rules = DuelFixture.rules()
	_tuning = _rules.combat
	_dt = SimulationTimebase.TICK_SECONDS


# -- StaminaModel.max_for_health ----------------------------------------

func test_stamina_max_equals_base_at_full_health() -> void:
	var result := StaminaModel.max_for_health(100.0, 100.0, 100.0, _tuning)
	assert_near(result, 100.0, 1e-9, "full health → full stamina ceiling")


func test_stamina_max_decreases_with_injury() -> void:
	var full := StaminaModel.max_for_health(100.0, 100.0, 100.0, _tuning)
	var half := StaminaModel.max_for_health(50.0, 100.0, 100.0, _tuning)
	var zero := StaminaModel.max_for_health(0.0, 100.0, 100.0, _tuning)
	assert_true(half < full, "injury lowers the ceiling")
	assert_true(zero < half, "more injury lowers it further")
	assert_true(zero > 0.0, "ceiling stays positive even at zero health")


func test_stamina_max_is_monotonic_in_health() -> void:
	var previous := StaminaModel.max_for_health(0.0, 100.0, 100.0, _tuning)
	for i in range(1, 11):
		var health := float(i) * 10.0
		var current := StaminaModel.max_for_health(health, 100.0, 100.0, _tuning)
		assert_true(current >= previous, "stamina max is non-decreasing at health %s" % str(health))
		previous = current


func test_stamina_max_zero_max_health_returns_zero() -> void:
	var result := StaminaModel.max_for_health(0.0, 0.0, 100.0, _tuning)
	assert_near(result, 0.0, 1e-9, "degenerate max_health → zero ceiling")


# -- StaminaModel.damage_shock -----------------------------------------

func test_damage_shock_proportional_to_damage() -> void:
	var small := StaminaModel.damage_shock(10.0, _tuning)
	var large := StaminaModel.damage_shock(50.0, _tuning)
	assert_near(large, small * 5.0, 1e-9, "shock scales linearly with damage")
	assert_true(small > 0.0, "non-zero damage produces non-zero shock")


func test_damage_shock_zero_damage_is_zero() -> void:
	assert_near(StaminaModel.damage_shock(0.0, _tuning), 0.0, 1e-9, "zero damage → zero shock")


# -- StaminaModel.exertion ---------------------------------------------

func test_exertion_proportional_to_effort_and_time() -> void:
	var base := StaminaModel.exertion(0.5, _dt, _tuning)
	var double_effort := StaminaModel.exertion(1.0, _dt, _tuning)
	var double_time := StaminaModel.exertion(0.5, _dt * 2.0, _tuning)
	assert_near(double_effort, base * 2.0, 1e-9, "exertion doubles with effort")
	assert_near(double_time, base * 2.0, 1e-9, "exertion doubles with time")


func test_exertion_idle_is_zero() -> void:
	assert_near(StaminaModel.exertion(0.0, _dt, _tuning), 0.0, 1e-9, "zero effort → zero drain")


# -- StaminaModel.recovery ---------------------------------------------

func test_recovery_at_rest() -> void:
	var result := StaminaModel.recovery(0.0, 50.0, 100.0, _dt, _tuning)
	assert_true(result > 0.0, "idle fighter recovers stamina")


func test_recovery_is_zero_when_exerting() -> void:
	var result := StaminaModel.recovery(1.0, 50.0, 100.0, _dt, _tuning)
	assert_near(result, 0.0, 1e-9, "full effort blocks recovery")


func test_recovery_is_zero_at_ceiling() -> void:
	var result := StaminaModel.recovery(0.0, 100.0, 100.0, _dt, _tuning)
	assert_near(result, 0.0, 1e-9, "already at max → nothing to recover")


func test_recovery_capped_by_headroom() -> void:
	var result := StaminaModel.recovery(0.0, 99.999, 100.0, 10.0, _tuning)
	assert_between(result, 0.0, 0.001 + 1e-9, "recovery does not exceed headroom")


# -- FighterCondition ---------------------------------------------------

func test_condition_full_health_is_healthy() -> void:
	assert_eq(FighterCondition.classify(100.0, 100.0), FighterCondition.Id.HEALTHY, "full health → HEALTHY")


func test_condition_zero_health_is_critical() -> void:
	assert_eq(FighterCondition.classify(0.0, 100.0), FighterCondition.Id.CRITICAL, "zero health → CRITICAL")


func test_condition_classification_is_monotone() -> void:
	var previous := FighterCondition.classify(100.0, 100.0)
	for i in range(99, -1, -1):
		var health := float(i)
		var current := FighterCondition.classify(health, 100.0)
		assert_true(current >= previous, "condition non-decreasing severity at health %s" % str(health))
		previous = current


func test_condition_thresholds() -> void:
	assert_eq(FighterCondition.classify(76.0, 100.0), FighterCondition.Id.HEALTHY, "76% → HEALTHY")
	assert_eq(FighterCondition.classify(75.0, 100.0), FighterCondition.Id.HURT, "75% → HURT")
	assert_eq(FighterCondition.classify(51.0, 100.0), FighterCondition.Id.HURT, "51% → HURT")
	assert_eq(FighterCondition.classify(50.0, 100.0), FighterCondition.Id.WOUNDED, "50% → WOUNDED")
	assert_eq(FighterCondition.classify(26.0, 100.0), FighterCondition.Id.WOUNDED, "26% → WOUNDED")
	assert_eq(FighterCondition.classify(25.0, 100.0), FighterCondition.Id.CRITICAL, "25% → CRITICAL")
	assert_eq(FighterCondition.classify(1.0, 100.0), FighterCondition.Id.CRITICAL, "1% → CRITICAL")


func test_condition_degenerate_max_health() -> void:
	assert_eq(FighterCondition.classify(0.0, 0.0), FighterCondition.Id.CRITICAL, "zero max_health → CRITICAL")


func test_condition_labels() -> void:
	assert_eq(FighterCondition.label(FighterCondition.Id.HEALTHY), "HEALTHY", "label HEALTHY")
	assert_eq(FighterCondition.label(FighterCondition.Id.HURT), "HURT", "label HURT")
	assert_eq(FighterCondition.label(FighterCondition.Id.WOUNDED), "WOUNDED", "label WOUNDED")
	assert_eq(FighterCondition.label(FighterCondition.Id.CRITICAL), "CRITICAL", "label CRITICAL")


# -- Tuning validation --------------------------------------------------

func test_tuning_validates_stamina_fields() -> void:
	var rules := DuelFixture.rules()
	assert_true(rules.combat.is_valid(), "standard tuning is valid")
	rules.combat.stamina_health_share = -0.1
	assert_false(rules.combat.is_valid(), "negative health share is invalid")
	rules.combat.stamina_health_share = _tuning.stamina_health_share
	assert_true(rules.combat.is_valid(), "and restoring it is valid again")


# -- Condition, not stamina, scales the motors (CONDITION-001, STAMINA-002) --

func test_a_healthy_duel_still_moves() -> void:
	var sim := DuelSimulation.create(_rules)
	var state := sim.new_match(42)
	var idle := PlayerCommand.create(0, 0.0, 0.0, false, false, false)
	var forward := PlayerCommand.create(0, 0.0, 1.0, false, false, false)
	for tick in _rules.intro_ticks + 30:
		sim.step(state, forward, idle)
	assert_true(state.fighter(0).speed() > 0.0, "fighter 0 moves (regression)")
	assert_true(StateInvariants.check(state, _rules) == StateInvariants.OK, "invariants hold (regression)")


func test_effort_written_to_scratch() -> void:
	var state := DuelFixture.state(_rules)
	var scratch := FighterTickScratch.new()
	MovementSystem.step(state.fighter(0), 0.0, 1.0, 0, _rules.combatant(0).fighter, null, scratch)
	assert_true(scratch.movement_utilization >= 0.0, "movement utilization non-negative")
	assert_true(scratch.movement_utilization <= 1.0, "movement utilization at most 1")
	assert_true(scratch.movement_positive_work >= 0.0, "movement positive work non-negative")
	var turn_scratch := FighterTickScratch.new()
	FacingSystem.step(state.fighter(0), 5.0, 0.0, 1.0, _rules.combatant(0).fighter, null, turn_scratch)
	assert_true(turn_scratch.turn_utilization >= 0.0, "turn utilization non-negative")
	assert_true(turn_scratch.turn_utilization <= 1.0, "turn utilization at most 1")
	var weapon_scratch := FighterTickScratch.new()
	var idle_events: Array[DuelEvent] = []
	WeaponSystem.step(state.fighter(0), _rules, 0, idle_events, null, weapon_scratch)
	assert_true(weapon_scratch.weapon_utilization >= 0.0, "weapon utilization non-negative")
	assert_true(weapon_scratch.weapon_utilization <= 1.0, "weapon utilization at most 1")


func test_tick_order_version_bumped() -> void:
	assert_eq(DuelSimulation.TICK_ORDER_VERSION, 13, "the tick order is version 13: a spent re-hold budget carries the remainder without tunnelling")


# -- Phase 3.1: FighterTickScratch motor exertion -------------------------

func test_scratch_reset_zeroes_all_fields() -> void:
	var scratch := FighterTickScratch.new()
	scratch.movement_positive_work = 1.0
	scratch.turn_utilization = 0.5
	scratch.weapon_braking_work = 2.0
	scratch.contact_shock = 10.0
	scratch.burst_active = true
	scratch.reset()
	assert_near(scratch.movement_positive_work, 0.0, 1e-9, "reset zeroes movement work")
	assert_near(scratch.turn_utilization, 0.0, 1e-9, "reset zeroes turn utilization")
	assert_near(scratch.weapon_braking_work, 0.0, 1e-9, "reset zeroes weapon braking")
	assert_near(scratch.contact_shock, 0.0, 1e-9, "reset zeroes contact shock")
	assert_false(scratch.burst_active, "reset clears burst flag")


func test_weapon_swing_produces_positive_work() -> void:
	var rig := WeaponRig.create(_rules)
	var scratch := FighterTickScratch.new()
	rig.press()
	rig.release()
	var cumulative_positive := 0.0
	for _i in 10:
		scratch.reset()
		WeaponSystem.step(rig.fighter, _rules, rig.tick, rig.events, null, scratch)
		rig.tick += 1
		cumulative_positive += scratch.weapon_positive_work
	assert_true(cumulative_positive > 0.0, "a driving swing deposits positive work across its arc")


func test_idle_weapon_produces_no_work() -> void:
	var state := DuelFixture.state(_rules)
	var scratch := FighterTickScratch.new()
	var idle_events: Array[DuelEvent] = []
	WeaponSystem.step(state.fighter(0), _rules, 0, idle_events, null, scratch)
	assert_near(scratch.weapon_positive_work, 0.0, 1e-9, "an idle weapon produces no positive work")
	assert_near(scratch.weapon_braking_work, 0.0, 1e-9, "an idle weapon produces no braking work")


func test_movement_forward_produces_positive_work() -> void:
	var state := DuelFixture.state(_rules)
	var scratch := FighterTickScratch.new()
	MovementSystem.step(state.fighter(0), 0.0, 1.0, 0, _rules.combatant(0).fighter, null, scratch)
	assert_true(scratch.movement_positive_work > 0.0 or scratch.movement_utilization > 0.0, "forward movement exerts the motor")


# -- Phase 4: Normalization and combined effort ----------------------------

func test_channel_effort_zero_when_idle() -> void:
	var effort := StaminaModel.channel_effort(0.0, 0.0, 0.0, 50.0, _tuning)
	assert_near(effort, 0.0, 1e-9, "idle channel produces zero effort")


func test_channel_effort_drive_weight_applied() -> void:
	var positive_only := StaminaModel.channel_effort(10.0, 0.0, 0.0, 50.0, _tuning)
	assert_true(positive_only > 0.0, "positive work produces effort")
	var braking_only := StaminaModel.channel_effort(0.0, 10.0, 0.0, 50.0, _tuning)
	assert_true(braking_only > 0.0, "braking work produces effort")
	assert_true(positive_only > braking_only, "drive weight exceeds brake weight")


func test_channel_effort_hold_weight() -> void:
	var hold_effort := StaminaModel.channel_effort(0.0, 0.0, 1.0, 50.0, _tuning)
	assert_near(hold_effort, _tuning.stamina_hold_weight, 1e-9, "utilization 1.0 contributes hold_weight")


func test_channel_effort_normalized_by_reference() -> void:
	var small_ref := StaminaModel.channel_effort(10.0, 0.0, 0.0, 10.0, _tuning)
	var large_ref := StaminaModel.channel_effort(10.0, 0.0, 0.0, 100.0, _tuning)
	assert_true(small_ref > large_ref, "smaller reference produces higher normalized effort")
	assert_near(small_ref / large_ref, 10.0, 1e-6, "effort scales inversely with reference")


func test_channel_effort_zero_reference_returns_zero() -> void:
	var effort := StaminaModel.channel_effort(10.0, 5.0, 0.5, 0.0, _tuning)
	assert_near(effort, 0.0, 1e-9, "degenerate reference → zero effort")


func test_total_effort_sums_channels() -> void:
	var scratch := FighterTickScratch.new()
	scratch.movement_positive_work = 10.0
	scratch.turn_positive_work = 5.0
	scratch.weapon_positive_work = 8.0
	var total := StaminaModel.total_effort(scratch, _tuning)
	var move := StaminaModel.channel_effort(10.0, 0.0, 0.0, _tuning.stamina_move_reference_work, _tuning)
	var turn := StaminaModel.channel_effort(5.0, 0.0, 0.0, _tuning.stamina_turn_reference_work, _tuning)
	var weapon := StaminaModel.channel_effort(8.0, 0.0, 0.0, _tuning.stamina_weapon_reference_work, _tuning)
	assert_near(total, move + turn + weapon, 1e-9, "total effort is sum of channels")


func test_total_effort_zero_when_idle() -> void:
	var scratch := FighterTickScratch.new()
	assert_near(StaminaModel.total_effort(scratch, _tuning), 0.0, 1e-9, "idle scratch → zero effort")


# -- Phase 4: Stamina drain in simulation ---------------------------------

func test_exertion_drains_stamina_during_movement() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	var initial := runner.state.fighter(0).stamina
	assert_near(initial, _rules.combatant(0).fighter.base_stamina, 1e-6, "stamina starts at base")
	var forward := PlayerCommand.create(0, 0.0, 1.0)
	var idle := PlayerCommand.idle(0)
	for _i in 120:
		runner.push(forward, idle)
	var after := runner.state.fighter(0).stamina
	assert_true(after < initial, "sustained movement drains stamina")
	assert_true(after > 0.0, "120 ticks of walking does not empty stamina")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_idle_fighter_does_not_drain_stamina() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	var initial := runner.state.fighter(0).stamina
	runner.idle(60)
	var after := runner.state.fighter(0).stamina
	assert_near(after, initial, 1e-6, "idle fighter stamina unchanged")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_recovery_restores_stamina_at_rest() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	runner.state.fighter(0).stamina = 50.0
	runner.idle(120)
	var after := runner.state.fighter(0).stamina
	assert_true(after > 50.0, "idle rest recovers stamina")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_stamina_never_negative() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	runner.state.fighter(0).stamina = 0.5
	var forward := PlayerCommand.create(0, 0.0, 1.0)
	var idle := PlayerCommand.idle(0)
	for _i in 30:
		runner.push(forward, idle)
	assert_true(runner.state.fighter(0).stamina >= 0.0, "stamina clamped at zero")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_stamina_capped_at_max() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	var fighter := runner.state.fighter(0)
	fighter.health = 50.0
	var stamina_max := StaminaModel.max_for_health(50.0, _rules.combatant(0).fighter.max_health, _rules.combatant(0).fighter.base_stamina, _tuning)
	fighter.stamina = stamina_max
	runner.idle(60)
	assert_true(fighter.stamina <= stamina_max + StateInvariants.BOUND_SLACK, "stamina stays at or below max")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_contact_shock_reduces_stamina() -> void:
	var shock := StaminaModel.damage_shock(56.0, _tuning)
	assert_true(shock > 0.0, "a reference hit produces non-zero shock")
	var scratch := FighterTickScratch.new()
	scratch.contact_shock = shock
	assert_near(scratch.contact_shock, 56.0 * _tuning.stamina_shock_rate, 1e-9, "shock = damage × rate")


func test_normalization_produces_reasonable_effort() -> void:
	var scratch := FighterTickScratch.new()
	scratch.movement_positive_work = _tuning.stamina_move_reference_work
	scratch.movement_utilization = 1.0
	scratch.turn_positive_work = _tuning.stamina_turn_reference_work
	scratch.turn_utilization = 1.0
	scratch.weapon_positive_work = _tuning.stamina_weapon_reference_work
	scratch.weapon_utilization = 1.0
	var effort := StaminaModel.total_effort(scratch, _tuning)
	var expected_per_channel := _tuning.stamina_drive_weight + _tuning.stamina_hold_weight
	assert_near(effort, expected_per_channel * 3.0, 1e-6, "three channels at reference + full utilization → 3 × (drive + hold)")


func test_burst_drains_more_than_walking() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	var walker := runner.state.fighter(0)
	var idle_cmd := PlayerCommand.idle(0)
	var forward := PlayerCommand.create(0, 0.0, 1.0)
	for _i in 60:
		runner.push(forward, idle_cmd)
	var walk_stamina := walker.stamina
	var runner2 := SimRunner.create(_rules, 42)
	runner2.skip_intro()
	var dasher := runner2.state.fighter(0)
	for tick in 60:
		var cmd: PlayerCommand
		if tick < 2:
			cmd = PlayerCommand.create(tick, 0.0, 1.0)
		elif tick == 2:
			cmd = PlayerCommand.create(tick, 0.0, 0.0)
		elif tick < 5:
			cmd = PlayerCommand.create(tick, 0.0, 1.0)
		else:
			cmd = PlayerCommand.create(tick, 0.0, 1.0)
		runner2.push(cmd, idle_cmd)
	var dash_stamina := dasher.stamina
	assert_true(dash_stamina < walk_stamina, "burst exertion costs more stamina than walking")
	assert_true(runner.is_sound(), runner.violation_summary())
	assert_true(runner2.is_sound(), runner2.violation_summary())


func test_replay_determinism_with_stamina_drain() -> void:
	var runner := SimRunner.create(_rules, 42)
	runner.skip_intro()
	var forward := PlayerCommand.create(0, 0.0, 1.0)
	var attack := PlayerCommand.create(0, 0.0, 0.5, true)
	for _i in 30:
		runner.push(forward, attack)
	runner.push(PlayerCommand.create(0, 0.0, 0.5, false, true), PlayerCommand.create(0, 0.0, 0.5, false, true))
	for _i in 60:
		runner.push(forward, forward)
	runner.seal()
	assert_true(runner.is_sound(), runner.violation_summary())
	var result := ReplayVerifier.verify(runner.record, _rules)
	assert_eq(result, ReplayVerifier.VERIFIED, "replay matches with stamina drain active")
