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
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade collision")
	assert_eq(contacts[0].text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_STRONG), "strong contact")
	assert_eq(contacts[0].actor, 0, "the swinging fighter is the attacker")
	assert_true(CombatPhase.is_swinging(state.fighter(0).weapon.phase), "momentum carries the heavy swing through")
	assert_true(absf(state.fighter(1).weapon.speed) > _rules.weapon.control_speed, "guard knocked out of control")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.PARRY).size(), 0, "no parry when the attacker wins")


## Contact geometry travels with the contact. Feedback has to be directional,
## and the only honest source for the direction is the resolver that computed
## it — a consumer rebuilding it from fighter positions would quietly disagree
## with the impulse that was actually applied (COMBAT-009).
func test_a_blade_contact_carries_its_own_geometry() -> void:
	var state := _beat_scene()
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
	var normal := SimMath.length(contact.number(DuelEventKeys.NORMAL_X), contact.number(DuelEventKeys.NORMAL_Y))
	assert_near(normal, 1.0, 1e-9, "the collision normal arrives as a unit vector")
	var strike := SimMath.length(contact.number(DuelEventKeys.STRIKE_X), contact.number(DuelEventKeys.STRIKE_Y))
	assert_near(strike, 1.0, 1e-9, "so does the striking point's direction of travel")
	## A bounded reading rather than a class name, so feedback can be a curve.
	var intensity := contact.number(DuelEventKeys.INTENSITY)
	assert_between(intensity, 0.0, 1.0, "intensity is a fraction")
	assert_eq(intensity, SwingSemantics.clash_intensity(contact.number(DuelEventKeys.CLOSING_SPEED), _rules.combat), "of the closing speed that counts as a full deflection")
	assert_eq(contact.text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_STRONG), "and the class is still there for audio")


func test_tap_into_a_strong_guard_is_parried() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 9.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	state.fighter(0).stability = 0.6
	ContactFixture.arm(state.fighter(1), 1.5, 0.044, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.15, 0.0, 1.15, 0.044), _rules, 1, 0.0, events)
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
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	assert_eq(events.size(), 0, "blades moving apart exchange nothing")
	assert_eq(state.blade_contact.phase, ContactPairState.Phase.SEPARATED, "and never enter a contact")


func test_low_energy_contact_binds_and_the_planted_fighter_wins() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	state.fighter(1).stability = 0.5
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BIND_STARTED).size(), 1, "slow contact binds")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.BIND, "fighter 0 bound")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.BIND, "fighter 1 bound")
	assert_true(state.blade_contact.is_bound(), "and the pair records the bind")
	for tick in range(2, 2 + _rules.weapon.bind_ticks):
		ContactResolver.update_bind(state, _rules, tick, events)
	var ended := DuelFixture.of_type(events, DuelEventTypes.BIND_ENDED)
	assert_eq(ended.size(), 1, "bind resolves")
	assert_eq(ended[0].actor, 0, "planted fighter wins the bind")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.NEUTRAL, "winner free")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.RECOVERY, "loser recovers")
	assert_eq(state.blade_contact.phase, ContactPairState.Phase.SEPARATING, "and the pair is coming apart")


func test_a_bind_can_never_become_unrecoverable() -> void:
	## COMBAT §45. The authored duration normally ends a bind, so the escape
	## bound only matters if that counter is wrong. Perturb exactly that: give
	## both fighters a bind that would outlast the match.
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	for slot in 2:
		state.fighter(slot).weapon.bind_left = 100000
	var escape := _rules.combat.bind_escape_ticks
	for tick in range(2, 2 + escape):
		state.blade_contact.tick()
		ContactResolver.update_bind(state, _rules, tick, events)
	var ended := DuelFixture.of_type(events, DuelEventTypes.BIND_ENDED)
	assert_eq(ended.size(), 1, "the escape bound frees the pair anyway")
	assert_eq(ended[0].text(DuelEventKeys.REASON), String(ContactResolver.REASON_ESCAPED), "reported as an escape")
	assert_eq(ended[0].actor, DuelEvent.NONE, "a fail-safe picks no winner")
	for slot in 2:
		assert_eq(state.fighter(slot).weapon.phase, CombatPhase.Id.NEUTRAL, "both fighters are free")
	assert_eq(StateInvariants.check(state, _rules), StateInvariants.OK, "so the stuck-pair invariant never trips")


