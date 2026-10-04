class_name TrainingDummyController
extends FighterController

## Training partner: holds its ground and answers with a slow quick cut when
## the player is inside reach, so blades can meet (UX §57 "BLADES ARE
## PHYSICAL"). Never charges, never moves.
##
## See also: /docs/concepts/ux.md

const ATTACK_INTERVAL_TICKS := 90

var _rules: DuelRules
var _cooldown: int = ATTACK_INTERVAL_TICKS


static func create(rules: DuelRules) -> TrainingDummyController:
	var controller := TrainingDummyController.new()
	controller._rules = rules
	return controller


func command_for(state: MatchState, slot: int) -> PlayerCommand:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		_cooldown = ATTACK_INTERVAL_TICKS
		return PlayerCommand.idle(state.tick)
	_cooldown -= 1
	var me := state.fighter(slot)
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	if _cooldown <= 0 and DuelGeometry.distance(me, state.opponent_of(slot)) <= reach and WeaponSystem.can_start_attack(me, _rules.weapon):
		_cooldown = ATTACK_INTERVAL_TICKS
		return PlayerCommand.create(state.tick, 0.0, 0.0, true, true)
	return PlayerCommand.idle(state.tick)
