extends TestCase

## CPU: same commands, same rules; difficulty is decision quality only
## (PLAN Phase 9). Results are deterministic per seed; the seed set is fixed.
##
## Implements: /spec/invariants.md#cpu-001
## See also: /docs/concepts/cpu.md

const MAX_TICKS := 40000


func _init() -> void:
	suite_name = "CPU"


func _session(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty, seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.for_difficulty(first), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.for_difficulty(second), seed_value, 1),
	]
	return MatchSession.create(config, controllers)


func _play(session: MatchSession) -> MatchSession:
	while not session.is_finished() and session.state.tick < MAX_TICKS:
		session.step()
	return session


## Matches won by `stronger` over `weaker` across seeds, playing both slots.
func _wins(stronger: MatchConfig.Difficulty, weaker: MatchConfig.Difficulty, seeds: Array[int]) -> int:
	var wins := 0
	for seed_value in seeds:
		if _play(_session(stronger, weaker, seed_value)).state.match_winner == 0:
			wins += 1
		if _play(_session(weaker, stronger, seed_value)).state.match_winner == 1:
			wins += 1
	return wins


func test_hard_beats_medium() -> void:
	var wins := _wins(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, [1, 2, 3, 4])
	assert_true(wins >= 6, "Hard wins at least 6 of 8 against Medium (%d)" % wins)


func test_medium_beats_easy() -> void:
	var wins := _wins(MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.EASY, [1, 2])
	assert_true(wins >= 3, "Medium wins at least 3 of 4 against Easy (%d)" % wins)


func test_every_match_ends_decisively() -> void:
	var session := _play(_session(MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.MEDIUM, 5))
	assert_true(session.is_finished(), "CPU mirror match finishes")
	var timeouts := 0
	for event in session.events:
		if event.type == DuelEventTypes.ROUND_ENDED and event.text(DuelEventKeys.REASON) == String(MatchPhase.REASON_TIMEOUT):
			timeouts += 1
	assert_true(timeouts <= 1, "no stalemated standoffs (%d timeouts)" % timeouts)


func test_easy_overcharges_and_hard_stays_quick() -> void:
	var easy := _play(_session(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, 3)).summary(0)
	var hard := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, 3)).summary(0)
	assert_true(easy.attacks > 0 and hard.attacks > 0, "precondition: both attacked")
	assert_true(easy.average_charge > hard.average_charge + 0.15, "Easy overcharges (%.2f vs %.2f)" % [easy.average_charge, hard.average_charge])


func test_reading_state_never_changes_it() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 4)
	runner.skip_intro()
	var cpu := CpuController.create(rules, CpuProfile.hard(), 4, 1)
	var before := StateHasher.hash_state(runner.state)
	for _i in 30:
		cpu.command_for(runner.state, 1)
	assert_eq(StateHasher.hash_state(runner.state), before, "the CPU only observes")


func test_perception_lags_by_the_reaction_time() -> void:
	var session := _session(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.HARD, 2)
	while session.state.round_ticks < 120 and not session.is_finished():
		session.step()
	var easy := session.controllers[0] as CpuController
	var hard := session.controllers[1] as CpuController
	assert_true(easy.last_perceived_tick >= 0 and hard.last_perceived_tick >= 0, "precondition: both decided")
	assert_true(session.state.tick - easy.last_perceived_tick >= easy.profile.reaction_ticks, "Easy sees the past")
	assert_true(session.state.tick - hard.last_perceived_tick >= hard.profile.reaction_ticks, "Hard sees the past too")
	assert_true(easy.profile.reaction_ticks > hard.profile.reaction_ticks, "Easy reacts slower")


func test_cpu_play_is_reproducible_and_well_formed() -> void:
	var first := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.EASY, 9))
	var second := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.EASY, 9))
	assert_eq(first.record.final_hash, second.record.final_hash, "same seed, same CPU duel")
	var out_of_range := 0
	for stream: PackedInt32Array in [first.record.commands_0, first.record.commands_1]:
		for index in range(0, stream.size(), PlayerCommand.PACKED_STRIDE):
			if absi(stream[index + 1]) > PlayerCommand.AXIS_MAX or absi(stream[index + 2]) > PlayerCommand.AXIS_MAX:
				out_of_range += 1
	assert_eq(out_of_range, 0, "every CPU command is a legal PlayerCommand")