func test_bind_breaks_when_fighters_disengage() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	state.fighter(1).x += 3.0
	ContactResolver.update_bind(state, _rules, 2, events)
	var ended := DuelFixture.of_type(events, DuelEventTypes.BIND_ENDED)
	assert_eq(ended.size(), 1, "stepping away ends the bind")
	assert_eq(ended[0].text(DuelEventKeys.REASON), String(ContactResolver.REASON_DISENGAGED), "disengage reason")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.NEUTRAL, "both free")


## One live tick with the attacker mid-swing at `attacker_angle` and the
## defender standing off the attacker's arc holding their blade at
## `guard_angle`. Returns the events that tick produced.
func _one_live_tick(attacker_angle: float, speed: float, guard_angle: float) -> Array[DuelEvent]:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var state := runner.state
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, attacker_angle, speed, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	var dx := SimMath.cosine(deg_to_rad(-40.0))
	var dy := SimMath.sine(deg_to_rad(-40.0))
	ContactFixture.arm(state.fighter(1), dx, dy, atan2(-dy, -dx), guard_angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var idle := PlayerCommand.idle(state.tick)
	return runner.simulation.step(state, idle, idle)


func test_an_intercepted_swing_never_reaches_the_body_behind_it() -> void:
	## The whole reason the tick is walked chronologically (COMBAT §43): a
	## blade clash early in the tick has to change whether the cut later in
	## that same tick exists at all. Enumerating both from the start poses and
	## sorting them would award a hit the parry already prevented.
	##
	## Same attacker, same swing, same tick. Only the defender's blade moves.
	var unguarded := _one_live_tick(deg_to_rad(-90.0), 60.0, deg_to_rad(-85.0))
	assert_eq(DuelFixture.of_type(unguarded, DuelEventTypes.BLADE_CONTACT).size(), 0, "precondition: nothing intercepts the lowered guard")
	assert_eq(DuelFixture.of_type(unguarded, DuelEventTypes.BODY_HIT).size(), 1, "precondition: the swing does reach the body")
	var guarded := _one_live_tick(deg_to_rad(-90.0), 60.0, deg_to_rad(85.0))
	assert_eq(DuelFixture.of_type(guarded, DuelEventTypes.BLADE_CONTACT).size(), 1, "the raised guard is met first")
	assert_eq(DuelFixture.of_type(guarded, DuelEventTypes.BODY_HIT).size(), 0, "and the cut behind it never happens")


func test_body_hit_applies_damage_and_knockback() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_eq(hits.size(), 1, "body hit reported")
	assert_true(hits[0].number(DuelEventKeys.DAMAGE) > 0.0, "damage dealt")
	assert_near(state.fighter(1).health, 100.0 - hits[0].number(DuelEventKeys.DAMAGE), 1e-9, "health reduced by the damage")
	assert_true(state.fighter(1).vy > 0.0, "knocked back along the strike normal")
	## The displacement that happened, carried, so recoil can be shown at
	## exactly that scale and never beyond it.
	assert_near(hits[0].number(DuelEventKeys.NORMAL_Y), 1.0, 1e-9, "the push direction is on the payload")
	assert_near(
		state.fighter(1).vy,
		hits[0].number(DuelEventKeys.PUSH) * hits[0].number(DuelEventKeys.NORMAL_Y),
		1e-9,
		"and the push is the velocity change actually applied"
	)


func test_displacement_is_impulse_over_resisting_mass() -> void:
	## PHYS-004. There is no knockback constant and no exposure term: the
	## target is shoved by exactly the momentum that arrived, divided by the
	## mass they braced with. Otherwise a badly positioned fighter would be
	## launched by their own bad positioning.
	var composed := DuelFixture.state(_rules)
	ContactFixture.arm(composed.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(composed.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var helpless := DuelFixture.state(_rules)
	ContactFixture.arm(helpless.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(helpless.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	## Captured before the hit lands, because resistance is a property of how
	## the target was standing, not of how they end up moving.
	var braced := StructuralCoupling.resisting_mass(composed.fighter(1), _rules.fighter, _rules.combat)
	var calm_events: Array[DuelEvent] = []
	ContactResolver.resolve(composed, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, calm_events)
	var exposed_events: Array[DuelEvent] = []
	ContactResolver.resolve(helpless, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, exposed_events)
	var calm := DuelFixture.of_type(calm_events, DuelEventTypes.BODY_HIT)[0]
	var exposed := DuelFixture.of_type(exposed_events, DuelEventTypes.BODY_HIT)[0]
	assert_true(exposed.number(DuelEventKeys.EXPOSURE) > calm.number(DuelEventKeys.EXPOSURE), "precondition: one target is far worse positioned")
	assert_true(exposed.number(DuelEventKeys.DAMAGE) > calm.number(DuelEventKeys.DAMAGE), "and is hurt more for it")
	assert_near(composed.fighter(1).vy, calm.number(DuelEventKeys.IMPULSE) / braced * _rules.combat.body_push_feel_scale, 1e-9, "displacement is J / m × feel scale")
	assert_near(helpless.fighter(1).vy, composed.fighter(1).vy, 1e-9, "and exposure adds none of it")


func test_stagger_is_decided_by_impulse_not_by_damage() -> void:
	## PHYS-004. Being knocked off balance is a momentum event. A fast cut
	## that hurts badly need not unbalance anyone, and the threshold the
	## resolver reads is impulse-derived.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	assert_near(
		strike.stagger_pressure,
		strike.impact.normalized_impulse(_rules.combat) * strike.exposure,
		1e-12,
		"stagger pressure is normalized impulse scaled by susceptibility"
	)
	assert_true(strike.damage > 0.0, "precondition: the cut does real damage")
	assert_true(strike.stagger_pressure < _rules.weapon.stagger_impulse, "precondition: but not enough momentum to unbalance a composed fighter")
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.STAGGERED).size(), 0, "so a damaging cut alone does not stagger")


func test_true_double_hit_damages_both() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, PI, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	var report := ContactFixture.body_report(0, 0.9, 0.0)
	report.body[1] = true
	report.body_x[1] = 0.0
	report.body_y[1] = 0.27
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 2, "both hits land")
	assert_true(state.fighter(0).health < 100.0 and state.fighter(1).health < 100.0, "both hurt")


func test_lethal_hit_kills() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 15.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	state.fighter(1).health = 5.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.375, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.FIGHTER_KILLED).size(), 1, "kill reported")
	assert_eq(state.fighter(1).health, 0.0, "health floors at zero")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.DEAD, "target is dead")
	## A trade is decided by arrival order, so the death has to remember the
	## instant the blade got there rather than just the tick it fell in.
	assert_eq(state.fighter(1).lethal_fraction, 0.375, "and the death records when the blade arrived")


