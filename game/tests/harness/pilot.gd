class_name Pilot
extends RefCounted

## Test-only deterministic command source. `wander` drifts toward the
## opponent with seeded random footwork and attacks, so long runs reliably
## produce contacts. `idle` never acts. `approach_and_tap` closes in and taps
## once — a point-symmetric script for mirror tests.
##
## See also: /docs/reference/testing.md

const KIND_IDLE := 0
const KIND_WANDER := 1
const KIND_APPROACH_TAP := 2

var kind: int = KIND_IDLE
var _rng: SeededRng
var _move_x: float = 0.0
var _move_y: float = 0.0
var _move_left: int = 0
var _held: bool = false
var _hold_left: int = 0
var _tapped: bool = false


static func idle() -> Pilot:
	return Pilot.new()


static func wander(seed_value: int, stream: int) -> Pilot:
	var pilot := Pilot.new()
	pilot.kind = KIND_WANDER
	pilot._rng = SeededRng.create(seed_value, stream)
	return pilot


static func approach_and_tap() -> Pilot:
	var pilot := Pilot.new()
	pilot.kind = KIND_APPROACH_TAP
	return pilot


func command(state: MatchState, slot: int) -> PlayerCommand:
	match kind:
		KIND_WANDER:
			return _wander(state, slot)
		KIND_APPROACH_TAP:
			return _approach_and_tap(state, slot)
	return PlayerCommand.idle(state.tick)


func _wander(state: MatchState, slot: int) -> PlayerCommand:
	var me := state.fighter(slot)
	var them := state.opponent_of(slot)
	if _move_left <= 0:
		var dx := them.x - me.x
		var dy := them.y - me.y
		var distance := maxf(SimMath.length(dx, dy), 0.001)
		var toward := 0.7 if distance > 1.6 else -0.2
		_move_x = dx / distance * toward + _rng.next_range(-0.6, 0.6)
		_move_y = dy / distance * toward + _rng.next_range(-0.6, 0.6)
		_move_left = _rng.next_int(4, 24)
	_move_left -= 1
	var pressed := false
	var released := false
	if _held:
		_hold_left -= 1
		if _hold_left <= 0:
			released = true
			_held = false
	elif _rng.next_float() < 0.08:
		pressed = true
		_held = true
		_hold_left = _rng.next_int(1, 64)
	return PlayerCommand.create(state.tick, _move_x, _move_y, pressed, released)


func _approach_and_tap(state: MatchState, slot: int) -> PlayerCommand:
	var me := state.fighter(slot)
	var them := state.opponent_of(slot)
	if _tapped or state.phase != MatchPhase.Id.ROUND_ACTIVE:
		return PlayerCommand.idle(state.tick)
	if DuelGeometry.distance(me, them) > 1.3:
		var direction := 1.0 if them.x > me.x else -1.0
		return PlayerCommand.create(state.tick, direction, 0.0)
	_tapped = true
	return PlayerCommand.create(state.tick, 0.0, 0.0, true, true)
