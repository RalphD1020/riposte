extends SceneTree

## Combat feel report: what the duel's exchanges are made of, on the audit
## corpus (the CPU tuning seeds, never the held-out ladder). Hard against
## Easy and against Medium, both seats, per fighter-minute of live play:
## attack volume and quality, steel contact, openings and their conversion,
## time at measure, stamina. Definitions: /docs/reference/testing.md
## (Combat feel metrics). Read-only; never a gate.
##
## Run: godot --headless --path game --script res://tools/feel_report.gd [-- --seeds=N]
##
## See also: /docs/reference/testing.md

## The audit block (`CpuLadder.AUDIT_SEEDS`). `--seeds=N` reads the first N.
## The 2026-10-17 diagnostic used 16 (201–216). 217–240 were not in that run.
const SEEDS: PackedInt64Array = [
	201, 202, 203, 204, 205, 206, 207, 208, 209, 210,
	211, 212, 213, 214, 215, 216, 217, 218, 219, 220,
	221, 222, 223, 224, 225, 226, 227, 228, 229, 230,
	231, 232, 233, 234, 235, 236, 237, 238, 239, 240,
]
const DEFAULT_SEEDS := 16
const MAX_TICKS := 40000
## How far beyond strike reach still counts as "at measure" (m).
const MEASURE_MARGIN := 0.5

var _seeds := DEFAULT_SEEDS


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			_seeds = clampi(int(arg.trim_prefix("--seeds=")), 1, SEEDS.size())
	for rival: MatchConfig.Difficulty in [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM]:
		_report(rival)
	quit()


func _report(rival: MatchConfig.Difficulty) -> void:
	var margin := 0
	var tally := FeelTally.new()
	for index in _seeds:
		var seed_value := SEEDS[index]
		for hard_slot in 2:
			var duel := _session(MatchConfig.Difficulty.HARD if hard_slot == 0 else rival, rival if hard_slot == 0 else MatchConfig.Difficulty.HARD, seed_value)
			_play(duel, hard_slot, tally)
			var winner := duel.state.match_winner
			margin += 1 if winner == hard_slot else (-1 if winner == 1 - hard_slot else 0)
	print("Hard v %s, %d seeds both seats: margin %+d of %d" % [MatchConfig.difficulty_label(rival), _seeds, margin, _seeds * 2])
	print(tally.describe())


static func _session(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty, seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.for_difficulty(first), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.for_difficulty(second), seed_value, 1),
	]
	return MatchSession.create(config, controllers)


func _play(duel: MatchSession, hard_slot: int, tally: FeelTally) -> void:
	var rules := duel.config.rules
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var cost := rules.combat.stamina_dash_cost
	var control_0 := rules.combatant(0).weapon.control_speed
	var control_1 := rules.combatant(1).weapon.control_speed
	## Per slot: whether its current attack was released inside an opening,
	## and whether it has already hit (attacks are counted once).
	var released_open: Array[bool] = [false, false]
	var attack_hit: Array[bool] = [false, false]
	## The current steel contact episode: its ticks, and whether it held.
	var episode_ticks := 0
	var episode_held := false
	while not duel.is_finished() and duel.state.tick < MAX_TICKS:
		var state := duel.state
		var live := state.phase == MatchPhase.Id.ROUND_ACTIVE
		var open_now: Array[bool] = [_exposed(state.fighter(1)), _exposed(state.fighter(0))]
		for event in duel.step():
			if event.actor < 0 or event.actor > 1:
				continue
			var side := 0 if event.actor == hard_slot else 1
			match event.type:
				DuelEventTypes.ATTACK_STARTED:
					tally.presses[side] += 1
				DuelEventTypes.CHARGE_STARTED:
					tally.charges[side] += 1
				DuelEventTypes.ATTACK_RELEASED:
					tally.releases[side] += 1
					released_open[event.actor] = open_now[event.actor]
					attack_hit[event.actor] = false
				DuelEventTypes.ATTACK_WHIFFED:
					tally.whiffs[side] += 1
				DuelEventTypes.BODY_HIT:
					if not attack_hit[event.actor]:
						attack_hit[event.actor] = true
						tally.hits[side] += 1
						if released_open[event.actor]:
							tally.conversions[side] += 1
				DuelEventTypes.PARRY:
					tally.parries[side] += 1
				DuelEventTypes.DEFLECTION:
					tally.deflections[side] += 1
				DuelEventTypes.BLADE_CONTACT:
					tally.contacts += 1
					match ContactReading.classify(event, control_0, control_1):
						ContactReading.CLASH:
							tally.clashes += 1
						ContactReading.GLANCE:
							tally.glances += 1
		if state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
			episode_ticks += 1
			if episode_ticks > 1 and state.blade_contact.hold_count() > 0:
				episode_held = true
		elif episode_ticks > 0:
			tally.episodes += 1
			if episode_held:
				tally.binds += 1
				tally.bind_ticks += episode_ticks
			episode_ticks = 0
			episode_held = false
		if not live:
			continue
		tally.live_ticks += 1
		for slot in 2:
			if open_now[slot]:
				tally.opening_ticks[0 if slot == hard_slot else 1] += 1
		var a := state.fighter(0)
		var b := state.fighter(1)
		if DuelGeometry.distance(a, b) <= reach + MEASURE_MARGIN and not CombatPhase.is_swinging(a.weapon.phase) and not CombatPhase.is_swinging(b.weapon.phase):
			tally.at_measure += 1
		for slot in 2:
			var side := 0 if slot == hard_slot else 1
			tally.stamina[side] += state.fighter(slot).stamina
			if state.fighter(slot).stamina < cost:
				tally.under_cost[side] += 1
	for slot in 2:
		var cpu := duel.controllers[slot] as CpuController
		if cpu == null:
			continue
		var side := 0 if slot == hard_slot else 1
		tally.decisions[side] += cpu.decisions
		tally.suppressed[side] += cpu.probes_suppressed
		tally.capitalize_decisions[side] += cpu.capitalize_decisions
		tally.tempo_decisions[side] += cpu.tempo_decisions
		tally.intercept_decisions[side] += cpu.intercept_decisions


