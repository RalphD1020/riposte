class_name DuelSimulation
extends RefCounted

## The authoritative duel. `step` consumes exactly one PlayerCommand per
## fighter per tick and returns the events that tick produced. It never reads
## render delta, Godot physics, input devices, or the identity of the command
## source (COMBAT §7, §69): the same rules + seed + commands always reproduce
## the same duel, whether a human, the CPU, a replay, or a server sent them.
##
## Tick order (symmetric: per-fighter updates read only start-of-tick
## relationships, so slot order cannot bias outcomes):
##   input edges → tracking + facing → footwork → weapon motor → arena →
##   bind upkeep → swept collision → contact resolution → round end.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md

var rules: DuelRules
var _collision := CollisionSystem.new()
var _report := ContactReport.new()
var _start: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
var _finish: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]


## Returns null when the rules are invalid (fail closed).
static func create(duel_rules: DuelRules) -> DuelSimulation:
	if duel_rules == null or not duel_rules.is_valid():
		return null
	var simulation := DuelSimulation.new()
	simulation.rules = duel_rules
	return simulation


func new_match(seed_value: int) -> MatchState:
	return DuelSetup.new_state(rules, seed_value)


func step(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = []
	if state.is_finished():
		return events
	match state.phase:
		MatchPhase.Id.ROUND_INTRO:
			_step_intro(state, events)
		MatchPhase.Id.ROUND_ACTIVE:
			_step_active(state, command_0.sanitized(), command_1.sanitized(), events)
		MatchPhase.Id.ROUND_RESULT:
			_step_result(state, events)
	state.tick += 1
	return events


func _step_intro(state: MatchState, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	if state.phase_ticks >= rules.intro_ticks:
		state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
		for fighter in state.fighters:
			fighter.clear_attack_input()
		events.append(DuelEvent.create(DuelEventTypes.ROUND_STARTED, state.tick, DuelEvent.NONE, DuelEvent.NONE, {DuelEventKeys.ROUND: state.round_number}))


func _step_active(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	state.round_ticks += 1
	var tick := state.tick
	var a := state.fighter(0)
	var b := state.fighter(1)
	var commands: Array[PlayerCommand] = [command_0, command_1]
	_start[0].write(a)
	_start[1].write(b)
	for slot in 2:
		WeaponSystem.apply_input(state.fighter(slot), commands[slot], rules, tick, events)
	var tracking := PackedFloat64Array([
		CommitmentModel.tracking_multiplier(a, b, rules.fighter),
		CommitmentModel.tracking_multiplier(b, a, rules.fighter),
	])
	var targets := PackedFloat64Array([b.x, b.y, a.x, a.y])
	for slot in 2:
		var fighter := state.fighter(slot)
		if fighter.is_alive():
			FacingSystem.step(fighter, targets[slot * 2], targets[slot * 2 + 1], tracking[slot], rules.fighter)
			MovementSystem.step(fighter, commands[slot].axis_x(), commands[slot].axis_y(), rules.fighter)
		else:
			MovementSystem.coast(fighter, rules.fighter)
	for slot in 2:
		WeaponSystem.step(state.fighter(slot), state.opponent_of(slot), rules, tick, events)
	ArenaConstraints.resolve(a, b, rules)
	_finish[0].write(a)
	_finish[1].write(b)
	ContactResolver.update_bind(state, rules, tick, events)
	_collision.detect(state, _start, _finish, rules, state.blade_cooldown == 0, _report)
	if _report.any():
		ContactResolver.resolve(state, _report, _start, rules, tick, events)
	if state.blade_cooldown > 0:
		state.blade_cooldown -= 1
	_check_round_end(state, events)


## While the result is shown, bodies brake and blades settle; nothing new can
## happen, so settling events are discarded.
func _step_result(state: MatchState, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	var settling: Array[DuelEvent] = []
	for slot in 2:
		var fighter := state.fighter(slot)
		MovementSystem.coast(fighter, rules.fighter)
		fighter.clear_attack_input()
		WeaponSystem.step(fighter, state.opponent_of(slot), rules, state.tick, settling)
	ArenaConstraints.resolve(state.fighter(0), state.fighter(1), rules)
	if state.phase_ticks < rules.result_ticks:
		return
	var scores := state.scores
	if scores[0] >= rules.rounds_to_win or scores[1] >= rules.rounds_to_win:
		_end_match(state, 0 if scores[0] > scores[1] else 1, MatchPhase.REASON_SCORE, events)
	elif state.round_number >= rules.max_rounds:
		var winner := MatchPhase.DRAW
		if scores[0] != scores[1]:
			winner = 0 if scores[0] > scores[1] else 1
		_end_match(state, winner, MatchPhase.REASON_ROUND_LIMIT, events)
	else:
		state.round_number += 1
		DuelSetup.reset_round(state, rules)
		state.set_phase(MatchPhase.Id.ROUND_INTRO)


func _check_round_end(state: MatchState, events: Array[DuelEvent]) -> void:
	var a_alive := state.fighter(0).is_alive()
	var b_alive := state.fighter(1).is_alive()
	var timed_out := state.round_ticks >= rules.round_time_limit_ticks
	if a_alive and b_alive and not timed_out:
		return
	var winner := MatchPhase.DRAW
	var reason := MatchPhase.REASON_KILL
	if not a_alive and not b_alive:
		reason = MatchPhase.REASON_DOUBLE_KILL
	elif not a_alive:
		winner = 1
	elif not b_alive:
		winner = 0
	else:
		reason = MatchPhase.REASON_TIMEOUT
		var health_a := state.fighter(0).health
		var health_b := state.fighter(1).health
		if health_a != health_b:
			winner = 0 if health_a > health_b else 1
	state.round_winner = winner
	state.end_reason = reason
	if winner == 0 or winner == 1:
		state.scores[winner] += 1
	state.set_phase(MatchPhase.Id.ROUND_RESULT)
	events.append(DuelEvent.create(DuelEventTypes.ROUND_ENDED, state.tick, winner if winner != MatchPhase.DRAW else DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.ROUND: state.round_number,
		DuelEventKeys.WINNER: winner,
		DuelEventKeys.REASON: String(reason),
		DuelEventKeys.SCORE_0: state.scores[0],
		DuelEventKeys.SCORE_1: state.scores[1],
	}))


func _end_match(state: MatchState, winner: int, reason: StringName, events: Array[DuelEvent]) -> void:
	state.match_winner = winner
	state.end_reason = reason
	state.set_phase(MatchPhase.Id.MATCH_ENDED)
	events.append(DuelEvent.create(DuelEventTypes.MATCH_ENDED, state.tick, winner if winner != MatchPhase.DRAW else DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.WINNER: winner,
		DuelEventKeys.REASON: String(reason),
		DuelEventKeys.SCORE_0: state.scores[0],
		DuelEventKeys.SCORE_1: state.scores[1],
		DuelEventKeys.ROUNDS: state.round_number,
	}))
