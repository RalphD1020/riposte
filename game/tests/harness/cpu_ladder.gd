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
##   tuning. The rules-53 Hard-versus-Easy result on this block (+4/16) is
##   consumed. Do not retune against it. The next acceptance grades
##   `ACCEPTANCE_SEEDS_V2`, fixed below before any duel on it is read.
##   If a profile change fails the set it is graded on, the ordering did not
##   generalise; moving these numbers until it passes is the overfitting the
##   split stops. `test:balance:accept` grades `ACCEPTANCE_SEEDS_V2`.
##   `ACCEPTANCE_SEEDS` (101–108) stays the consumed rules-53 result.
##
## Every duel prints one progress line, so the harness's no-output guard reads
## progress per duel, never per corpus (it stays a hang detector).
##
## See also: /docs/concepts/cpu.md, /docs/reference/testing.md

const MAX_TICKS := 40000
const CALIBRATION_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const ACCEPTANCE_SEEDS: Array[int] = [101, 102, 103, 104, 105, 106, 107, 108]
## Next CPU acceptance, after impact authority is accepted. Same size as v1,
## clear of calibration (1–8), v1 (101–108) and the audit block (201–240).
## Fixed before any result on it is known. `test:balance:accept` grades this
## block. v1 stays consumed and is not the graded set.
const ACCEPTANCE_SEEDS_V2: Array[int] = [301, 302, 303, 304, 305, 306, 307, 308]
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
	return session_of(CpuProfile.for_difficulty(first), CpuProfile.for_difficulty(second), seed_value)


## The one duel constructor: `first` in slot 0, `second` in slot 1. A profile
## candidate is graded through this too, so a candidate run and the ladder
## differ only in the profiles, never in how the duel is built.
static func session_of(first: CpuProfile, second: CpuProfile, seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, first, seed_value, 0),
		CpuController.create(config.rules, second, seed_value, 1),
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
