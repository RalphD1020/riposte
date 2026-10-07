class_name TutorialTracker
extends RefCounted

## Demonstrated, not explained (UX §57): MOVE → QUICK CUT → CHARGE → RELEASE
## → BLADES ARE PHYSICAL → SWEET SPOT → MOMENTUM. Each step completes from
## what the player actually did in the simulation; the HUD maps steps to copy.
##
## The last two steps teach the physics the first five let you feel, and both
## are checked against quantities the strike itself carried (COMBAT-009). That
## matters more than it sounds: a lesson scored on its own idea of a good hit
## could pass a player for something the game does not reward, which is worse
## than no lesson. No equation is ever shown — a drill is passed by doing the
## thing, and the only feedback is the hit.
##
## See also: /docs/concepts/ux.md, /docs/concepts/combat.md

enum Step { MOVE, QUICK_CUT, CHARGE, RELEASE, BLADES, SWEET_SPOT, MOMENTUM, COMPLETE }

const MOVE_DISTANCE := 1.0
const CHARGE_TARGET := 0.5

## How much harder one hit has to be than another before the player has
## demonstrably *felt* the difference rather than scattered.
##
## A ratio between their own two hits, not an absolute speed: the contrast is
## the lesson, and an absolute threshold would be a different test for a fast
## fighter than a slow one.
const MOMENTUM_CONTRAST := 1.6

var step: Step = Step.MOVE
var _slot: int = 0
var _travel: float = 0.0
var _last_x: float = 0.0
var _last_y: float = 0.0
var _tracking: bool = false
var _softest: float = 0.0
var _hardest: float = 0.0


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
		Step.SWEET_SPOT:
			## Where on the blade, and nothing else. Not the damage and not
			## the grade: a thin hit from a huge swing can out-damage a
			## perfect one from a small swing, and passing the player for that
			## would teach them to wind up instead of to aim.
			for event in events:
				if event.type == DuelEventTypes.BODY_HIT and event.actor == _slot:
					if SwingSemantics.in_sweet_region(event.number(DuelEventKeys.BLADE_FRACTION)):
						return _advance_if(true)
		Step.MOMENTUM:
			for event in events:
				if event.type != DuelEventTypes.BODY_HIT or event.actor != _slot:
					continue
				var closing := event.number(DuelEventKeys.CLOSING_SPEED)
				if closing <= 0.0:
					continue
				_hardest = maxf(_hardest, closing)
				_softest = closing if _softest <= 0.0 else minf(_softest, closing)
			return _advance_if(_softest > 0.0 and _hardest >= _softest * MOMENTUM_CONTRAST)
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
