extends TestCase

## CONTACT: collisions change both combat states (COMBAT §40–§45, §55–§59).
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "CONTACT"
	_rules = DuelFixture.rules()


## A heavy swing along +X meets a parallel guard lying 4.4 cm above it.
func _beat_scene() -> MatchState:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 18.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 2.2, 0.044, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	return state


func test_heavy_swing_beats_through_a_weak_guard() -> void:
	var state := _beat_scene()
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), ContactFixture.start_poses(state), _rules, 1, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade collision")
	assert_eq(contacts[0].text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_STRONG), "strong contact")
	assert_eq(contacts[0].actor, 0, "the swinging fighter is the attacker")
	assert_true(CombatPhase.is_swinging(state.fighter(0).weapon.phase), "momentum carries the heavy swing through")
	assert_true(absf(state.fighter(1).weapon.speed) > _rules.weapon.control_speed, "guard knocked out of control")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.PARRY).size(), 0, "no parry when the attacker wins")
	assert_eq(state.blade_cooldown, _rules.weapon.contact_cooldown_ticks, "contact cooldown armed")


func test_tap_into_a_strong_guard_is_parried() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 9.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	state.fighter(0).stability = 0.6
	ContactFixture.arm(state.fighter(1), 1.5, 0.044, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.15, 0.0, 1.15, 0.044), ContactFixture.start_poses(state), _rules, 1, events)
	var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
	assert_true(bool(contact.data[DuelEventKeys.DEFLECTED_0]), "the tap is deflected")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.RECOVERY, "attacker must recover")
	var parries := DuelFixture.of_type(events, DuelEventTypes.PARRY)
	assert_eq(parries.size(), 1, "the strong guard parries")
	assert_eq(parries[0].actor, 1, "defender is credited")
	assert_true(parries[0].number(DuelEventKeys.MARGIN) >= _rules.combat.parry_margin_seconds, "defender threatens first by the margin")


func test_separating_blades_do_not_collide() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = -9.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), ContactFixture.start_poses(state), _rules, 1, events)
	assert_eq(events.size(), 0, "blades moving apart exchange nothing")
	assert_eq(state.blade_cooldown, 0, "no cooldown without an impact")


func test_low_energy_contact_binds_and_the_planted_fighter_wins() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	state.fighter(1).stability = 0.5
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), ContactFixture.start_poses(state), _rules, 1, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BIND_STARTED).size(), 1, "slow contact binds")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.BIND, "fighter 0 bound")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.BIND, "fighter 1 bound")
	for tick in range(2, 2 + _rules.weapon.bind_ticks):
		ContactResolver.update_bind(state, _rules, tick, events)
	var ended := DuelFixture.of_type(events, DuelEventTypes.BIND_ENDED)
	assert_eq(ended.size(), 1, "bind resolves")
	assert_eq(ended[0].actor, 0, "planted fighter wins the bind")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.NEUTRAL, "winner free")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.RECOVERY, "loser recovers")


func test_bind_breaks_when_fighters_disengage() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), ContactFixture.start_poses(state), _rules, 1, events)
	state.fighter(1).x += 3.0
	ContactResolver.update_bind(state, _rules, 2, events)
	var ended := DuelFixture.of_type(events, DuelEventTypes.BIND_ENDED)
	assert_eq(ended.size(), 1, "stepping away ends the bind")
	assert_eq(ended[0].text(DuelEventKeys.REASON), String(ContactResolver.REASON_DISENGAGED), "disengage reason")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.NEUTRAL, "both free")


func test_body_hit_applies_damage_and_knockback() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), ContactFixture.start_poses(state), _rules, 1, events)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_eq(hits.size(), 1, "body hit reported")
	assert_true(hits[0].number(DuelEventKeys.DAMAGE) > 0.0, "damage dealt")
	assert_near(state.fighter(1).health, 100.0 - hits[0].number(DuelEventKeys.DAMAGE), 1e-9, "health reduced by the damage")
	assert_true(state.fighter(1).vy > 0.0, "knocked back along the strike normal")
	assert_true(state.fighter(0).weapon.swing_hit, "swing marked as landed")


func test_true_double_hit_damages_both() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, PI, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	var report := ContactFixture.body_report(0, 0.9, 0.0)
	report.body[1] = true
	report.body_x[1] = 0.0
	report.body_y[1] = 0.27
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, ContactFixture.start_poses(state), _rules, 1, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 2, "both hits land")
	assert_true(state.fighter(0).health < 100.0 and state.fighter(1).health < 100.0, "both hurt")


func test_lethal_hit_kills() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 15.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	state.fighter(1).health = 5.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), ContactFixture.start_poses(state), _rules, 1, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.FIGHTER_KILLED).size(), 1, "kill reported")
	assert_eq(state.fighter(1).health, 0.0, "health floors at zero")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.DEAD, "target is dead")


func test_strong_hit_staggers_the_target() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 10.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.CHARGING, 0.5, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), ContactFixture.start_poses(state), _rules, 1, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.STAGGERED).size(), 1, "stagger reported")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.STAGGER, "charge interrupted by stagger")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.OVERSWING, "a clean hit ends the attacker's drive")
