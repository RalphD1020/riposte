class_name DuelFixture
extends RefCounted

## Test-only builders for duel states and canonical command sequences.
##
## See also: /docs/reference/testing.md


static func rules() -> DuelRules:
	return StandardDuelRules.create()


static func state(duel_rules: DuelRules, seed_value: int = 1) -> MatchState:
	return DuelSetup.new_state(duel_rules, seed_value)


static func place(fighter: FighterState, x: float, y: float, facing: float) -> void:
	fighter.x = x
	fighter.y = y
	fighter.vx = 0.0
	fighter.vy = 0.0
	fighter.facing = facing
	fighter.turn_rate = 0.0


## Put a weapon into a striking phase with a given charge and refresh K.
static func commit(fighter: FighterState, phase: CombatPhase.Id, charge: float, weapon: WeaponDefinition) -> void:
	fighter.weapon.phase = phase
	fighter.weapon.swing_charge = charge
	fighter.weapon.charge = charge
	fighter.weapon.commitment = CommitmentModel.commitment(fighter.weapon, weapon)


static func steady_speed(fighter: FighterState, input_x: float, input_y: float, definition: FighterDefinition, ticks: int) -> float:
	for _i in ticks:
		MovementSystem.step(fighter, input_x, input_y, definition)
	return fighter.speed()


## Events of one type, in order. The single event filter for every helper.
static func of_type(events: Array[DuelEvent], type: StringName) -> Array[DuelEvent]:
	var matches: Array[DuelEvent] = []
	for event in events:
		if event.type == type:
			matches.append(event)
	return matches