## Whether `fighter` is exposed — its blade in recovery or overswing.
static func _exposed(fighter: FighterState) -> bool:
	return fighter.weapon.phase == CombatPhase.Id.RECOVERY or fighter.weapon.phase == CombatPhase.Id.OVERSWING


class FeelTally:
	extends RefCounted
	var live_ticks := 0
	var at_measure := 0
	var contacts := 0
	var clashes := 0
	var glances := 0
	var episodes := 0
	var binds := 0
	var bind_ticks := 0
	var presses: Array[int] = [0, 0]
	var charges: Array[int] = [0, 0]
	var releases: Array[int] = [0, 0]
	var whiffs: Array[int] = [0, 0]
	var decisions: Array[int] = [0, 0]
	var suppressed: Array[int] = [0, 0]
	var capitalize_decisions: Array[int] = [0, 0]
	var tempo_decisions: Array[int] = [0, 0]
	var intercept_decisions: Array[int] = [0, 0]
	var hits: Array[int] = [0, 0]
	var conversions: Array[int] = [0, 0]
	var parries: Array[int] = [0, 0]
	var deflections: Array[int] = [0, 0]
	var opening_ticks: Array[int] = [0, 0]
	var stamina: Array[float] = [0.0, 0.0]
	var under_cost: Array[int] = [0, 0]

	func describe() -> String:
		var minutes := maxf(float(live_ticks) / 3600.0, 1e-9)
		var lines := PackedStringArray()
		for side in 2:
			lines.append("  %s: presses %.1f/min, charges %.1f/min, releases %.1f/min, attacks per hitting attack %.2f, whiffs %.1f/min, hitting attacks %.1f/min, converted %.1f%% of them, parries %.1f/min, deflections %.2f/min, stamina %.3f (under dash %.1f%%)" % [
				"hard " if side == 0 else "rival",
				presses[side] / minutes,
				charges[side] / minutes,
				releases[side] / minutes,
				float(releases[side]) / maxf(hits[side], 1),
				whiffs[side] / minutes,
				hits[side] / minutes,
				100.0 * conversions[side] / maxf(hits[side], 1),
				parries[side] / minutes,
				deflections[side] / minutes,
				stamina[side] / maxf(live_ticks, 1),
				100.0 * under_cost[side] / maxf(live_ticks, 1),
			])
		lines.append("  steel: %.1f contacts/min (clash %.0f%%, glance %.0f%%, touch %.0f%%), at measure %.1f%% of live time, openings %.1f%% / %.1f%%" % [
			contacts / minutes,
			100.0 * clashes / maxf(contacts, 1),
			100.0 * glances / maxf(contacts, 1),
			100.0 * (contacts - clashes - glances) / maxf(contacts, 1),
			100.0 * at_measure / maxf(live_ticks, 1),
			100.0 * opening_ticks[0] / maxf(live_ticks, 1),
			100.0 * opening_ticks[1] / maxf(live_ticks, 1),
		])
		lines.append("  gate: decisions %d/%d, suppressed probes %d/%d (%.1f%% / %.1f%% of decisions), capitalize %d/%d, tempo %d/%d, intercept %d/%d" % [
			decisions[0], decisions[1],
			suppressed[0], suppressed[1],
			100.0 * suppressed[0] / maxf(decisions[0], 1),
			100.0 * suppressed[1] / maxf(decisions[1], 1),
			capitalize_decisions[0], capitalize_decisions[1],
			tempo_decisions[0], tempo_decisions[1],
			intercept_decisions[0], intercept_decisions[1],
		])
		lines.append("  episodes: %.1f/min, binds %.1f/min (%.0f%% of episodes, mean %.1f ticks)" % [episodes / minutes, binds / minutes, 100.0 * binds / maxf(episodes, 1), float(bind_ticks) / maxf(binds, 1)])
		return "\n".join(lines)
