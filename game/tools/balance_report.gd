extends SceneTree

## Balance pass tool (PLAN Phase 17): CPU-vs-CPU matchups with the shipping
## rules, printed as a compact table. Read-only; changes nothing.
##
## Run: `pnpm test:balance:audit` (the ladder, a line per duel), or
## godot --headless --path game --script res://tools/balance_report.gd
## Takes a few minutes for the ladder; the mirror-match tactics table adds
## about a quarter of an hour (skip it with `-- --ladder-only`). `-- --audit`
## replaces the ladder with a per-side behaviour table over the same duels.
## Not a gate; nothing fails here.
##
## This tool owns the one ladder claim the suite deliberately does not gate.
## Hard's edge over Medium is real but small — about 54.5% of duels — and no
## sample a per-commit suite can afford distinguishes that from a coin. So
## `test_cpu.gd` gates Medium and Hard over Easy, where the margin is near
## ceiling, and the Hard-over-Medium effect *size* is read here instead.
##
## Read the `matches`, `rounds`, and `hits` columns together. Within a single
## seed they move together, so three agreeing numbers on a short run are one
## observation, not three.
##
## See also: /docs/concepts/cpu.md, /docs/reference/testing.md

## The tuning corpus (`CpuLadder.AUDIT_SEEDS`): disjoint from the smoke and
## held-out seeds, so reading this never contaminates the acceptance ladder.
const SEEDS: Array[int] = CpuLadder.AUDIT_SEEDS
const MAX_TICKS := 40000


func _initialize() -> void:
	var levels: Array[MatchConfig.Difficulty] = [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]
	var audit := OS.get_cmdline_user_args().has("--audit")
	for first in levels:
		for second in levels:
			if second <= first:
				continue
			if audit:
				_audit(first, second)
			else:
				_report(first, second)
	if audit or OS.get_cmdline_user_args().has("--ladder-only"):
		quit(0)
		return
	## Mirror matches, so a tactic's support is not confounded by facing a
	## different-difficulty opponent who creates openings at a different rate.
	for level in levels:
		_tactics(level)
	quit(0)


## Why a profile wins, not just whether. A win rate cannot distinguish "Hard
## perceives whiffs sooner but never converts them" from "Hard converts but
## gives the openings back", and those have opposite fixes (CPU-005).
func _tactics(difficulty: MatchConfig.Difficulty) -> void:
	var rules := StandardDuelRules.create()
	var totals := TacticalAudit.create(0, rules, difficulty)
	for match_seed in SEEDS:
		for slot in 2:
			var levels: Array[MatchConfig.Difficulty] = [difficulty, difficulty]
			var session := _session(levels, match_seed)
			var audit := TacticalAudit.create(slot, session.config.rules, difficulty)
			for _tick in MAX_TICKS:
				if session.is_finished():
					break
				session.step()
				audit.observe(session.state)
			totals.absorb(audit)
	print("\n%s tactics over %d duels" % [MatchConfig.difficulty_label(difficulty), SEEDS.size() * 2])
	print("  %-34s %8s %8s  %s" % ["behaviour", "support", "rate", "verdict"])
	for metric in totals.metrics():
		print(
			(
				"  %-34s %8d %7.1f%%  %s"
				% [
					metric.label,
					metric.support,
					metric.rate() * 100.0,
					TacticalAudit.verdict_label(metric.verdict()),
				]
			)
		)
	var share := 0.0 if totals.total_ticks == 0 else float(totals.ideal_measure_ticks) / float(totals.total_ticks)
	print("  %-34s %8d %7.1f%%" % ["time held at ideal measure", totals.total_ticks, share * 100.0])


func _report(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty) -> void:
	var wins := PackedInt32Array([0, 0, 0])
	## Wins per (profile, slot) — `first` in slot 0, `first` in slot 1, then
	## `second` likewise. Seeds alternate slots, so a total can hide a slot
	## bias that a fixed-slot candidate run would show.
	var side_wins := PackedInt32Array([0, 0, 0, 0])
	var rounds := PackedInt32Array([0, 0])
	var hits := PackedInt32Array([0, 0])
	var parries := PackedInt32Array([0, 0])
	var charge := PackedFloat64Array([0.0, 0.0])
	var attacks := PackedInt32Array([0, 0])
	var round_ticks := 0
	var round_count := 0
	## `--paired`: every seed in both slot orders, so a slot effect cannot
	## hide in which seeds happened to be swapped (I-7). Default: alternate.
	var paired := OS.get_cmdline_user_args().has("--paired")
	var duels := SEEDS.size() * (2 if paired else 1)
	for index in duels:
		var swap := index % 2 == 1
		var match_seed: int = SEEDS[index >> 1] if paired else SEEDS[index]
		var levels: Array[MatchConfig.Difficulty] = [first, second]
		if swap:
			levels = [second, first]
		var session := _session(levels, match_seed)
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
			var who := (1 - winner) if swap else winner
			wins[who] += 1
			side_wins[who * 2 + winner] += 1
		## One line per duel: the runner's no-output guard reads progress.
		print("  · %s v %s seed %d: winner %s" % [MatchConfig.difficulty_label(first), MatchConfig.difficulty_label(second), match_seed, str(winner)])
	print(
		"%s vs %s | matches %d-%d (draws %d) | by slot P1/P2 %d/%d-%d/%d | rounds %d-%d | hits %d-%d | parries %d-%d | avg charge %.2f-%.2f | avg round %.1fs"
		% [
			MatchConfig.difficulty_label(first),
			MatchConfig.difficulty_label(second),
			wins[0], wins[1], wins[2],
			side_wins[0], side_wins[1], side_wins[2], side_wins[3],
			rounds[0], rounds[1],
			hits[0], hits[1],
			parries[0], parries[1],
			charge[0] / maxf(attacks[0], 1.0), charge[1] / maxf(attacks[1], 1.0),
			SimulationTimebase.ticks_to_seconds(round_ticks) / maxf(round_count, 1.0),
		]
	)


