class_name CrowdDirector
extends RefCounted

## Presentation-only audience. It reads events and the set score and names
## one reaction. It does not write combat state. Intensity is a separate
## decaying meter: a class step adds once per run, and a quiet tick takes the
## max of that decay and one heavy wound, strong clash, or committed whiff.
## A second meter, per fighter, can hold a name chant. That slot is not a cue.
## Credits decay once per authority tick, inside `observe`, not on a render
## frame. The floor, the gap, and the two-second hold say "this fighter is
## clearly ahead, and a brief trade does not flip the name." They are not a
## listening result. A finish roar and the set win release the name
## immediately. The roar then owns the hold, so the name does not return
## under it. The set win keeps it down for the rest of this director.
## Ordinary clashes and light wounds do not lift it. A gasp waits on a
## longer cooldown than a class cue; the meter can still move during that
## wait, and playing a shot does not itself raise it. Those levels are
## presentation readings of existing payloads, not a force. A finish punches
## through cheer cooldown once per scoreline. After the set-win shot, later
## ticks with the winner still set are silence so the meter can decay. A new
## MatchScreen constructs a new director.
##
## See also: /docs/concepts/presentation.md

const COOLDOWN_TICKS := 90
## Ordinary vocalizations (a gasp) wait longer than a class cue. Excitement
## may still move during this wait. 360 ticks is 6 seconds, a listening
## start, not a measured ideal.
const ORDINARY_COOLDOWN_TICKS := 360
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
## Ordinary clashes and wounds under half a reference wound do not lift the bed.
const HEAVY_LEVEL := 0.35
const STRONG_LEVEL := 0.22
const WHIFF_LEVEL := 0.15
## A far hold on the shipping rules whiffed at charge 0.81. A tap is 0.
const WHIFF_COMMITTED_CHARGE := 0.5
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
var _ordinary: int = 0
var _run: int = CLASS_NONE
var _at_setpoint: bool = false
## The set-win reaction plays once. The snapshot keeps the winner after that.
var _victory_played: bool = false
## Finish shot already fired for this scoreline. A duplicated kill or ring-out
## at the same scores does not roar again. A new round result may.
var _finish_scores: PackedInt32Array = PackedInt32Array()
## Per-fighter name momentum. The room meter stays `excitement`. A ring-out's
## actor is the fighter who left, so that credit goes to the one still in.
var _momentum := PackedFloat32Array([0.0, 0.0])
var chant_slot: int = -1
var _hold_left: int = 0
## Set on the match-winning cue. Later ticks of this director stay unnamed.
var _name_closed: bool = false
## Same per-tick decay as the room meter. At 60 observes per second, 120
## ticks is two seconds: the minimum a name is protected from ordinary
## trades, and the quiet after a finish before a name may return.
const MOMENTUM_DECAY := 0.985
## A slot is ahead only when it is at least this high and leads by `LEAD_GAP`.
## One critical (0.35) misses the floor. A sustained run can clear it.
const MOMENTUM_FLOOR := 0.55
const LEAD_GAP := 0.2
const CREDIT_CRITICAL := 0.35
const CREDIT_PARRY := 0.2
const CREDIT_HIT := 0.25
const CREDIT_KILL := 0.5
const CREDIT_RING := 0.45
## Once a name starts, a lull this long cannot drop it. 120 ticks is 2 s.
const CHANT_HOLD_TICKS := 120


func observe(events: Array[DuelEvent], scores: PackedInt32Array, rounds_to_win: int, set_winner: int, tuning: CombatTuning = null, distance: float = INF, reach: PackedFloat32Array = PackedFloat32Array()) -> StringName:
	if cooldown > 0:
		cooldown -= 1
	if _ordinary > 0:
		_ordinary -= 1
	var rising := _mark_setpoint(scores, rounds_to_win)
	var klass := _class_of(events, set_winner, rising)
	_apply_intensity(klass, events, tuning)
	_credit(events, tuning)
	var cue := _select_shot(klass, events, scores, distance, reach)
	_update_chant(cue)
	return cue


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
	if tuning == null or event.text(DuelEventKeys.CONTACT_KIND) == StrikeResult.KIND_GRAZE:
		return 0.0
	var reading := ImpactFeedback.from_event(event, tuning).severity01
	if reading >= HEAVY_SEVERITY:
		return reading * HEAVY_LEVEL
	return 0.0


