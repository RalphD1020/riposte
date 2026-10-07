extends TestCase

## TUTORIAL: each instruction completes from what the player actually did
## (UX §57).
##
## See also: /docs/concepts/ux.md


func _init() -> void:
	suite_name = "TUTORIAL"


func _event(type: StringName, actor: int, charge: float = 0.0) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = [DuelEvent.create(type, 0, actor, DuelEvent.NONE, {DuelEventKeys.CHARGE: charge})]
	return events


func _active_state() -> MatchState:
	var state := DuelFixture.state(DuelFixture.rules())
	state.phase = MatchPhase.Id.ROUND_ACTIVE
	return state


func test_moving_a_meter_completes_move() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	var none: Array[DuelEvent] = []
	assert_false(tracker.observe(state, none), "standing still teaches nothing")
	state.fighter(0).x += 0.6
	assert_false(tracker.observe(state, none), "0.6 m is not enough")
	state.fighter(0).y += 0.6
	assert_true(tracker.observe(state, none), "1.2 m completes the step")
	assert_eq(tracker.step, TutorialTracker.Step.QUICK_CUT, "next: quick cut")


func test_attack_steps_follow_the_real_inputs() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.QUICK_CUT
	assert_false(tracker.observe(state, _event(DuelEventTypes.ATTACK_RELEASED, 1)), "the opponent's cut does not count")
	assert_false(tracker.observe(state, _event(DuelEventTypes.ATTACK_RELEASED, 0, 0.4)), "a charged cut is not a quick cut")
	assert_true(tracker.observe(state, _event(DuelEventTypes.ATTACK_RELEASED, 0, 0.0)), "a 0% cut completes QUICK CUT")
	var none: Array[DuelEvent] = []
	state.fighter(0).weapon.phase = CombatPhase.Id.CHARGING
	state.fighter(0).weapon.charge = 0.3
	assert_false(tracker.observe(state, none), "a shallow charge is not enough")
	state.fighter(0).weapon.charge = 0.6
	assert_true(tracker.observe(state, none), "half charge completes CHARGE")
	assert_true(tracker.observe(state, _event(DuelEventTypes.ATTACK_RELEASED, 0, 0.6)), "releasing it completes RELEASE")
	assert_eq(tracker.step, TutorialTracker.Step.BLADES, "next: blades")


func test_blade_contact_opens_the_physical_lessons() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.BLADES
	assert_true(tracker.observe(state, _event(DuelEventTypes.BLADE_CONTACT, -1)), "blades met")
	assert_eq(tracker.step, TutorialTracker.Step.SWEET_SPOT, "the five verbs done, the physics next")
	assert_false(tracker.observe(state, _event(DuelEventTypes.BLADE_CONTACT, -1)), "a second clash is not the sweet-spot lesson")
	tracker.step = TutorialTracker.Step.COMPLETE
	assert_false(tracker.observe(state, _event(DuelEventTypes.BLADE_CONTACT, -1)), "complete stays complete")


func test_nothing_counts_outside_an_active_round() -> void:
	var state := DuelFixture.state(DuelFixture.rules())
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.QUICK_CUT
	assert_eq(state.phase, MatchPhase.Id.ROUND_INTRO, "precondition: intro")
	assert_false(tracker.observe(state, _event(DuelEventTypes.ATTACK_RELEASED, 0, 0.0)), "intro input is ignored")


func test_training_session_drives_the_first_steps() -> void:
	var human := HumanController.new()
	var session := MatchComposer.compose(MatchConfig.training(1), human)
	var tracker := TutorialTracker.create(0)
	while session.state.phase != MatchPhase.Id.ROUND_ACTIVE:
		tracker.observe(session.state, session.step())
	human.input.set_key_axis(1.0, 0.0)
	for _i in 30:
		tracker.observe(session.state, session.step())
	human.input.set_key_axis(0.0, 0.0)
	assert_eq(tracker.step, TutorialTracker.Step.QUICK_CUT, "walking completed MOVE")
	human.input.attack_down(HumanInputState.SOURCE_KEY)
	human.input.attack_up(HumanInputState.SOURCE_KEY)
	tracker.observe(session.state, session.step())
	assert_eq(tracker.step, TutorialTracker.Step.CHARGE, "a real tap completed QUICK CUT")


