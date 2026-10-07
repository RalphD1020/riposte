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


## Kill a fighter the way a lethal strike does: health to zero *and* the
## weapon into DEAD. Zeroing health alone is an impossible authoritative state
## that StateInvariants rejects, so tests must not take that shortcut.
static func kill(fighter: FighterState) -> void:
	fighter.health = 0.0
	fighter.stamina = 0.0
	WeaponSystem.kill(fighter, 0.0)


## Put a weapon into a striking phase with a given charge and refresh K.
static func commit(fighter: FighterState, phase: CombatPhase.Id, charge: float, weapon: WeaponDefinition) -> void:
	fighter.weapon.phase = phase
	fighter.weapon.swing_charge = charge
	fighter.weapon.charge = charge
	fighter.weapon.commitment = CommitmentModel.commitment(fighter.weapon, weapon)


## How far ahead the stand-in opponent holds its measure. Any distance works;
## it only has to be non-zero so the duel axis is well defined.
const PARTNER_MEASURE := 3.0


## One tick of footwork against a stand-in opponent holding its measure dead
## ahead along +X. Footwork is duel-relative (MOVE-001), so this is what
## pins duel forward `(0, 1)` to world `+X` and lets single-fighter movement
## expectations stay closed-form.
static func spar(fighter: FighterState, input_x: float, input_y: float, definition: FighterDefinition, tick: int = 0) -> void:
	var partner := FighterState.new()
	partner.slot = 1 - fighter.slot
	place(partner, fighter.x + PARTNER_MEASURE, fighter.y, fighter.facing + PI)
	MovementSystem.step(fighter, partner, input_x, input_y, tick, definition)


static func steady_speed(fighter: FighterState, input_x: float, input_y: float, definition: FighterDefinition, ticks: int) -> float:
	for tick in ticks:
		spar(fighter, input_x, input_y, definition, tick)
	return fighter.speed()


## Events of one type, in order. The single event filter for every helper.
static func of_type(events: Array[DuelEvent], type: StringName) -> Array[DuelEvent]:
	var matches: Array[DuelEvent] = []
	for event in events:
		if event.type == type:
			matches.append(event)
	return matches