func _blade_level(event: DuelEvent) -> float:
	var intensity := clampf(event.number(DuelEventKeys.INTENSITY), 0.0, 1.0)
	var band := event.text(DuelEventKeys.CONTACT_CLASS)
	if band == String(ContactResolver.CLASS_STRONG):
		return intensity * STRONG_LEVEL
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
		if _ordinary == 0 and cooldown == 0 and _gasp(events, distance, reach):
			_hold_ordinary()
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


func _hold_ordinary() -> void:
	_ordinary = ORDINARY_COOLDOWN_TICKS
	_hold()


func _same_scores(left: PackedInt32Array, right: PackedInt32Array) -> bool:
	if left.size() != right.size() or left.is_empty():
		return false
	for i in left.size():
		if left[i] != right[i]:
			return false
	return true


func momentum_of(slot: int) -> float:
	if slot < 0 or slot >= _momentum.size():
		return 0.0
	return _momentum[slot]


func _credit(events: Array[DuelEvent], tuning: CombatTuning) -> void:
	for slot: int in _momentum.size():
		_momentum[slot] *= MOMENTUM_DECAY
	for event: DuelEvent in events:
		var slot := _credited_slot(event)
		if slot < 0:
			continue
		var amount := _credit_amount(event, tuning)
		if amount <= 0.0:
			continue
		_momentum[slot] = minf(_momentum[slot] + amount, 1.5)


func _credited_slot(event: DuelEvent) -> int:
	if event.type == DuelEventTypes.RING_OUT:
		if event.actor != 0 and event.actor != 1:
			return -1
		return 1 - event.actor
	if event.actor != 0 and event.actor != 1:
		return -1
	return event.actor


func _credit_amount(event: DuelEvent, tuning: CombatTuning) -> float:
	match event.type:
		DuelEventTypes.CRITICAL_HIT:
			return CREDIT_CRITICAL
		DuelEventTypes.PARRY:
			if _parry_quality(event) >= CLEAN_PARRY_QUALITY:
				return CREDIT_PARRY
		DuelEventTypes.BODY_HIT:
			if _body_level(event, tuning) > 0.0:
				return CREDIT_HIT
		DuelEventTypes.FIGHTER_KILLED:
			return CREDIT_KILL
		DuelEventTypes.RING_OUT:
			return CREDIT_RING
	return 0.0


func _update_chant(cue: StringName) -> void:
	if cue == CUE_VICTORY:
		chant_slot = -1
		_hold_left = 0
		_name_closed = true
		return
	if _name_closed:
		return
	## A kill or a ring-out owns the crowd. The name stops now, including
	## inside the hold, and the hold becomes the quiet before it may return.
	if cue == CUE_STRONG:
		chant_slot = -1
		_hold_left = CHANT_HOLD_TICKS
		return
	if _hold_left > 0:
		_hold_left -= 1
		if _hold_left > 0:
			return
	var lead := _qualified_lead()
	if lead < 0:
		chant_slot = -1
		return
	if chant_slot != lead:
		chant_slot = lead
		_hold_left = CHANT_HOLD_TICKS


## The fighter who is clearly ahead, or -1 when the room is quiet or the
## two slots are too close to name either of them. The previous favorite
## does not have to stay strong for the other to qualify.
func _qualified_lead() -> int:
	if excitement < STRONG_LEVEL:
		return -1
	var lead := 0 if _momentum[0] >= _momentum[1] else 1
	var trailing := 1 - lead
	if _momentum[lead] < MOMENTUM_FLOOR:
		return -1
	if _momentum[lead] < _momentum[trailing] + LEAD_GAP:
		return -1
	return lead
