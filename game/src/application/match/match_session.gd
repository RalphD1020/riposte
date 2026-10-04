class_name MatchSession
extends RefCounted

## One running match: the authoritative DuelSimulation, its state, two
## controllers, the replay record, and the full event log. Each `step` asks
## both controllers for a command, records them, and advances one tick. The
## session never renders, never reads devices, and never waits on
## presentation.
##
## See also: /docs/concepts/simulation.md

var config: MatchConfig
var simulation: DuelSimulation
var state: MatchState
var record: ReplayRecord
var events: Array[DuelEvent] = []
var controllers: Array[FighterController] = []
var telemetry: TelemetrySink


## Returns null when the rules are invalid or controllers are missing.
static func create(match_config: MatchConfig, fighter_controllers: Array[FighterController], sink: TelemetrySink = null) -> MatchSession:
	var duel := DuelSimulation.create(match_config.rules)
	if duel == null or fighter_controllers.size() != 2 or fighter_controllers.has(null):
		return null
	var session := MatchSession.new()
	session.config = match_config
	session.simulation = duel
	session.state = duel.new_match(match_config.seed_value)
	session.record = ReplayRecord.begin(match_config.rules, match_config.seed_value)
	session.controllers = fighter_controllers
	session.telemetry = sink if sink != null else TelemetrySink.new()
	return session


func step() -> Array[DuelEvent]:
	if state.is_finished():
		var none: Array[DuelEvent] = []
		return none
	var command_0 := controllers[0].command_for(state, 0)
	var command_1 := controllers[1].command_for(state, 1)
	record.append(command_0, command_1)
	var tick_events := simulation.step(state, command_0, command_1)
	events.append_array(tick_events)
	telemetry.record_duel_events(tick_events)
	if state.is_finished():
		record.final_hash = StateHasher.hash_state(state)
	return tick_events


func is_finished() -> bool:
	return state.is_finished()


func summary(slot: int) -> MatchSummary:
	return MatchSummary.from_session(self, slot)
