extends TestCase

## CPU-BALANCE: the balance smoke tier (`pnpm test:balance`, run by `verify`).
## Emergent outcomes over whole CPU duels, on non-held-out seeds only: a
## failure here is a balance shift a person reviews, and it never grades the
## ladder — the held-out ladder is CPU-ACCEPT (`pnpm test:balance:accept`) and
## the tuning corpus the audit report (`pnpm test:balance:audit`). Kept apart
## from the CPU suite's laws so CI says which kind of claim broke. Every duel
## prints a progress line.
##
## Results are deterministic per seed; the corpora are fixed and are never
## regenerated or extended to make a failing gate pass.
##
## Implements: /spec/invariants.md#cpu-001
## See also: /docs/concepts/cpu.md, /docs/reference/testing.md


func _init() -> void:
	suite_name = "CPU-BALANCE"


## Over whole duels Easy should hold (CHARGE_STARTED per release) more often
## than Hard. An emergent mix of where the fight goes and what each profile
## decides there, so it moves with geometry and contact rules; the law itself
## — same situation, lighter commitment — is CPU's
## `test_easy_overcharges_and_hard_stays_quick`.
func test_easy_holds_more_often_than_hard_over_whole_duels() -> void:
	var ratios := PackedFloat64Array([0.0, 0.0])
	var samples := 0
	for seed_value: int in [3, 7, 11]:
		var easy := _played(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, seed_value)
		var hard := _played(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, seed_value)
		if easy.summary(0).attacks > 0 and hard.summary(0).attacks > 0:
			ratios[0] += _hold_ratio(easy, 0)
			ratios[1] += _hold_ratio(hard, 0)
			samples += 1
	assert_true(samples >= 2, "precondition: at least 2 seeds produced attacks")
	assert_true(ratios[0] > ratios[1], "Easy holds more often than Hard (%.2f vs %.2f)" % [ratios[0] / float(maxi(samples, 1)), ratios[1] / float(maxi(samples, 1))])


## A CPU mirror match is decided by blows, not by the clock. Emergent: it
## depends on how much damage gets past the guards — guards that hold make the
## same profiles fence longer.
func test_every_match_ends_decisively() -> void:
	var duel := _played(MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.MEDIUM, 5)
	assert_true(duel.is_finished(), "CPU mirror match finishes")
	var timeouts := 0
	for event in duel.events:
		if event.type == DuelEventTypes.ROUND_ENDED and event.text(DuelEventKeys.REASON) == String(MatchPhase.REASON_TIMEOUT):
			timeouts += 1
	assert_true(timeouts <= 1, "no stalemated standoffs (%d timeouts)" % timeouts)


## The split is only real if the corpora are disjoint: a seed in two of them
## would quietly let tuning reach the held-out ladder.
func test_the_three_corpora_are_disjoint() -> void:
	assert_eq(CpuLadder.CALIBRATION_SEEDS.size(), CpuLadder.ACCEPTANCE_SEEDS.size(), "fixture: equal-sized smoke and acceptance corpora, so margins are comparable")
	assert_true(CpuLadder.AUDIT_SEEDS.size() >= 40, "fixture: the tuning corpus is forty seeds or more (%d)" % CpuLadder.AUDIT_SEEDS.size())
	for seed_value in CpuLadder.ACCEPTANCE_SEEDS:
		assert_false(CpuLadder.CALIBRATION_SEEDS.has(seed_value), "acceptance seed %d is not a calibration seed" % seed_value)
		assert_false(CpuLadder.AUDIT_SEEDS.has(seed_value), "acceptance seed %d is not a tuning seed" % seed_value)
	for seed_value in CpuLadder.CALIBRATION_SEEDS:
		assert_false(CpuLadder.AUDIT_SEEDS.has(seed_value), "calibration seed %d is not a tuning seed" % seed_value)


## One duel to its end, with its progress line.
func _played(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty, seed_value: int) -> MatchSession:
	var started := Time.get_ticks_msec()
	var duel := CpuLadder.play(CpuLadder.session(first, second, seed_value))
	print("  · CPU-BALANCE %s v %s seed %d: %d ticks (%.1f s)" % [MatchConfig.difficulty_label(first), MatchConfig.difficulty_label(second), seed_value, duel.state.tick, float(Time.get_ticks_msec() - started) / 1000.0])
	return duel


func _hold_ratio(duel: MatchSession, slot: int) -> float:
	var charges := 0
	var releases := 0
	for event in duel.events:
		if event.actor != slot:
			continue
		if event.type == DuelEventTypes.CHARGE_STARTED:
			charges += 1
		elif event.type == DuelEventTypes.ATTACK_RELEASED:
			releases += 1
	return 0.0 if releases == 0 else float(charges) / float(releases)
