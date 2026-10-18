class_name FriendAuthority
extends RefCounted

## Host-authoritative casual match. This process owns the duel. Guests submit
## commands; they do not submit outcomes. A missing command holds the last
## move and adds no attack edge. Disconnect abandons the session with no
## winner and no host migration. The accepted command log is what a replay
## verifies. This is not a ranked result and not a Steam transport.
##
## See also: /docs/concepts/simulation.md

const NO_WINNER := 255

var session_id: int = 0
var rules: DuelRules
var simulation: DuelSimulation
var state: MatchState
var record: ReplayRecord
var build_id: int = MatchNote.BUILD_ID
var abandoned: bool = false
var joined: int = 0
var _next_seq := PackedInt32Array([1, 1])
var _held: Array = [null, null]
var _last_move_x := PackedInt32Array([0, 0])
var _last_move_y := PackedInt32Array([0, 0])
var _connected := PackedByteArray([0, 0])


static func open(duel_rules: DuelRules, seed_value: int, identity: int = MatchNote.BUILD_ID) -> FriendAuthority:
	var authority := FriendAuthority.new()
	authority.rules = duel_rules
	authority.build_id = identity
	authority.simulation = DuelSimulation.create(duel_rules)
	if authority.simulation == null:
		return null
	authority.state = authority.simulation.new_match(seed_value)
	authority.record = ReplayRecord.begin(duel_rules, seed_value)
	authority.session_id = seed_value if seed_value != 0 else 1
	return authority


func accept_join(note: MatchNote) -> MatchNote:
	if note == null or note.kind != MatchNote.KIND_JOIN:
		return null
	if note.rules_version != rules.version or note.build_id != build_id:
		return null
	if joined >= 2 or abandoned:
		return null
	var slot := joined
	joined += 1
	_connected[slot] = 1
	var reply := MatchNote.new()
	reply.kind = MatchNote.KIND_ACCEPT
	reply.session_id = session_id
	reply.slot = slot
	reply.rules_version = rules.version
	reply.build_id = build_id
	reply.extra = state.tick
	return reply


func submit(slot: int, note: MatchNote) -> bool:
	if abandoned or state.is_finished() or note == null or note.kind != MatchNote.KIND_COMMAND:
		return false
	if slot < 0 or slot > 1 or _connected[slot] == 0 or note.slot != slot or note.session_id != session_id:
		return false
	if note.seq != _next_seq[slot]:
		return false
	if note.tick < state.tick - MatchNote.ACCEPT_WINDOW or note.tick > state.tick + MatchNote.ACCEPT_WINDOW:
		return false
	_held[slot] = note
	_next_seq[slot] = note.seq + 1
	return true


func end_session(slot: int) -> void:
	if slot < 0 or slot > 1:
		return
	_connected[slot] = 0
	abandoned = true


func tick() -> MatchNote:
	var note := MatchNote.new()
	note.kind = MatchNote.KIND_SNAPSHOT
	note.session_id = session_id
	note.rules_version = rules.version
	note.build_id = build_id
	if abandoned:
		note.extra = MatchNote.RESULT_ABANDONED
		note.slot = NO_WINNER
		note.tick = state.tick
		note.state_hash = StateHasher.hash_state(state)
		return note
	if state.is_finished():
		note.extra = MatchNote.RESULT_DECIDED
		note.slot = state.match_winner if state.match_winner >= 0 else NO_WINNER
		note.tick = state.tick
		note.state_hash = record.final_hash
		return note
	var first := _command_for(0)
	var second := _command_for(1)
	first.tick = state.tick
	second.tick = state.tick
	record.append(first, second)
	simulation.step(state, first, second)
	record.final_hash = StateHasher.hash_state(state)
	note.tick = state.tick
	note.state_hash = record.final_hash
	if state.is_finished():
		note.extra = MatchNote.RESULT_DECIDED
		note.slot = state.match_winner if state.match_winner >= 0 else NO_WINNER
	else:
		note.extra = MatchNote.RESULT_LIVE
		note.slot = NO_WINNER
	return note


func _command_for(slot: int) -> PlayerCommand:
	var waiting: Variant = _held[slot]
	_held[slot] = null
	if waiting != null:
		var command := (waiting as MatchNote).to_command().sanitized()
		_last_move_x[slot] = command.move_x
		_last_move_y[slot] = command.move_y
		return command
	var held := PlayerCommand.new()
	held.move_x = _last_move_x[slot]
	held.move_y = _last_move_y[slot]
	return held
