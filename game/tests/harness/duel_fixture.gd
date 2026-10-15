class_name DuelFixture
extends RefCounted

## Test-only builders for duel states and canonical command sequences.
##
## See also: /docs/reference/testing.md


## The standard rules as a mirror match whose two slots hold the *same*
## `CombatantPhysicsSpec` instance, so a mechanism test that perturbs the
## loadout (`combatant(0)`) perturbs both fighters, as a mirror match should.
## Production compiles each slot on its own; heterogeneous tests build their
## own pair (`with_loadouts`).
static func rules() -> DuelRules:
	return mirror(StandardDuelRules.create())


## `duel_rules` with slot 1 holding slot 0's spec instance.
static func mirror(duel_rules: DuelRules) -> DuelRules:
	duel_rules.combatants[1] = duel_rules.combatants[0]
	return duel_rules


## The standard arena and format with two given loadouts, one per slot.
static func with_loadouts(first: CombatantPhysicsSpec, second: CombatantPhysicsSpec) -> DuelRules:
	var duel_rules := StandardDuelRules.create()
	duel_rules.combatants = [first, second]
	return duel_rules


## The standard rules with the sword on the fixed, body-centred pivot. For
## tests of a mechanism — the sweep, a contact lifecycle, a stagger threshold,
## a formula — whose hand-built geometry is written in revolute terms; the
## attack manifold itself is proven by KINEMATICS, COLLIDE's curved sweep, the
## golden corpus and the E2E suites (WEAPON-PATH-001).
## The body-centred pivot the hand-built mechanism scenes are written for. Its
## pommel is the wielder's centre, so a guard and handle there would sit inside
## the wielder's own torso: on this pivot the sword is its blade alone (the
## guard root and the grip are proven on the shipped orbit, GRIP).
static func revolute_rules() -> DuelRules:
	var duel_rules := rules()
	duel_rules.combatant(0).handling.attack_path = WeaponAttackPath.fixed_pivot()
	duel_rules.combatant(0).weapon.crossguard_half_span = 0.0
	duel_rules.combatant(0).weapon.handle_radius = 0.0
	return duel_rules


static func state(duel_rules: DuelRules, seed_value: int = 1) -> MatchState:
	return DuelSetup.new_state(duel_rules, seed_value)


## Fighter 0 → fighter 1 on the plane. Two bodies that never swap sides keep
## this pointing the same way from tick to tick, whichever axis they face on.
static func separation(match_state: MatchState) -> Vector2:
	return Vector2(match_state.fighter(1).x - match_state.fighter(0).x, match_state.fighter(1).y - match_state.fighter(0).y)


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
	WeaponSystem.kill(fighter, 0.0)


## Put a weapon into a striking phase with a given charge and refresh K.
static func commit(fighter: FighterState, phase: CombatPhase.Id, charge: float, weapon: WeaponDefinition) -> void:
	fighter.weapon.phase = phase
	fighter.weapon.swing_charge = charge
	fighter.weapon.charge = charge
	fighter.weapon.commitment = CommitmentModel.commitment(fighter.weapon, weapon)


## One tick of footwork in the fighter's own combat frame (MOVEMENT-FRAME-001):
## forward `(0, 1)` is its heading, so a fighter facing +X walks along world
## +X and single-fighter movement expectations stay closed-form.
static func spar(fighter: FighterState, input_x: float, input_y: float, definition: FighterDefinition, tick: int = 0) -> void:
	MovementSystem.step(fighter, input_x, input_y, tick, definition)


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


## Point the fighter's weapon perpendicular to the line toward the opponent so
## its blade geometry does not overlap the opponent's body, so the blade cannot
## interfere with a test about something else.
static func weapon_clear_of(fighter: FighterState, opponent_x: float, opponent_y: float) -> void:
	var dx := opponent_x - fighter.x
	var dy := opponent_y - fighter.y
	var bearing := SimMath.arctan2(dy, dx)
	var local_toward := SimMath.wrap_angle(bearing - fighter.facing)
	fighter.weapon.angle = SimMath.wrap_angle(local_toward + PI * 0.5)
	if absf(fighter.weapon.angle) > deg_to_rad(135.0):
		fighter.weapon.angle = SimMath.wrap_angle(local_toward - PI * 0.5)
