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


func test_blade_contact_completes_the_tutorial() -> void:
	var state := _active_state()
	var tracker := TutorialTracker.create(0)
	tracker.step = TutorialTracker.Step.BLADES
	assert_true(tracker.observe(state, _event(DuelEventTypes.BLADE_CONTACT, -1)), "blades met")
	assert_true(tracker.is_complete(), "tutorial complete")
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
