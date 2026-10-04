class_name SimRunner
extends RefCounted

## Test-only match runner: drives a DuelSimulation with two pilots, records a
## replay, and keeps per-tick hashes and every event.
##
## See also: /docs/reference/testing.md

var simulation: DuelSimulation
var state: MatchState
var record: ReplayRecord
var events: Array[DuelEvent] = []
var hashes: PackedStringArray = PackedStringArray()


static func create(rules: DuelRules, seed_value: int) -> SimRunner:
	var runner := SimRunner.new()
	runner.simulation = DuelSimulation.create(rules)
	runner.state = runner.simulation.new_match(seed_value)
	runner.record = ReplayRecord.begin(rules, seed_value)
	return runner


func run(pilot_0: Pilot, pilot_1: Pilot, max_ticks: int, keep_hashes: bool = false) -> void:
	for _i in max_ticks:
		if state.is_finished():
			break
		var command_0 := pilot_0.command(state, 0)
		var command_1 := pilot_1.command(state, 1)
		record.append(command_0, command_1)
		events.append_array(simulation.step(state, command_0, command_1))
		if keep_hashes:
			hashes.append(StateHasher.hash_state(state))
	record.final_hash = StateHasher.hash_state(state)


## Step idle until the active round begins.
func skip_intro() -> void:
	while state.phase == MatchPhase.Id.ROUND_INTRO:
		events.append_array(simulation.step(state, PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick)))


func idle(ticks: int) -> void:
	for _i in ticks:
		events.append_array(simulation.step(state, PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick)))


func count(type: StringName) -> int:
	return DuelFixture.of_type(events, type).size()


func first(type: StringName) -> DuelEvent:
	var matches := DuelFixture.of_type(events, type)
	return null if matches.is_empty() else matches[0]
