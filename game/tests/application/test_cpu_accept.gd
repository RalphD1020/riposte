extends TestCase

## CPU-ACCEPT: the held-out ladder (`pnpm test:balance:accept`). Does a sharper
## profile actually *win* more, on seeds no profile was ever tuned against?
## An emergent outcome over a fixed corpus, so a failure is a balance shift a
## person reviews — never a reason to move the seeds or the bar. Run once after
## a tuning pass on the audit corpus (`pnpm test:balance:audit`), in its own
## process with a progress line per seed.
##
## Graded only where the effect is large enough for an affordable sample to
## resolve it. Hard-over-Medium is read by the audit report on forty duels,
## not gated: the edge is slim enough that sixteen duels cannot tell it from a
## coin (docs/concepts/cpu.md).
##
## Implements: /spec/invariants.md#cpu-001
## See also: /docs/concepts/cpu.md, /docs/reference/testing.md


func _init() -> void:
	suite_name = "CPU-ACCEPT"


## Both sharper profiles beat the blunt one decisively, in both slots, on
## held-out seeds. The margin is near the 16-duel ceiling, so a regression that
## actually broke a difficulty axis could not hide inside it.
func test_sharper_profiles_beat_the_blunt_one_on_held_out_seeds() -> void:
	var seeds := CpuLadder.ACCEPTANCE_SEEDS
	var duels := seeds.size() * 2
	var medium := CpuLadder.margin(MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.EASY, seeds, "Medium v Easy")
	var hard := CpuLadder.margin(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.EASY, seeds, "Hard v Easy")
	assert_true(medium > 0, "Medium is ahead of Easy over %d unseen duels (margin %d)" % [duels, medium])
	assert_true(hard > 0, "Hard is ahead of Easy over %d unseen duels (margin %d)" % [duels, hard])
	## Not merely positive: decisive. A one- or two-duel edge over Easy would
	## mean a difficulty axis had quietly stopped working. Half the duels is
	## the bar.
	var decisive := seeds.size()
	assert_true(medium >= decisive, "and decisively so (%d of a possible %d)" % [medium, duels])
	assert_true(hard >= decisive, "both of them (%d of a possible %d)" % [hard, duels])