func test_strong_hit_staggers_the_target() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 10.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.CHARGING, 0.5, _rules.weapon)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.STAGGERED).size(), 1, "stagger reported")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.STAGGER, "charge interrupted by stagger")
	## PHYS-008: body contact does NOT change attacker weapon state.
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.ACTIVE_THREAT, "attacker weapon phase unchanged by body contact (PHYS-008)")


## --- PHYS-008: conditional weapon/body coupling (sword independence) --------
## Stabbing-angle contacts (point-first entry) penetrate cleanly: the blade
## receives NO reactive impulse. Non-stabbing contacts (transverse slashes,
## oblique impacts) receive an opposite reactive angular impulse. One
## definition, not two: if the geometry qualifies as a point strike (POKE or
## THRUST), the blade also penetrates without reaction.
##
## Implements: /spec/invariants.md#combat-003 (PHYS-008)
## See also: /docs/concepts/combat.md


## Group 1: Stabbing invariants — weapon.speed unchanged through body contact.

func test_poke_does_not_change_weapon_speed() -> void:
	## A walking poke: tip-region contact, sufficient alignment, sufficient
	## incidence. The blade penetrates cleanly — no Δω on the weapon.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 2.0
	a.weapon.swing_dir = 1.0
	a.vx = 5.0
	var speed_before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, _rules.weapon.tip_radius, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 1, "body hit resolved")
	assert_eq(a.weapon.speed, speed_before, "poke: weapon speed unchanged (PHYS-008)")
	assert_true(b.health < _rules.fighter.max_health, "target took damage")
	assert_true(absf(b.vx) > 0.0 or absf(b.vy) > 0.0, "target was pushed")


func test_thrust_does_not_change_weapon_speed() -> void:
	## A forward-dash thrust: all poke criteria plus aligned burst.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 1.5
	a.weapon.swing_dir = 1.0
	a.vx = 8.0
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	var speed_before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, _rules.weapon.tip_radius, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_THRUST).size(), 1, "classified as THRUST")
	assert_eq(a.weapon.speed, speed_before, "thrust: weapon speed unchanged (PHYS-008)")


## Group 2: Non-stabbing reaction — measurable Δω on weapon.speed.

