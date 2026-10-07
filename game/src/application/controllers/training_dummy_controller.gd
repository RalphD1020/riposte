class_name TrainingDummyController
extends FighterController

## Training partner. Performs one of a few deliberately legible beats so a
## lesson has something to be a lesson *about* (UX §57, §18A).
##
## Every beat is typed as ordinary `PlayerCommand`s on the same stream a thumb
## uses. The dummy has no privileged access to anything, which is why a
## training round replays like any other round and why a drill cannot teach a
## timing the game does not actually have.
##
## The beats are cadenced on a fixed tick count on purpose. A reactive partner
## is a better sparring opponent and a worse teacher: you cannot learn to
## punish a recovery window you have never seen twice in a row.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/ux.md

## What the partner is currently demonstrating.
enum Beat {
	## Stand and answer in reach, so blades can meet.
	SPAR,
	## A big, slow, fully committed swing on a fixed cadence, thrown whether or
	## not anyone is there. Keep your distance and it hits air; then its
	## recovery is yours. This is the sweet-spot drill: a still target, long
	## enough to choose where on your blade to meet it.
	BIG_SWING,
	## Walk in, walk out, forever, and never attack. The momentum drill: the
	## same cut lands differently into a body coming at you than into one
	## going away.
	PACE,
}

const ATTACK_INTERVAL_TICKS := 90
## Long enough to read the wind-back and step clear of it.
const WINDUP_TICKS := 48
const SWING_PERIOD_TICKS := 110
## Half a period of walking in, half walking out. Slow enough that the
## direction is never in doubt.
const PACE_TICKS := 55

var beat: Beat = Beat.SPAR

var _rules: DuelRules
var _cooldown: int = ATTACK_INTERVAL_TICKS
var _clock: int = 0


static func create(rules: DuelRules) -> TrainingDummyController:
	var controller := TrainingDummyController.new()
	controller._rules = rules
	return controller


func command_for(state: MatchState, slot: int) -> PlayerCommand:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		_cooldown = ATTACK_INTERVAL_TICKS
		_clock = 0
		return PlayerCommand.idle(state.tick)
	_clock += 1
	match beat:
		Beat.BIG_SWING:
			return _big_swing(state, slot)
		Beat.PACE:
			return _pace(state)
	return _spar(state, slot)


func _spar(state: MatchState, slot: int) -> PlayerCommand:
	_cooldown -= 1
	var me := state.fighter(slot)
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	if _cooldown <= 0 and DuelGeometry.distance(me, state.opponent_of(slot)) <= reach and WeaponSystem.can_start_attack(me, _rules.weapon):
		_cooldown = ATTACK_INTERVAL_TICKS
		return PlayerCommand.create(state.tick, 0.0, 0.0, true, true)
	return PlayerCommand.idle(state.tick)


## Hold for `WINDUP_TICKS`, let go, then stand through the recovery. The press
## and the release are single-tick edges, exactly as a thumb produces them;
## the charge in between is the simulation's, earned from the blade actually
## travelling backwards (PHYS-002).
func _big_swing(state: MatchState, slot: int) -> PlayerCommand:
	var step := _clock % SWING_PERIOD_TICKS
	if step == 1 and WeaponSystem.can_start_attack(state.fighter(slot), _rules.weapon):
		return PlayerCommand.create(state.tick, 0.0, 0.0, true, false)
	if step == WINDUP_TICKS:
		return PlayerCommand.create(state.tick, 0.0, 0.0, false, true)
	return PlayerCommand.idle(state.tick)


## `+y` closes on the opponent, so this is simply forward then back.
func _pace(state: MatchState) -> PlayerCommand:
	var closing := 1.0 if (_clock - 1) % (PACE_TICKS * 2) < PACE_TICKS else -1.0
	return PlayerCommand.create(state.tick, 0.0, closing)
