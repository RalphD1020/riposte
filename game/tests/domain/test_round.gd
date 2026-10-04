extends TestCase

## ROUND: round and match lifecycle (PLAN Phase 8): intro, kill, timeout,
## draws, best of five, deterministic resets.
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "ROUND"


func _runner(rules: DuelRules = null) -> SimRunner:
	return SimRunner.create(rules if rules != null else DuelFixture.rules(), 7)


## Kill `loser` (or both with -1) and wait out the result period.
func _decide_round(runner: SimRunner, loser: int) -> void:
	runner.skip_intro()
	for slot in 2:
		if loser == -1 or slot == loser:
			runner.state.fighter(slot).health = 0.0
	runner.idle(1 + runner.simulation.rules.result_ticks)


func test_intro_lasts_its_ticks_then_the_round_starts() -> void:
	var runner := _runner()
	runner.idle(runner.simulation.rules.intro_ticks - 1)
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_INTRO, "still in the intro")
	assert_eq(runner.events.size(), 0, "nothing happens during the intro")
	runner.idle(1)
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_ACTIVE, "round begins")
	assert_eq(runner.first(DuelEventTypes.ROUND_STARTED).number(DuelEventKeys.ROUND), 1.0, "round 1 started")


func test_commands_during_the_intro_are_ignored() -> void:
	var runner := _runner()
	var x := runner.state.fighter(0).x
	for i in 10:
		runner.simulation.step(runner.state, PlayerCommand.create(i, 1.0, 0.0, true, false), PlayerCommand.idle(i))
	assert_eq(runner.state.fighter(0).x, x, "no movement during the intro")
	assert_eq(runner.state.fighter(0).weapon.phase, CombatPhase.Id.NEUTRAL, "no attack during the intro")


func test_a_kill_ends_the_round_and_scores() -> void:
	var runner := _runner()
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	b.x = a.x + 1.1
	b.health = 1.0
	runner.simulation.step(runner.state, PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	runner.idle(40)
	assert_eq(runner.count(DuelEventTypes.BODY_HIT), 1, "the tap landed")
	assert_eq(runner.count(DuelEventTypes.FIGHTER_KILLED), 1, "and killed")
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "fighter 0 won the round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_KILL), "by kill")
	assert_eq(runner.state.scores, PackedInt32Array([1, 0]), "score 1–0")


func test_timeout_awards_the_healthier_fighter() -> void:
	var rules := DuelFixture.rules()
	rules.round_time_limit_ticks = 5
	var runner := _runner(rules)
	runner.skip_intro()
	runner.state.fighter(1).health = 90.0
	runner.idle(5)
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_true(ended != null, "time limit ends the round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_TIMEOUT), "by timeout")
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "healthier fighter wins")


func test_double_kill_is_a_drawn_round() -> void:
	var runner := _runner()
	_decide_round(runner, -1)
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), MatchPhase.DRAW, "drawn round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_DOUBLE_KILL), "double kill")
	assert_eq(runner.state.scores, PackedInt32Array([0, 0]), "nobody scores")


func test_best_of_five_ends_at_three() -> void:
	var runner := _runner()
	for _round in 3:
		_decide_round(runner, 1)
	assert_true(runner.state.is_finished(), "match over")
	assert_eq(runner.state.match_winner, 0, "fighter 0 wins the match")
	assert_eq(runner.state.scores, PackedInt32Array([3, 0]), "3–0")
	assert_eq(runner.count(DuelEventTypes.MATCH_ENDED), 1, "one match end")


func test_round_limit_ends_a_tied_match_as_a_draw() -> void:
	var rules := DuelFixture.rules()
	rules.rounds_to_win = 2
	rules.max_rounds = 3
	var runner := _runner(rules)
	for _round in 3:
		_decide_round(runner, -1)
	assert_true(runner.state.is_finished(), "round limit ends the match")
	assert_eq(runner.state.match_winner, MatchPhase.DRAW, "tied match is a draw")
	assert_eq(runner.first(DuelEventTypes.MATCH_ENDED).text(DuelEventKeys.REASON), String(MatchPhase.REASON_ROUND_LIMIT), "round limit reason")


func test_next_round_resets_canonical_state() -> void:
	var runner := _runner()
	runner.skip_intro()
	var a := runner.state.fighter(0)
	a.x = 1.0
	a.weapon.angle = 1.0
	_decide_round(runner, 1)
	assert_eq(runner.state.round_number, 2, "second round")
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_INTRO, "back to the intro")
	assert_eq(a.x, -runner.simulation.rules.spawn_offset, "canonical position")
	assert_eq(a.health, runner.simulation.rules.fighter.max_health, "full health")
	assert_eq(a.weapon.angle, -runner.simulation.rules.weapon.guard_angle, "canonical guard")


func test_a_finished_match_is_inert() -> void:
	var runner := _runner()
	for _round in 3:
		_decide_round(runner, 0)
	var tick := runner.state.tick
	var after := runner.simulation.step(runner.state, PlayerCommand.idle(tick), PlayerCommand.idle(tick))
	assert_eq(after.size(), 0, "no events after the end")
	assert_eq(runner.state.tick, tick, "the clock stops")


func test_invalid_rules_fail_closed() -> void:
	assert_true(DuelSimulation.create(DuelRules.new()) == null, "neutral rules cannot start a duel")
	assert_true(DuelSimulation.create(null) == null, "missing rules cannot start a duel")
