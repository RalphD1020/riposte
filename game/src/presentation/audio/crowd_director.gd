class_name CrowdDirector
extends RefCounted

## Presentation-only audience. It reads events and the set score and names
## one reaction. It does not write combat state. Intensity is a separate
## decaying meter: a class step adds once per run, and a quiet tick takes the
## max of that decay and one impact, clash, or whiff level. Those levels are
## presentation readings of existing payloads, not a force. A finish punches
## through cheer cooldown once per scoreline. After the set-win shot, later
## ticks with the winner still set are silence so the meter can decay. A new
## MatchScreen constructs a new director.
##
## See also: /docs/concepts/presentation.md

const COOLDOWN_TICKS := 90
## About three seconds from 1 toward the ambient band at 60 observes/s.
const DECAY := 0.985
const STEP_SETPOINT := 0.25
const STEP_PARRY := 0.35
const STEP_CRITICAL := 0.45
const STEP_FINISH := 0.65
const STEP_VICTORY := 1.0
## Half a reference-quality wound (`SEVERITY / reference_severity`). Scratches
## from a charged meeting sat near 0.02; the heavy slash on that same trace
## clamped at 1. This split is that scale, not a new force.
const HEAVY_SEVERITY := 0.5
## Bed levels, below the critical and finish steps so a miss cannot outrank a hit.
const BODY_LEVEL := 0.2
const HEAVY_LEVEL := 0.35
const SOLID_LEVEL := 0.12
const STRONG_LEVEL := 0.22
const WHIFF_LEVEL := 0.15
## A far hold on the shipping rules whiffed at charge 0.81. A tap is 0.
const WHIFF_COMMITTED_CHARGE := 0.5
## Payload label written by StrikeResult for a graze.
const GRAZE_KIND := "graze"
## The high end of CombatFeedbackDirector's 0..1 parry reading.
const CLEAN_PARRY_QUALITY := 1.0
const CUE_MURMUR := &"murmur"
const CUE_CHEER := &"cheer"
const CUE_SETPOINT := &"setpoint"
const CUE_STRONG := &"strong"
const CUE_VICTORY := &"victory"
const CUE_GASP := &"gasp"
const CLASS_NONE := 0
const CLASS_SETPOINT := 1
const CLASS_PARRY := 2
const CLASS_CRITICAL := 3
const CLASS_FINISH := 4
const CLASS_VICTORY := 5

var excitement: float = 0.0
var cooldown: int = 0
var _run: int = CLASS_NONE
var _at_setpoint: bool = false
## The set-win reaction plays once. The snapshot keeps the winner after that.
var _victory_played: bool = false
## Finish shot already fired for this scoreline. A duplicated kill or ring-out
## at the same scores does not roar again. A new round result may.
var _finish_scores: PackedInt32Array = PackedInt32Array()


func observe(events: Array[DuelEvent], scores: PackedInt32Array, rounds_to_win: int, set_winner: int, tuning: CombatTuning = null, distance: float = INF, reach: PackedFloat32Array = PackedFloat32Array()) -> StringName:
	if cooldown > 0:
		cooldown -= 1
	var rising := _mark_setpoint(scores, rounds_to_win)
	var klass := _class_of(events, set_winner, rising)
	_apply_intensity(klass, events, tuning)
	return _select_shot(klass, events, scores, distance, reach)


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


func _class_of(events: Array[DuelEvent], set_winner: int, rising: bool) -> int:
	if MatchPhase.is_combatant(set_winner):
		if _victory_played:
			return CLASS_NONE
		return CLASS_VICTORY
	var finish := false
	var critical := false
	var parry := false
	for event: DuelEvent in events:
		match event.type:
			DuelEventTypes.FIGHTER_KILLED, DuelEventTypes.RING_OUT:
				finish = true
			DuelEventTypes.CRITICAL_HIT:
				critical = true
			DuelEventTypes.PARRY:
				if _parry_quality(event) >= CLEAN_PARRY_QUALITY:
					parry = true
	if finish:
		return CLASS_FINISH
	if critical:
		return CLASS_CRITICAL
	if parry:
		return CLASS_PARRY
	if rising:
		return CLASS_SETPOINT
	return CLASS_NONE


func _parry_quality(event: DuelEvent) -> float:
	return clampf(event.number(DuelEventKeys.MARGIN) / CombatFeedbackDirector.PARRY_QUALITY_CEIL, 0.0, 1.0)


