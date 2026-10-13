class_name CpuLadder
extends RefCounted

## The CPU ladder's corpora and duel runner, shared by the balance smoke
## (CPU-BALANCE), the held-out acceptance (CPU-ACCEPT) and the audit report
## (`tools/balance_report.gd`), so all three play a duel the same way.
##
## Three disjoint corpora, because tuning a profile against the seeds that
## then grade it is training against the test set:
##
## - calibration: the smoke tier's seeds — looked at freely, never graded;
## - audit: the tuning corpus — forty duels per matchup, read while tuning,
##   never asserted on;
## - acceptance: the held-out ladder — chosen by a rule (the calibration block
##   offset by 100) before any result from it was known, run once after
##   tuning. If a profile change fails it, the ordering did not generalise;
##   moving these numbers until it passes is the overfitting the split stops.
##
## Every duel prints one progress line, so the harness's no-output guard reads
## progress per duel, never per corpus (it stays a hang detector).
##
## See also: /docs/concepts/cpu.md, /docs/reference/testing.md

const MAX_TICKS := 40000
const CALIBRATION_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const ACCEPTANCE_SEEDS: Array[int] = [101, 102, 103, 104, 105, 106, 107, 108]
## A contiguous block clear of both, large enough that a ~5-point win-rate
## edge is visible; raise it, never curate it.
const AUDIT_SEEDS: Array[int] = [
	201, 202, 203, 204, 205, 206, 207, 208, 209, 210,
	211, 212, 213, 214, 215, 216, 217, 218, 219, 220,
	221, 222, 223, 224, 225, 226, 227, 228, 229, 230,
	231, 232, 233, 234, 235, 236, 237, 238, 239, 240,
]


## A Quick Play duel between two CPU profiles on `seed_value`.
static func session(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty, seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.for_difficulty(first), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.for_difficulty(second), seed_value, 1),
	]
	return MatchSession.create(config, controllers)


static func play(duel: MatchSession) -> MatchSession:
	while not duel.is_finished() and duel.state.tick < MAX_TICKS:
		duel.step()
	return duel


## +1 when `slot` won, -1 when it lost, 0 for a draw.
static func decision(duel: MatchSession, slot: int) -> int:
	var winner := duel.state.match_winner
	if winner == slot:
		return 1
	return -1 if winner == 1 - slot else 0


## Matches decided for `stronger` minus those decided for `weaker`, over every
## seed in both slots — playing both sides of a seed cancels any positional
## advantage, so a positive margin is difficulty and nothing else. One
## progress line per seed.
static func margin(stronger: MatchConfig.Difficulty, weaker: MatchConfig.Difficulty, seeds: Array[int], label: String) -> int:
	var total := 0
	for seed_value in seeds:
		var started := Time.get_ticks_msec()
		var first := decision(play(session(stronger, weaker, seed_value)), 0)
		var second := decision(play(session(weaker, stronger, seed_value)), 1)
		total += first + second
		print("  · %s seed %d: %+d %+d (%.1f s)" % [label, seed_value, first, second, float(Time.get_ticks_msec() - started) / 1000.0])
	return total
