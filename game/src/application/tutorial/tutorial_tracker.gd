class_name TutorialTracker
extends RefCounted

## Demonstrated, not explained (UX §57): MOVE → QUICK CUT → CHARGE → RELEASE
## → BLADES ARE PHYSICAL. Each step completes from what the player actually
## did in the simulation; the HUD maps steps to copy.
##
## See also: /docs/concepts/ux.md

enum Step { MOVE, QUICK_CUT, CHARGE, RELEASE, BLADES, COMPLETE }

const MOVE_DISTANCE := 1.0
const CHARGE_TARGET := 0.5

var step: Step = Step.MOVE
var _slot: int = 0
var _travel: float = 0.0
var _last_x: float = 0.0
var _last_y: float = 0.0
var _tracking: bool = false


static func create(slot: int) -> TutorialTracker:
	var tracker := TutorialTracker.new()
	tracker._slot = slot
	return tracker


func is_complete() -> bool:
	return step == Step.COMPLETE


## Returns true when this tick completed a step.
func observe(state: MatchState, events: Array[DuelEvent]) -> bool:
	if is_complete() or state.phase != MatchPhase.Id.ROUND_ACTIVE:
		_tracking = false
		return false
	var me := state.fighter(_slot)
	match step:
		Step.MOVE:
			if _tracking:
				_travel += SimMath.length(me.x - _last_x, me.y - _last_y)
			_last_x = me.x
			_last_y = me.y
			_tracking = true
			return _advance_if(_travel >= MOVE_DISTANCE)
		Step.QUICK_CUT:
			return _advance_if(_released_with(events, func(charge: float) -> bool: return charge == 0.0))
		Step.CHARGE:
			return _advance_if(me.weapon.phase == CombatPhase.Id.CHARGING and me.weapon.charge >= CHARGE_TARGET)
		Step.RELEASE:
			return _advance_if(_released_with(events, func(charge: float) -> bool: return charge >= CHARGE_TARGET))
		Step.BLADES:
			for event in events:
				if event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BIND_STARTED:
					return _advance_if(true)
	return false


func _released_with(events: Array[DuelEvent], accepts: Callable) -> bool:
	for event in events:
		if event.type == DuelEventTypes.ATTACK_RELEASED and event.actor == _slot and accepts.call(event.number(DuelEventKeys.CHARGE)):
			return true
	return false


func _advance_if(done: bool) -> bool:
	if done:
		step = (step + 1) as Step
	return done
