class_name SimRunner
extends RefCounted

## Test-only match runner: drives a DuelSimulation with two pilots, records a
## replay, and keeps per-tick hashes and every event.
##
## Every advance validates StateInvariants, so any suite that drives a match
## through this runner also proves totality for the ticks it produced.
## `violations` is the per-tick audit trail; `assert_sound` is the assertion.
##
## See also: /docs/reference/testing.md

var simulation: DuelSimulation
var rules: DuelRules
var state: MatchState
var record: ReplayRecord
var events: Array[DuelEvent] = []
var hashes: PackedStringArray = PackedStringArray()
var violations: PackedStringArray = PackedStringArray()


static func create(duel_rules: DuelRules, seed_value: int) -> SimRunner:
	var runner := SimRunner.new()
	runner.simulation = DuelSimulation.create(duel_rules)
	runner.rules = duel_rules
	runner.state = runner.simulation.new_match(seed_value)
	runner.record = ReplayRecord.begin(duel_rules, seed_value)
	return runner


func run(pilot_0: Pilot, pilot_1: Pilot, max_ticks: int, keep_hashes: bool = false) -> void:
	for _i in max_ticks:
		if state.is_finished():
			break
		_step(pilot_0.command(state, 0), pilot_1.command(state, 1))
		if keep_hashes:
			hashes.append(StateHasher.hash_state(state))
	seal()


## Step idle until the active round begins.
func skip_intro() -> void:
	while state.phase == MatchPhase.Id.ROUND_INTRO:
		_step(PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick))


func idle(ticks: int) -> void:
	for _i in ticks:
		_step(PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick))


## Feed one scripted tick. Use this rather than calling `simulation.step`
## directly, so the events and the per-tick invariant audit are collected.
func push(command_0: PlayerCommand, command_1: PlayerCommand) -> void:
	_step(command_0, command_1)


## Hold a duel-relative move intent for both fighters, with no attack input.
func drive(move_x: float, move_y: float, ticks: int) -> void:
	for _i in ticks:
		_step(PlayerCommand.create(state.tick, move_x, move_y), PlayerCommand.create(state.tick, move_x, move_y))


## True when every tick this runner produced satisfied StateInvariants.
func is_sound() -> bool:
	return violations.is_empty()


## Human-readable audit of the first violation, for assertion messages.
func violation_summary() -> String:
	return "clean" if violations.is_empty() else String(", ").join(violations)


## Close the record off at the current state, so it can be verified. Separate
## from stepping because the closing hash is the expensive part and a run that
## never verifies should not pay for it.
func seal() -> void:
	record.final_hash = StateHasher.hash_state(state)


## Every tick this runner produces goes into the record, however it was
## driven. A scripted run and a piloted run are therefore equally replayable —
## a record that silently omitted the ticks fed by `push` would verify against
## a duel nobody played.
func _step(command_0: PlayerCommand, command_1: PlayerCommand) -> void:
	record.append(command_0, command_1)
	events.append_array(simulation.step(state, command_0, command_1))
	var violation := StateInvariants.check(state, rules)
	if violation != StateInvariants.OK:
		violations.append("tick %d: %s" % [state.tick, violation])


func count(type: StringName) -> int:
	return DuelFixture.of_type(events, type).size()


func first(type: StringName) -> DuelEvent:
	var matches := DuelFixture.of_type(events, type)
	return null if matches.is_empty() else matches[0]