## How each side of a matchup fights, per duel, on the same corpus as the
## ladder (`-- --audit`). A win rate says who wins; this says whether a
## profile loses on spacing, on charge commitment, or on blade engagement.
## Whiffs punished = body hits taken within half a second of one's own whiff.
const PUNISH_WINDOW_TICKS := 30
const FULL_CHARGE := 0.9
const COMMITTED := 0.5


func _audit(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty) -> void:
	var labels := ["mean distance (m)", "time inside strike reach", "time committed (> 0.5)", "attacks", "full-charge attacks", "whiffs", "whiffs punished", "blade contacts", "parries", "body hits landed", "pokes landed", "body hits taken"]
	var totals: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
	for who in 2:
		totals[who].resize(labels.size())
	var active_ticks := 0
	for index in SEEDS.size():
		var swap := index % 2 == 1
		var levels: Array[MatchConfig.Difficulty] = [first, second]
		if swap:
			levels = [second, first]
		var session := _session(levels, SEEDS[index])
		var rules := session.config.rules
		var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
		var last_whiff := PackedInt32Array([-1000000, -1000000])
		for _tick in MAX_TICKS:
			if session.is_finished():
				break
			for event in session.step():
				var actor := event.actor
				if actor < 0 or actor > 1:
					if event.type == DuelEventTypes.BLADE_CONTACT:
						for slot in 2:
							totals[(1 - slot) if swap else slot][7] += 1.0
					continue
				var who := (1 - actor) if swap else actor
				var victim_who := 1 - who
				match event.type:
					DuelEventTypes.ATTACK_RELEASED:
						totals[who][3] += 1.0
						if event.number(DuelEventKeys.CHARGE) >= FULL_CHARGE:
							totals[who][4] += 1.0
					DuelEventTypes.ATTACK_WHIFFED:
						totals[who][5] += 1.0
						last_whiff[actor] = event.tick
					DuelEventTypes.BLADE_CONTACT:
						totals[0][7] += 1.0
						totals[1][7] += 1.0
					DuelEventTypes.PARRY:
						totals[who][8] += 1.0
					DuelEventTypes.BODY_HIT:
						totals[who][9] += 1.0
						totals[victim_who][11] += 1.0
						if event.tick - last_whiff[1 - actor] <= PUNISH_WINDOW_TICKS:
							totals[victim_who][6] += 1.0
					DuelEventTypes.BODY_POKE:
						totals[who][10] += 1.0
			var state := session.state
			if state.phase != MatchPhase.Id.ROUND_ACTIVE:
				continue
			active_ticks += 1
			var distance := DuelGeometry.distance(state.fighter(0), state.fighter(1))
			for slot in 2:
				var who := (1 - slot) if swap else slot
				totals[who][0] += distance
				if distance <= reach:
					totals[who][1] += 1.0
				if CommitmentModel.commitment(state.fighter(slot).weapon, rules.combatant(slot).weapon) > COMMITTED:
					totals[who][2] += 1.0
	var duels := float(SEEDS.size())
	var ticks := maxf(float(active_ticks), 1.0)
	print("\n%s vs %s behaviour over %d duels (per duel unless a share)" % [MatchConfig.difficulty_label(first), MatchConfig.difficulty_label(second), SEEDS.size()])
	print("  %-26s %10s %10s" % ["", MatchConfig.difficulty_label(first), MatchConfig.difficulty_label(second)])
	for row in labels.size():
		var values := PackedFloat64Array([totals[0][row], totals[1][row]])
		for who in 2:
			if row == 0:
				values[who] /= ticks
			elif row <= 2:
				values[who] = values[who] / ticks * 100.0
			else:
				values[who] /= duels
		var unit := "%" if row in [1, 2] else " "
		print("  %-26s %9.2f%s %9.2f%s" % [labels[row], values[0], unit, values[1], unit])


func _session(levels: Array[MatchConfig.Difficulty], match_seed: int) -> MatchSession:
	return CpuLadder.session(levels[0], levels[1], match_seed)
