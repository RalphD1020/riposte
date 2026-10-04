extends TestCase

## SESSION: configs compose the right controllers; sessions record, verify,
## replay, and summarize (PLAN Phases 11, 13).
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "SESSION"


func _finished_cpu_session(seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.medium(), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.hard(), seed_value, 1),
	]
	var session := MatchSession.create(config, controllers)
	while not session.is_finished() and session.state.tick < 40000:
		session.step()
	return session


func test_quick_play_is_human_versus_cpu() -> void:
	var human := HumanController.new()
	var session := MatchComposer.compose(MatchConfig.quick_play(MatchConfig.Difficulty.HARD, 5), human)
	assert_true(session.controllers[0] == human, "slot 0 is the local human")
	var cpu := session.controllers[1] as CpuController
	assert_true(cpu != null, "slot 1 is the CPU")
	assert_eq(cpu.profile.difficulty, MatchConfig.Difficulty.HARD, "chosen difficulty")
	assert_eq(session.config.rules.id, ContentIds.RULES_STANDARD_DUEL, "standard rules")


func test_training_is_a_non_lethal_dummy() -> void:
	var session := MatchComposer.compose(MatchConfig.training(5), HumanController.new())
	assert_true(session.controllers[1] is TrainingDummyController, "training partner")
	assert_eq(session.config.rules.id, ContentIds.RULES_TRAINING, "training rules")
	assert_eq(session.config.rules.combat.damage_for(1.0), 0.0, "contact is physical but non-lethal")


func test_rematch_keeps_the_mode_with_a_fresh_seed() -> void:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.EASY, 5)
	var again := config.rematch(6)
	assert_eq(again.cpu_difficulty, MatchConfig.Difficulty.EASY, "same difficulty")
	assert_eq(again.seed_value, 6, "new seed")
	assert_true(again.rules != config.rules, "fresh rules instance")
	assert_eq(MatchConfig.training(1).rematch(2).mode, MatchConfig.Mode.TRAINING, "training rematches as training")


func test_finished_sessions_record_verifiable_replays() -> void:
	var session := _finished_cpu_session(8)
	assert_true(session.is_finished(), "precondition: match ended")
	assert_ne(session.record.final_hash, "", "final hash recorded")
	assert_eq(ReplayVerifier.verify(session.record, session.config.rules), ReplayVerifier.VERIFIED, "replay verifies")
	assert_eq(session.step().size(), 0, "a finished session is inert")


func test_replay_controllers_reproduce_the_session() -> void:
	var original := _finished_cpu_session(4)
	var controllers: Array[FighterController] = [
		ReplayController.create(original.record, 0),
		ReplayController.create(original.record, 1),
	]
	var replayed := MatchSession.create(original.config.rematch(original.config.seed_value), controllers)
	while not replayed.is_finished() and replayed.state.tick < 40000:
		replayed.step()
	assert_eq(replayed.record.final_hash, original.record.final_hash, "replay controllers reproduce the duel")


func test_summary_reflects_the_match() -> void:
	var session := _finished_cpu_session(2)
	var summary := session.summary(0)
	var expected := MatchSummary.VICTORY if session.state.match_winner == 0 else MatchSummary.DEFEAT
	assert_eq(summary.outcome, expected, "outcome from the match winner")
	var hits := 0
	for event in session.events:
		if event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
			hits += 1
	assert_eq(summary.hits_landed, hits, "hits counted from the log")
	assert_eq(summary.score_self + summary.score_opponent, session.state.scores[0] + session.state.scores[1], "score copied")
	assert_between(summary.average_charge, 0.0, 1.0, "average charge is a charge")


func test_invalid_sessions_fail_closed() -> void:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 1)
	var one: Array[FighterController] = [FighterController.new()]
	assert_true(MatchSession.create(config, one) == null, "two controllers required")
	var broken := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 1)
	broken.rules = DuelRules.new()
	var two: Array[FighterController] = [FighterController.new(), FighterController.new()]
	assert_true(MatchSession.create(broken, two) == null, "invalid rules never start")


func test_training_dummy_answers_only_inside_reach() -> void:
	var rules := StandardDuelRules.training()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var dummy := TrainingDummyController.create(rules)
	var far := false
	for _i in TrainingDummyController.ATTACK_INTERVAL_TICKS + 5:
		far = far or dummy.command_for(runner.state, 1).attack_pressed
	assert_false(far, "no attack while the player is out of reach")
	runner.state.fighter(0).x = runner.state.fighter(1).x - 1.2
	var answered := false
	for _i in TrainingDummyController.ATTACK_INTERVAL_TICKS + 5:
		answered = answered or dummy.command_for(runner.state, 1).attack_pressed
	assert_true(answered, "a quick cut once the player steps in")
