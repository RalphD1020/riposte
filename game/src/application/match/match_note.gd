class_name MatchNote
extends RefCounted

## One fixed-size friend-match message. The bytes are the wire form. A note
## never carries a scene, a node path, or a claimed hit.
##
## See also: /docs/concepts/simulation.md

const PROTOCOL_VERSION := 1
const BUILD_ID := 1
const SIZE := 33
const ACCEPT_WINDOW := 6

const KIND_JOIN := 1
const KIND_ACCEPT := 2
const KIND_START := 3
const KIND_COMMAND := 4
const KIND_SNAPSHOT := 5
const KIND_DISCONNECT := 6

const RESULT_LIVE := 0
const RESULT_ABANDONED := 1
const RESULT_DECIDED := 2

var kind: int = 0
var session_id: int = 0
var slot: int = -1
var tick: int = 0
var move_x: int = 0
var move_y: int = 0
var flags: int = 0
var seq: int = 0
var rules_version: int = 0
var build_id: int = BUILD_ID
var extra: int = 0
## Authority-side only. Not written to the wire.
var state_hash: String = ""


static func join(version: int, identity: int) -> MatchNote:
	var note := MatchNote.new()
	note.kind = KIND_JOIN
	note.rules_version = version
	note.build_id = identity
	return note


static func pack(match_id: int, player: int, sequence: int, intent: PlayerCommand) -> MatchNote:
	var note := MatchNote.new()
	note.kind = KIND_COMMAND
	note.session_id = match_id
	note.slot = player
	note.seq = sequence
	note.tick = intent.tick
	note.move_x = intent.move_x
	note.move_y = intent.move_y
	note.flags = intent.flags()
	return note


func to_command() -> PlayerCommand:
	var intent := PlayerCommand.new()
	intent.tick = tick
	intent.move_x = move_x
	intent.move_y = move_y
	intent.attack_pressed = (flags & PlayerCommand.FLAG_PRESSED) != 0
	intent.attack_released = (flags & PlayerCommand.FLAG_RELEASED) != 0
	intent.attack_cancel = (flags & PlayerCommand.FLAG_CANCEL) != 0
	intent.dash_modifier = (flags & PlayerCommand.FLAG_DASH) != 0
	return intent


func to_bytes() -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(SIZE)
	raw[0] = kind
	raw[1] = PROTOCOL_VERSION
	raw.encode_u32(2, session_id)
	raw[6] = slot if slot >= 0 else 255
	raw.encode_s32(7, tick)
	raw.encode_s32(11, move_x)
	raw.encode_s32(15, move_y)
	raw[19] = flags
	raw.encode_u32(20, seq)
	raw.encode_s32(24, rules_version)
	raw[28] = build_id
	raw.encode_u32(29, extra)
	return raw


static func from_bytes(raw: PackedByteArray) -> MatchNote:
	if raw.size() != SIZE or raw[1] != PROTOCOL_VERSION:
		return null
	var note := MatchNote.new()
	note.kind = raw[0]
	note.session_id = raw.decode_u32(2)
	note.slot = -1 if raw[6] == 255 else raw[6]
	note.tick = raw.decode_s32(7)
	note.move_x = raw.decode_s32(11)
	note.move_y = raw.decode_s32(15)
	note.flags = raw[19]
	note.seq = raw.decode_u32(20)
	note.rules_version = raw.decode_s32(24)
	note.build_id = raw[28]
	note.extra = raw.decode_u32(29)
	if note.kind < KIND_JOIN or note.kind > KIND_DISCONNECT:
		return null
	return note