## -- PHYSICAL LESSONS --


func _hit(blade_fraction: float, closing: float) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = [
		DuelEvent.create(
			DuelEventTypes.BODY_HIT,
			0,
			0,
			1,
			{
				DuelEventKeys.BLADE_FRACTION: blade_fraction,
				DuelEventKeys.CLOSING_SPEED: closing,
			}
		)
	]
	return events


func test_the_sweet_spot_lesson_is_passed_by_where_the_blade_met() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.SWEET_SPOT
	assert_false(tracker.observe(state, _hit(0.2, 6.0)), "a hit near the hilt teaches the wrong thing")
	assert_false(tracker.observe(state, _hit(0.99, 6.0)), "and so does the very end of the blade")
	assert_true(tracker.observe(state, _hit(0.7, 1.0)), "the percussion band passes, however gentle the hit")
	assert_eq(tracker.step, TutorialTracker.Step.MOMENTUM, "next: momentum")


func test_the_sweet_spot_lesson_ignores_the_opponents_hits() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.SWEET_SPOT
	var theirs: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BODY_HIT, 0, 1, 0, {DuelEventKeys.BLADE_FRACTION: 0.7, DuelEventKeys.CLOSING_SPEED: 6.0})
	]
	assert_false(tracker.observe(state, theirs), "being hit well is not a pass")


func test_the_momentum_lesson_wants_the_contrast_not_a_number() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.MOMENTUM
	assert_false(tracker.observe(state, _hit(0.7, 5.0)), "one hit is not a comparison")
	assert_false(tracker.observe(state, _hit(0.7, 5.4)), "two near-identical hits felt the same")
	assert_true(tracker.observe(state, _hit(0.7, 5.0 * TutorialTracker.MOMENTUM_CONTRAST)), "a clearly harder hit completes the pair")
	assert_true(tracker.is_complete(), "training complete")


func test_the_partner_winds_up_and_swings_on_its_own_cadence() -> void:
	var rules := StandardDuelRules.training()
	var state := DuelFixture.state(rules)
	state.phase = MatchPhase.Id.ROUND_ACTIVE
	var dummy := TrainingDummyController.create(rules)
	dummy.beat = TrainingDummyController.Beat.BIG_SWING
	var presses := 0
	var releases := 0
	var moved := false
	for _i in TrainingDummyController.SWING_PERIOD_TICKS:
		var command := dummy.command_for(state, 1)
		if command.attack_pressed:
			presses += 1
		if command.attack_released:
			releases += 1
		if command.move_x != 0 or command.move_y != 0:
			moved = true
	assert_eq(presses, 1, "one wind-back per period, whether or not anyone is in reach")
	assert_eq(releases, 1, "and one release")
	assert_false(moved, "a still target: the drill is about your spacing, not theirs")


func test_the_partner_paces_in_and_out_without_attacking() -> void:
	var rules := StandardDuelRules.training()
	var state := DuelFixture.state(rules)
	state.phase = MatchPhase.Id.ROUND_ACTIVE
	var dummy := TrainingDummyController.create(rules)
	dummy.beat = TrainingDummyController.Beat.PACE
	var closing := PackedFloat64Array()
	for _i in TrainingDummyController.PACE_TICKS * 2:
		var command := dummy.command_for(state, 1)
		assert_false(command.attack_pressed or command.attack_released, "the momentum drill never swings back")
		closing.append(command.axis_y())
	assert_eq(closing[0], 1.0, "walks in first")
	assert_eq(closing[TrainingDummyController.PACE_TICKS - 1], 1.0, "and keeps walking in long enough to be read")
	assert_eq(closing[TrainingDummyController.PACE_TICKS], -1.0, "then walks out")


func test_the_partner_stands_down_between_rounds() -> void:
	var rules := StandardDuelRules.training()
	var state := DuelFixture.state(rules)
	var dummy := TrainingDummyController.create(rules)
	dummy.beat = TrainingDummyController.Beat.PACE
	assert_eq(state.phase, MatchPhase.Id.ROUND_INTRO, "precondition: intro")
	assert_true(dummy.command_for(state, 1).is_idle(), "no drill runs before the round does")