class_name CrowdDirector
extends RefCounted

## Presentation-only audience. It reads events and the set score and names
## one reaction. It does not write combat state. A set point is the tick the
## score arrives there, once. First-to-one has no set point: the opening
## score is already zero. A parry already playing holds that cue and
## plays it when the parry's cooldown ends. Victory replaces it.
##
## See also: /docs/concepts/presentation.md

const COOLDOWN_TICKS := 90
const DECAY := 0.92
## A murmur or a light cheer. A stronger cue may speak over their cooldown.
const CUE_MURMUR := &"murmur"
const CUE_CHEER := &"cheer"
const CUE_SETPOINT := &"setpoint"
const CUE_STRONG := &"strong"
const CUE_VICTORY := &"victory"
const RANK_MINOR := 1
const RANK_SETPOINT := 2
const RANK_STRONG := 3
const RANK_VICTORY := 4

var excitement: float = 0.0
var cooldown: int = 0
var _rank: int = 0
var _at_setpoint: bool = false
var _pending: StringName = &""
## The set-win reaction plays once. The snapshot keeps the winner after that,
## and a second cheer every cooldown would restart the chant for the rest of
## the deciding round.
var _victory_played: bool = false


func observe(events: Array[DuelEvent], scores: PackedInt32Array, rounds_to_win: int, set_winner: int) -> StringName:
	excitement *= DECAY
	if cooldown > 0:
		cooldown -= 1
	var rising := _mark_setpoint(scores, rounds_to_win)
	if MatchPhase.is_combatant(set_winner):
		_clear_pending()
		if _victory_played:
			return &""
		_victory_played = true
		excitement = 1.0
		_hold(RANK_VICTORY)
		return CUE_VICTORY
	if _is_strong(events):
		excitement = minf(excitement + 0.45, 1.0)
		if rising:
			_pending = CUE_SETPOINT
		if cooldown > 0 and RANK_STRONG <= _rank:
			return &""
		_hold(RANK_STRONG)
		return CUE_STRONG
	if rising:
		excitement = minf(excitement + 0.35, 1.0)
		if cooldown > 0 and RANK_SETPOINT <= _rank:
			_pending = CUE_SETPOINT
			return &""
		_clear_pending()
		_hold(RANK_SETPOINT)
		return CUE_SETPOINT
	var minor := _minor(events)
	if minor != &"":
		if cooldown > 0 and _rank_of(minor) <= _rank:
			return &""
		_hold(_rank_of(minor))
		return minor
	if _pending == CUE_SETPOINT and cooldown == 0:
		_clear_pending()
		_hold(RANK_SETPOINT)
		return CUE_SETPOINT
	return &""


func _mark_setpoint(scores: PackedInt32Array, rounds_to_win: int) -> bool:
	## First-to-one has no set point: the opening score is already 0, and the
	## next point ends the set. An earned set point is a positive score.
	var earned := rounds_to_win - 1
	var at_point := false
	if earned > 0:
		for score in scores:
			if score == earned:
				at_point = true
	var rising := at_point and not _at_setpoint
	_at_setpoint = at_point
	return rising


func _is_strong(events: Array[DuelEvent]) -> bool:
	for event: DuelEvent in events:
		if event.type == DuelEventTypes.PARRY or event.type == DuelEventTypes.CRITICAL_HIT:
			return true
	return false


func _minor(events: Array[DuelEvent]) -> StringName:
	for event: DuelEvent in events:
		if event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_HIT:
			excitement = minf(excitement + 0.2, 1.0)
			return CUE_CHEER if excitement >= 0.55 else CUE_MURMUR
	return &""


func _clear_pending() -> void:
	_pending = &""


func _hold(rank: int) -> void:
	cooldown = COOLDOWN_TICKS
	_rank = rank


func _rank_of(cue: StringName) -> int:
	match cue:
		CUE_STRONG:
			return RANK_STRONG
		CUE_SETPOINT:
			return RANK_SETPOINT
		CUE_CHEER, CUE_MURMUR:
			return RANK_MINOR
		_:
			return 0