func _apply_intensity(klass: int, events: Array[DuelEvent], tuning: CombatTuning) -> void:
	if klass == CLASS_NONE:
		var decayed := excitement * DECAY
		excitement = minf(maxf(decayed, _ambient_level(events, tuning)), 1.0)
		_run = CLASS_NONE
		return
	if klass == _run:
		return
	_run = klass
	excitement = minf(excitement + _step(klass), 1.0)


## One level for the tick: the hardest body reading, the hardest steel
## reading, or a committed whiff. Not a sum, and not impulse.
func _ambient_level(events: Array[DuelEvent], tuning: CombatTuning) -> float:
	var level := 0.0
	for event: DuelEvent in events:
		match event.type:
			DuelEventTypes.BODY_HIT:
				level = maxf(level, _body_level(event, tuning))
			DuelEventTypes.BLADE_CONTACT:
				level = maxf(level, _blade_level(event))
			DuelEventTypes.ATTACK_WHIFFED:
				if _committed(event):
					level = maxf(level, WHIFF_LEVEL)
	return level


func _body_level(event: DuelEvent, tuning: CombatTuning) -> float:
	if tuning == null or event.text(DuelEventKeys.CONTACT_KIND) == GRAZE_KIND:
		return 0.0
	var reading := ImpactFeedback.from_event(event, tuning).severity01
	if reading >= HEAVY_SEVERITY:
		return reading * HEAVY_LEVEL
	return reading * BODY_LEVEL


func _blade_level(event: DuelEvent) -> float:
	var intensity := clampf(event.number(DuelEventKeys.INTENSITY), 0.0, 1.0)
	var band := event.text(DuelEventKeys.CONTACT_CLASS)
	if band == String(ContactResolver.CLASS_STRONG):
		return intensity * STRONG_LEVEL
	if band == String(ContactResolver.CLASS_SOLID):
		return intensity * SOLID_LEVEL
	return 0.0


func _committed(event: DuelEvent) -> bool:
	return event.number(DuelEventKeys.CHARGE) >= WHIFF_COMMITTED_CHARGE


func _in_measure(event: DuelEvent, distance: float, reach: PackedFloat32Array) -> bool:
	var span := _reach_of(event, reach)
	return span > 0.0 and distance <= span


func _reach_of(event: DuelEvent, reach: PackedFloat32Array) -> float:
	if event.actor < 0 or event.actor >= reach.size():
		return 0.0
	return reach[event.actor]


func _step(klass: int) -> float:
	match klass:
		CLASS_SETPOINT:
			return STEP_SETPOINT
		CLASS_PARRY:
			return STEP_PARRY
		CLASS_CRITICAL:
			return STEP_CRITICAL
		CLASS_FINISH:
			return STEP_FINISH
		CLASS_VICTORY:
			return STEP_VICTORY
		_:
			return 0.0


func _select_shot(klass: int, events: Array[DuelEvent], scores: PackedInt32Array, distance: float, reach: PackedFloat32Array) -> StringName:
	if klass == CLASS_VICTORY:
		if _victory_played:
			return &""
		_victory_played = true
		_hold()
		return CUE_VICTORY
	if klass == CLASS_FINISH:
		if _same_scores(scores, _finish_scores):
			return &""
		_finish_scores = scores.duplicate()
		_hold()
		return CUE_STRONG
	if klass == CLASS_NONE:
		if cooldown == 0 and _gasp(events, distance, reach):
			_hold()
			return CUE_GASP
		return &""
	if cooldown > 0:
		return &""
	if klass == CLASS_CRITICAL or klass == CLASS_PARRY:
		_hold()
		return CUE_CHEER
	if klass == CLASS_SETPOINT:
		_hold()
		return CUE_SETPOINT
	return &""


## A committed in-measure miss, and not on a tick that already struck a body.
func _gasp(events: Array[DuelEvent], distance: float, reach: PackedFloat32Array) -> bool:
	var struck := false
	var missed := false
	for event: DuelEvent in events:
		if event.type == DuelEventTypes.BODY_HIT:
			struck = true
		elif event.type == DuelEventTypes.ATTACK_WHIFFED and _committed(event) and _in_measure(event, distance, reach):
			missed = true
	return missed and not struck


func _hold() -> void:
	cooldown = COOLDOWN_TICKS


func _same_scores(left: PackedInt32Array, right: PackedInt32Array) -> bool:
	if left.size() != right.size() or left.is_empty():
		return false
	for i in left.size():
		if left[i] != right[i]:
			return false
	return true
