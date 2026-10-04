class_name WeaponRig
extends RefCounted

## Test-only driver for one fighter's weapon with scripted attack edges. The
## opponent stands far away and still, so only the input language and motor
## are exercised.
##
## See also: /docs/reference/testing.md

var rules: DuelRules
var fighter: FighterState
var opponent: FighterState
var tick: int = 0
var events: Array[DuelEvent] = []
var phases: Array[CombatPhase.Id] = []
var angles: PackedFloat64Array = PackedFloat64Array()


static func create(duel_rules: DuelRules) -> WeaponRig:
	var rig := WeaponRig.new()
	rig.rules = duel_rules
	rig.fighter = FighterState.new()
	rig.fighter.slot = 0
	rig.fighter.health = duel_rules.fighter.max_health
	rig.fighter.weapon.reset(-duel_rules.weapon.guard_angle)
	rig.opponent = FighterState.new()
	rig.opponent.slot = 1
	rig.opponent.health = duel_rules.fighter.max_health
	DuelFixture.place(rig.opponent, 10.0, 0.0, PI)
	return rig


func step(pressed: bool = false, released: bool = false, cancel: bool = false) -> void:
	var command := PlayerCommand.create(tick, 0.0, 0.0, pressed, released, cancel)
	WeaponSystem.apply_input(fighter, command, rules, tick, events)
	WeaponSystem.step(fighter, opponent, rules, tick, events)
	phases.append(fighter.weapon.phase)
	angles.append(fighter.weapon.angle)
	tick += 1


func press() -> void:
	step(true)


func release() -> void:
	step(false, true)


func hold(ticks: int) -> void:
	for _i in ticks:
		step()


## Press, hold `hold_ticks` total ticks since the press, then release.
func attack(hold_ticks: int) -> void:
	press()
	hold(hold_ticks - 1)
	release()


## Step until the weapon is NEUTRAL again (or the cap); returns ticks used.
func settle(max_ticks: int = 240) -> int:
	var used := 0
	while used < max_ticks and (used == 0 or fighter.weapon.phase != CombatPhase.Id.NEUTRAL):
		step()
		used += 1
	return used


func step_until_phase(phase: CombatPhase.Id, max_ticks: int = 240) -> bool:
	for _i in max_ticks:
		if fighter.weapon.phase == phase:
			return true
		step()
	return fighter.weapon.phase == phase


func events_of(type: StringName) -> Array[DuelEvent]:
	return DuelFixture.of_type(events, type)


## Phase history with consecutive duplicates collapsed, from `from_index`.
func phase_sequence(from_index: int = 0) -> Array[CombatPhase.Id]:
	var sequence: Array[CombatPhase.Id] = []
	for i in range(from_index, phases.size()):
		if sequence.is_empty() or sequence[sequence.size() - 1] != phases[i]:
			sequence.append(phases[i])
	return sequence