func test_slash_produces_blade_reaction() -> void:
	## A transverse slash: the blade's edge leads, contact is mid-blade
	## (not tip region). The weapon receives a reactive angular impulse.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var speed_before := state.fighter(0).weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.45, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 1, "body hit")
	var speed_after := state.fighter(0).weapon.speed
	assert_true(absf(speed_after - speed_before) > 0.01, "slash: weapon speed changed by reactive impulse (PHYS-008)")


func test_charged_slash_has_larger_reaction_than_tap() -> void:
	## A heavier swing (higher commitment, more inertia contribution)
	## delivers more force, and the reaction from a heavier target coupling
	## is also proportionally larger. However, what matters here is that a
	## stronger swing + same contact produces a measurably different Δω.
	var tap_state := DuelFixture.state(_rules)
	ContactFixture.arm(tap_state.fighter(0), 0.0, 0.0, 0.0, 0.0, 6.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	ContactFixture.arm(tap_state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var tap_speed_before := tap_state.fighter(0).weapon.speed
	var tap_events: Array[DuelEvent] = []
	ContactResolver.resolve(tap_state, ContactFixture.body_report(0, 0.45, 0.0), _rules, 1, 0.0, tap_events)
	var tap_dw := absf(tap_state.fighter(0).weapon.speed - tap_speed_before)
	var charged_state := DuelFixture.state(_rules)
	ContactFixture.arm(charged_state.fighter(0), 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, _rules.weapon)
	ContactFixture.arm(charged_state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var charged_speed_before := charged_state.fighter(0).weapon.speed
	var charged_events: Array[DuelEvent] = []
	ContactResolver.resolve(charged_state, ContactFixture.body_report(0, 0.45, 0.0), _rules, 1, 0.0, charged_events)
	var charged_dw := absf(charged_state.fighter(0).weapon.speed - charged_speed_before)
	assert_true(tap_dw > 0.0, "tap has measurable reaction")
	assert_true(charged_dw > 0.0, "charged has measurable reaction")
	assert_true(charged_dw > tap_dw, "charged slash produces larger blade reaction (PHYS-008)")


func test_oblique_tip_below_thresholds_gets_both_reaction_and_push() -> void:
	## Tip-region contact but below alignment/incidence thresholds: not a
	## point strike, so the blade reacts AND the target is pushed.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, deg_to_rad(70.0))
	DuelFixture.place(b, 0.9, 0.27, -PI / 2.0, )
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 10.0
	a.weapon.swing_dir = 1.0
	DuelFixture.commit(a, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	var speed_before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.85, 0.0), _rules, 1, 0.0, events)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_eq(hits.size(), 1, "body hit")
	var strike := DamageModel.evaluate(a, b, 0.85, 0.0, _rules)
	assert_false(strike.is_stabbing, "precondition: oblique geometry is not stabbing")
	assert_true(absf(state.fighter(0).weapon.speed - speed_before) > 0.001, "blade reacted (non-stabbing)")
	assert_true(b.health < _rules.fighter.max_health, "target took damage")


## Group 3: Weapon-body lifecycle — one damage on entry, nothing inside.

func test_weapon_body_lifecycle_no_repeat_damage_inside() -> void:
	## COMBAT-007 / PHYS-008: WeaponBodyContact lifecycle gates re-entry.
	## The collision system (not the resolver) tracks OUTSIDE → ENTERED →
	## INSIDE → EXITED → OUTSIDE. A penetrating sword that stays inside the
	## body volume does not deal repeated damage. Test through the full
	## simulation path since lifecycle is a CollisionSystem concern.
	var runner := SimRunner.create(_rules, 20)
	runner.skip_intro()
	var state := runner.state
	## Position fighters close enough that a swing will hit, with attacker
	## already in a swinging phase.
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-80.0), 50.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, _rules.weapon)
	ContactFixture.arm(state.fighter(1), _rules.weapon.tip_radius * 0.9, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	var initial_health := state.fighter(1).health
	var idle := PlayerCommand.idle(state.tick)
	var total_hits := 0
	var first_hit_tick := -1
	for tick in 15:
		var events := runner.simulation.step(state, idle, idle)
		var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
		total_hits += hits.size()
		if hits.size() > 0 and first_hit_tick < 0:
			first_hit_tick = state.tick
	assert_true(first_hit_tick >= 0, "precondition: the swing connected")
	assert_true(state.fighter(1).health < initial_health, "damage was dealt")
	## The key invariant: only ONE hit from a single swing passage through
	## the body, even though the blade was inside for multiple ticks.
	assert_eq(total_hits, 1, "lifecycle: exactly one body hit per entry (COMBAT-007)")
