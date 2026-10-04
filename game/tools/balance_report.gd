extends SceneTree

## Balance pass tool (PLAN Phase 17): CPU-vs-CPU matchups with the shipping
## rules, printed as a compact table. Read-only; changes nothing.
##
## Run: godot --headless --path game --script res://tools/balance_report.gd
##
## See also: /docs/reference/testing.md

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
const MAX_TICKS := 40000


func _initialize() -> void:
	var levels: Array[MatchConfig.Difficulty] = [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]
	for first in levels:
		for second in levels:
			if second <= first:
				continue
			_report(first, second)
	quit(0)


func _report(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty) -> void:
	var wins := PackedInt32Array([0, 0, 0])
	var rounds := PackedInt32Array([0, 0])
	var hits := PackedInt32Array([0, 0])
	var parries := PackedInt32Array([0, 0])
	var charge := PackedFloat64Array([0.0, 0.0])
	var attacks := PackedInt32Array([0, 0])
	var round_ticks := 0
	var round_count := 0
	for index in SEEDS.size():
		var swap := index % 2 == 1
		var levels: Array[MatchConfig.Difficulty] = [second, first] if swap else [first, second]
		var session := _session(levels, SEEDS[index])
		var round_start := 0
		for _tick in MAX_TICKS:
			if session.is_finished():
				break
			for event in session.step():
				if event.type == DuelEventTypes.ROUND_STARTED:
					round_start = event.tick
				elif event.type == DuelEventTypes.ROUND_ENDED:
					round_ticks += event.tick - round_start
					round_count += 1
		for slot in 2:
			var who := (1 - slot) if swap else slot
			var summary := session.summary(slot)
			rounds[who] += summary.score_self
			hits[who] += summary.hits_landed
			parries[who] += summary.parries
			attacks[who] += summary.attacks
			charge[who] += summary.average_charge * summary.attacks
		var winner := session.state.match_winner
		if winner == MatchPhase.DRAW or winner == MatchPhase.NO_WINNER:
			wins[2] += 1
		else:
			wins[(1 - winner) if swap else winner] += 1
	print(
		"%s vs %s | matches %d-%d (draws %d) | rounds %d-%d | hits %d-%d | parries %d-%d | avg charge %.2f-%.2f | avg round %.1fs"
		% [
			MatchConfig.difficulty_label(first),
			MatchConfig.difficulty_label(second),
			wins[0], wins[1], wins[2],
			rounds[0], rounds[1],
			hits[0], hits[1],
			parries[0], parries[1],
			charge[0] / maxf(attacks[0], 1.0), charge[1] / maxf(attacks[1], 1.0),
			SimulationTimebase.ticks_to_seconds(round_ticks) / maxf(round_count, 1.0),
		]
	)


func _session(levels: Array[MatchConfig.Difficulty], match_seed: int) -> MatchSession:
	var config := MatchConfig.quick_play(levels[0], match_seed)
	var controllers: Array[FighterController] = []
	for slot in 2:
		controllers.append(CpuController.create(config.rules, CpuProfile.for_difficulty(levels[slot]), match_seed, slot))
	return MatchSession.create(config, controllers)
