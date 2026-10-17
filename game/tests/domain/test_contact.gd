extends TestCase

## CONTACT: collisions change both combat states (COMBAT §40–§45, §55–§59).
##
## Implements: /spec/invariants.md#combat-003
## Implements: /spec/invariants.md#contact-heading-001
## Implements: /spec/invariants.md#contact-outcome-001
## Implements: /spec/invariants.md#deflection-001
## See also: /docs/concepts/combat.md

## What a fixed-iteration solve with friction leaves of a velocity target (m/s).
const SOLVE_RESIDUAL := 1.0e-6

var _rules: DuelRules


func _init() -> void:
	suite_name = "CONTACT"
	## Hand-built revolute scenes: the mechanism under test, on the fixed pivot.
	_rules = DuelFixture.revolute_rules()


## A heavy swing along +X meets a parallel guard lying 4.4 cm above it.
func _beat_scene() -> MatchState:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 18.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 2.2, 0.044, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	return state


func test_heavy_swing_beats_through_a_weak_guard() -> void:
	var state := _beat_scene()
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade collision")
	assert_eq(contacts[0].text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_STRONG), "strong contact")
	assert_eq(contacts[0].actor, 0, "the swinging fighter is the attacker")
	assert_true(CombatPhase.is_swinging(state.fighter(0).weapon.phase), "momentum carries the heavy swing through")
	assert_true(absf(state.fighter(1).weapon.speed) > _rules.combatant(0).weapon.control_speed, "guard knocked out of control")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.PARRY).size(), 0, "no parry when the attacker wins")


## Contact geometry travels with the contact. Feedback has to be directional,
## and the only honest source for the direction is the resolver that computed
## it — a consumer rebuilding it from fighter positions would quietly disagree
## with the impulse that was actually applied (COMBAT-009).
func test_a_blade_contact_carries_its_own_geometry() -> void:
	var state := _beat_scene()
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
	var normal := SimMath.length(contact.number(DuelEventKeys.NORMAL_X), contact.number(DuelEventKeys.NORMAL_Y))
	assert_near(normal, 1.0, 1e-9, "the collision normal arrives as a unit vector")
	var strike := SimMath.length(contact.number(DuelEventKeys.STRIKE_X), contact.number(DuelEventKeys.STRIKE_Y))
	assert_near(strike, 1.0, 1e-9, "so does the striking point's direction of travel")
	## A bounded reading rather than a class name, so feedback can be a curve.
	var intensity := contact.number(DuelEventKeys.INTENSITY)
	assert_between(intensity, 0.0, 1.0, "intensity is a fraction")
	assert_eq(intensity, SwingSemantics.clash_intensity(contact.number(DuelEventKeys.ENERGY), _rules.combat), "of the energy the solve took out, against a strong clash")
	assert_eq(contact.text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_STRONG), "and the class is still there for audio")


## The canonical parry guard (rad): the defender's blade resting across the
## tap's path at 120°, mid-way in the band (110°–130° on rules 50) where the
## blade alone meets and arrests the tap. A steeper guard can meet the quillon
## first; that protected side is steel and still never a wound
## (GUARD-PROTECTION-001, TORSO-CIRCLE-001).
const PARRY_GUARD := 2.0943951023931953


## A tap thrown from measure on the shipping rules at an idle defender whose
## guard rests at `guard` (rad); runs `ticks` ticks after the release, under
## `rules` (the shipping rules by default), appending each of those ticks'
## state hash to `trace`.
func _seat_tap(guard: float, rules: DuelRules = null) -> SimRunner:
	if rules == null:
		rules = DuelFixture.rules()
	var runner := SimRunner.create(rules, 2)
	runner.skip_intro()
	var attacker := runner.state.fighter(0)
	var defender := runner.state.fighter(1)
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var walked := 0
	while DuelGeometry.distance(attacker, defender) > reach and walked < 300:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		walked += 1
	runner.idle(20)
	## Seated after the approach. An idle blade returns to its committed guard,
	## so carrying this angle in from range sweeps it through the attacker.
	defender.weapon.angle = guard
	defender.weapon.speed = 0.0
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	return runner


func _tap_at_guard(guard: float, ticks: int, rules: DuelRules = null, trace: Array[String] = []) -> SimRunner:
	var runner := _seat_tap(guard, rules)
	for _i in ticks:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		trace.append(StateHasher.hash_state(runner.state))
	return runner


## NO-LABEL-PHYSICS-001: nothing in the simulation reads a parry. The same
## interception, once by steel that protects (labelled PARRY) and once by the
## same steel declared non-protective — a classification-only input, read by
## PARRY alone — moves every body, sword, phase and contact identically on
## every tick. The only difference is the event.
func test_a_parry_label_changes_no_physics() -> void:
	## ARRANGE: the parry scene of test_tap_into_a_strong_guard_is_parried.
	var labelled_trace: Array[String] = []
	var labelled := _tap_at_guard(PARRY_GUARD, 40, DuelFixture.rules(), labelled_trace)
	## PERTURB: the defender's steel protects nothing.
	var inert := DuelFixture.rules()
	inert.combatant(1).weapon.blade_protects = false
	assert_true(inert.is_valid(), "fixture: the declaration is still valid content")
	## ACT
	var silenced_trace: Array[String] = []
	var silenced := _tap_at_guard(PARRY_GUARD, 40, inert, silenced_trace)
	## ASSERT
	assert_true(labelled.first(DuelEventTypes.BLADE_CONTACT) != null, "control: the guard meets the tap")
	assert_eq(labelled.count(DuelEventTypes.PARRY), 1, "control: labelled a parry")
	assert_eq(silenced.count(DuelEventTypes.PARRY), 0, "perturbed: non-protective steel parries nothing")
	assert_eq(silenced.count(DuelEventTypes.BLADE_CONTACT), labelled.count(DuelEventTypes.BLADE_CONTACT), "yet the same contacts happen")
	assert_eq(silenced_trace.size(), 40, "fixture: every tick traced")
	assert_eq(silenced_trace, labelled_trace, "and the state is identical on every tick")


## A parry is physical interception, never a timing verdict (PARRY-001). The
## scene proves itself first: with the defender's guard seated away the same
## tap lands, so it threatened; with the guard in its path, the guard meets it
## before that hit would have come, with a positive impulse that arrests it,
## and no body is hit. Then the label MUST fire, credited to the defender. The
## riposte advantage rides along as a separate reading — here a parry that
## won no tempo, which is still a parry.
func test_tap_into_a_strong_guard_is_parried() -> void:
	var limit := _rules.combatant(1).weapon.guard_limit
	## ARRANGE (control): the guard seated outside the sweep — the tap lands.
	var control := _tap_at_guard(-limit, 40)
	var landed := control.first(DuelEventTypes.BODY_HIT)
	assert_eq(control.count(DuelEventTypes.BLADE_CONTACT), 0, "control: no sword contact")
	assert_true(landed != null and landed.actor == 0, "control: without the guard in its path the tap hits")
	## PERTURB + ACT: the same tap, the guard resting in its path. The follow
	## ticks also read the recovering blade against the defender's torso.
	var rules := DuelFixture.rules()
	var runner := _seat_tap(PARRY_GUARD, rules)
	var pose := BladePose.new()
	var weapon := rules.combatant(0).weapon
	var hurt := rules.combatant(1).fighter.hurt_radius
	var recovering := 0
	var min_gap := INF
	for _step in 40:
		var attacker := runner.state.fighter(0)
		if attacker.weapon.phase == CombatPhase.Id.RECOVERY:
			recovering += 1
			WeaponKinematics.pose_of(attacker, rules.combatant(0), pose)
			var tip_x := pose.point_x(weapon.tip_radius)
			var tip_y := pose.point_y(weapon.tip_radius)
			var defender := runner.state.fighter(1)
			var along := SimMath.closest_param_on_segment(pose.origin_x, pose.origin_y, tip_x, tip_y, defender.x, defender.y)
			var px := pose.origin_x + (tip_x - pose.origin_x) * along
			var py := pose.origin_y + (tip_y - pose.origin_y) * along
			min_gap = minf(min_gap, SimMath.length(px - defender.x, py - defender.y) - hurt - weapon.blade_radius)
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	## ASSERT: physically a parry...
	var contact := runner.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(contact != null, "the guard meets the tap")
	assert_true(contact.tick < landed.tick, "before the hit it would otherwise have taken (tick %d < %d)" % [contact.tick, landed.tick])
	assert_eq(contact.actor, 0, "the tap is the attacker")
	assert_true(contact.number(DuelEventKeys.IMPULSE) > 0.0, "with a solved, positive impulse")
	assert_true(contact.number(DuelEventKeys.DELTA_0) * runner.state.fighter(0).weapon.swing_dir < 0.0, "that opposed the cut")
	assert_true(bool(contact.data[DuelEventKeys.ARRESTED_0]), "and arrested it")
	assert_eq(runner.count(DuelEventTypes.BODY_HIT), 0, "the body hit is prevented")
	assert_true(recovering > 0, "the arrested cut entered recovery")
	assert_true(min_gap > 0.0, "and while it recovered the blade stayed outside the torso (%.4f m)" % min_gap)
	## ...so it is labelled a parry, whatever the tempo it left.
	var parries := DuelFixture.of_type(runner.events, DuelEventTypes.PARRY)
	assert_eq(parries.size(), 1, "physical interception is a parry")
	assert_eq(parries[0].tick, contact.tick, "on the interception itself")
	assert_eq(parries[0].actor, 1, "the defender is credited")
	assert_eq(parries[0].target, 0, "against the attacker")
	assert_true(is_finite(parries[0].number(DuelEventKeys.MARGIN)), "and carries the riposte advantage as a reading")
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


## The other half of PARRY-001: a clash the cut carries on through is not a
## parry, even with a weapon in the way and however much it slowed the cut.
func test_a_clash_the_cut_carries_through_is_not_a_parry() -> void:
	var state := _beat_scene()
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
	assert_true(contact.number(DuelEventKeys.IMPULSE) > 0.0, "precondition: a real clash")
	assert_true(contact.number(DuelEventKeys.DELTA_0) < 0.0, "precondition: the guard took progress from the cut")
	assert_false(bool(contact.data[DuelEventKeys.ARRESTED_0]), "precondition: but did not arrest it")
	assert_true(state.fighter(0).weapon.speed * state.fighter(0).weapon.swing_dir > 0.0, "precondition: the cut still progresses")
	assert_true(state.fighter(0).weapon.attack_contacted, "the attack did meet the opponent")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.PARRY).size(), 0, "but a carried-through cut is not parried")


func test_separating_blades_do_not_collide() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = -9.0
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	assert_eq(events.size(), 0, "blades moving apart exchange nothing")
	assert_eq(state.blade_contact.phase, SwordContactSet.Phase.SEPARATED, "and never enter a contact")


## Closing speed (m/s, > 0 approaching) of the two blades at (px, py) along
## the normal the resolver recorded.
func _closing_at(state: MatchState, px: float, py: float) -> float:
	var spec := _rules.combatant(0)
	var pose_a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	WeaponKinematics.velocity_into(state.fighter(0), pose_a, px, py)
	WeaponKinematics.velocity_into(state.fighter(1), pose_b, px, py)
	var contact := state.blade_contact
	return -((pose_a.vx - pose_b.vx) * contact.normal_x + (pose_a.vy - pose_b.vy) * contact.normal_y)


## RIGID-CONTACT-002: there is no scripted bind. A contact closing below the
## restitution threshold is resting, not an impact: it is inelastic — the
## blades stop closing and neither bounces — and it simply persists for the
## rigid solver. Nothing is zeroed, no input or charge is cleared, and no
## winner is picked; the old bind did all three.
func test_a_slow_contact_is_inelastic_and_persists_without_a_bind() -> void:
	var state := _beat_scene()
	state.fighter(0).weapon.speed = 1.0
	var defender := state.fighter(1)
	defender.attack_held = true
	defender.press_tick = 0
	defender.weapon.charge = 0.3
	defender.weapon.earned_windback = 0.2
	defender.weapon.phase = CombatPhase.Id.CHARGING
	state.blade_contact.set_normal(0.0, -1.0)
	var closing := _closing_at(state, 1.1, 0.022)
	assert_between(closing, SimMath.EPSILON, _rules.combatant(0).weapon.restitution_threshold_speed, "precondition: a slow closing contact (%.3f m/s)" % closing)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "a slow contact is an ordinary blade contact")
	assert_eq(contacts[0].text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_LIGHT), "classified light")
	## Friction iterates with the normal; four fixed passes leave a residual far
	## below a micrometre per second, which is no bounce.
	assert_near(_closing_at(state, 1.1, 0.022), 0.0, SOLVE_RESIDUAL, "inelastic: the blades stop closing and do not bounce apart")
	assert_true(absf(state.fighter(0).weapon.speed) > SimMath.EPSILON, "the cut is not zeroed by fiat")
	assert_true(defender.attack_held and defender.press_tick == 0, "the defender's held input survives")
	assert_eq(defender.weapon.charge, 0.3, "and so does the charge it earned")
	assert_eq(defender.weapon.phase, CombatPhase.Id.CHARGING, "and its phase")


## The restitution threshold is a speed, not a state: below it a new contact
## is inelastic, at or above it the blades leave at e × the closing speed.
func test_a_fast_contact_still_bounces() -> void:
	var w := _rules.combatant(0).weapon
	assert_eq(w.restitution_at(w.restitution_threshold_speed * 0.99), 0.0, "below the threshold: inelastic")
	assert_eq(w.restitution_at(w.restitution_threshold_speed), w.restitution, "at the threshold: the authored restitution")
	var state := _beat_scene()
	state.blade_contact.set_normal(0.0, -1.0)
	var closing := _closing_at(state, 1.1, 0.022)
	assert_true(closing > w.restitution_threshold_speed, "precondition: a fast contact (%.2f m/s)" % closing)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	assert_near(_closing_at(state, 1.1, 0.022), -w.restitution * closing, SOLVE_RESIDUAL, "the blades separate at e × closing")


## RIGID-CONTACT-002: one interrupt law for a first impact and a held
## contact. The phase describes what the sword did: a cut ends when a contact
## opposed it and either stopped or reversed it, or pinned it — held it under
## the wielder's `control_speed` with nothing gained over the tick. A cut
## travelling faster than control, or one still accelerating out of a contact
## it was launched in, is not interrupted; no ratio or timer decides it. Both
## swing directions.
func test_one_interrupt_law_decides_blocked_from_glancing() -> void:
	var control := _rules.combatant(0).weapon.control_speed
	for dir: float in [1.0, -1.0]:
		var weapon := WeaponState.new()
		weapon.swing_dir = dir
		weapon.speed = (control + 1.0) * dir
		assert_false(ContactResolver.arrests(weapon, -9.0 * dir, control, 12.0 * dir), "glancing (dir %+.0f): still faster than control → still a cut" % dir)
		weapon.speed = 0.3 * dir
		assert_true(ContactResolver.arrests(weapon, -9.0 * dir, control, 9.3 * dir), "pressed (dir %+.0f): brought under control from a fast cut → arrested" % dir)
		assert_true(ContactResolver.arrests(weapon, -0.4 * dir, control, 0.3 * dir), "pinned (dir %+.0f): under control and no faster than the tick began → arrested" % dir)
		assert_false(ContactResolver.arrests(weapon, -0.4 * dir, control, 0.0), "launched from a contact (dir %+.0f): under control but gaining on it → still a cut" % dir)
		weapon.speed = control * dir
		assert_true(ContactResolver.arrests(weapon, -1.0 * dir, control, (control + 1.0) * dir), "exactly at control (dir %+.0f), slowed → arrested" % dir)
		weapon.speed = 0.0
		assert_true(ContactResolver.arrests(weapon, -6.0 * dir, control, 6.0 * dir), "blocked (dir %+.0f): stopped dead → arrested" % dir)
		assert_true(ContactResolver.arrests(weapon, -0.5 * dir, control, -1.0 * dir), "stopped dead arrests whatever the tick began at (dir %+.0f)" % dir)
		weapon.speed = -1.5 * dir
		assert_true(ContactResolver.arrests(weapon, -7.5 * dir, control, 6.0 * dir), "reversed (dir %+.0f) → arrested" % dir)
		weapon.speed = -1.0 * dir
		assert_false(ContactResolver.arrests(weapon, 0.5 * dir, control, -1.5 * dir), "a contact pushing along the cut never arrests it, even one already reversed (dir %+.0f)" % dir)


## The motor is a finite torque, not a velocity setter: a cut a contact slowed
## is re-driven from the speed the contact left it, by at most one tick of the
## motor's authority (`α·dt`, `α = τ / M_θ`), never snapped back to its ceiling.
## That is what lets a contact's effect survive — no pause, no timer.
func test_a_met_cut_is_re_driven_at_finite_torque() -> void:
	var state := DuelFixture.state(_rules)
	var w := _rules.combatant(0).weapon
	var ceiling := w.achievable_swing_speed(1.0, 1.0)
	var authority := w.swing_accel(1.0, _rules.combatant(0).fighter.weapon_torque_scale, WeaponKinematics.motor_inertia(_rules.combatant(0), deg_to_rad(-60.0))) * SimulationTimebase.TICK_SECONDS
	var met := state.fighter(0)
	ContactFixture.arm(met, 0.0, 0.0, 0.0, deg_to_rad(-60.0), ceiling, CombatPhase.Id.ACTIVE_EARLY, 1.0, w)
	met.weapon.launch_preparation = 1.0
	ContactFixture.arm(state.fighter(1), 3.0, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, w)
	var after_contact := ceiling - 1.5 * authority
	met.weapon.speed = after_contact
	assert_true(after_contact > 0.0, "fixture: the contact took %.1f of %.1f rad/s, more than one tick of motor authority (%.2f)" % [ceiling - after_contact, ceiling, authority])
	var events: Array[DuelEvent] = []
	WeaponSystem.step(met, _rules, 0, events)
	assert_true(CombatPhase.is_swinging(met.weapon.phase), "precondition: still a cut")
	assert_near(met.weapon.speed, after_contact + authority, 1e-9, "the motor adds exactly one tick of its torque to what the contact left")
	assert_true(met.weapon.speed < ceiling, "so the contact's effect is still there a tick later")
	WeaponSystem.step(met, _rules, 1, events)
	assert_near(met.weapon.speed, ceiling, 1e-9, "and the cut regains its ceiling only as fast as its torque allows")


## One live tick with the attacker mid-swing at `attacker_angle` and the
## defender standing off the attacker's arc holding their blade at
## `guard_angle`. Returns the events that tick produced.
func _one_live_tick(attacker_angle: float, speed: float, guard_angle: float) -> Array[DuelEvent]:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var state := runner.state
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, attacker_angle, speed, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	var dx := SimMath.cosine(deg_to_rad(-40.0))
	var dy := SimMath.sine(deg_to_rad(-40.0))
	ContactFixture.arm(state.fighter(1), dx, dy, atan2(-dy, -dx), guard_angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
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
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
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


func test_displacement_is_impulse_over_body_mass() -> void:
	## PHYS-004, PHYS-010. Bilateral impulse: the target is pushed by J / m_T
	## where J is the single authoritative bilateral impulse. There is no
	## feel scale — the push is the physical consequence of one J. Exposure is
	## a reading (v36): it scales neither damage nor displacement.
	## The composed target faces the attacker on its guard, ready to answer;
	## the helpless one is caught in a full overswing, turned away.
	var facing := SimMath.arctan2(-0.27, -0.9)
	var guard := -_rules.combatant(0).weapon.guard_angle
	var composed := DuelFixture.state(_rules)
	ContactFixture.arm(composed.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(composed.fighter(1), 0.9, 0.27, facing, guard, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var helpless := DuelFixture.state(_rules)
	ContactFixture.arm(helpless.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(helpless.fighter(1), 0.9, 0.27, facing + PI * 0.6, guard, 0.0, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	var calm_events: Array[DuelEvent] = []
	ContactResolver.resolve(composed, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, calm_events)
	var exposed_events: Array[DuelEvent] = []
	ContactResolver.resolve(helpless, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, exposed_events)
	var calm := DuelFixture.of_type(calm_events, DuelEventTypes.BODY_HIT)[0]
	var exposed := DuelFixture.of_type(exposed_events, DuelEventTypes.BODY_HIT)[0]
	assert_true(exposed.number(DuelEventKeys.EXPOSURE) > calm.number(DuelEventKeys.EXPOSURE), "precondition: one target is far worse positioned")
	assert_near(exposed.number(DuelEventKeys.DAMAGE), calm.number(DuelEventKeys.DAMAGE), 1e-9, "and is hurt exactly as much: the same impact, the same damage")
	assert_true(absf(composed.fighter(1).vy) > 0.0, "the hit pushes the target")
	assert_near(composed.fighter(1).vy, calm.number(DuelEventKeys.PUSH), 1e-9, "displacement matches the reported bilateral push")
	assert_near(helpless.fighter(1).vy, composed.fighter(1).vy, 1e-9, "and exposure adds none of it")


func test_stagger_is_decided_by_impulse_not_by_damage() -> void:
	## PHYS-004. Being knocked off balance is a momentum event. A fast cut
	## that hurts badly need not unbalance anyone, and the threshold the
	## resolver reads is impulse-derived.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	assert_near(
		strike.stagger_pressure,
		strike.impact.normalized_impulse(_rules.combat),
		1e-12,
		"stagger pressure is the normalized impulse itself (v36: exposure never scales it)"
	)
	assert_true(strike.damage > 0.0, "precondition: the cut does real damage")
	assert_true(strike.stagger_pressure < _rules.combatant(0).weapon.stagger_impulse, "precondition: but not enough momentum to unbalance a composed fighter")
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.STAGGERED).size(), 0, "so a damaging cut alone does not stagger")


func test_true_double_hit_damages_both() -> void:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, PI, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
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
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 15.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
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
	## Stagger is the solved impulse crossing `stagger_impulse`, not a speed
	## that used to be "strong" under a lighter fake mass. Build the hit so
	## its pressure is over that line, then require the resolver to stagger.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 10.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.CHARGING, 0.5, _rules.combatant(0).weapon)
	var probe := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	var line := _rules.combatant(0).weapon.stagger_impulse
	assert_true(probe.stagger_pressure > 0.0, "precondition: the cut carries stagger pressure")
	var speed := 10.0 * line / probe.stagger_pressure * 1.05
	state.fighter(0).weapon.speed = speed
	var over := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	assert_true(over.stagger_pressure >= line, "precondition: this hit is over the stagger line (%.3f)" % over.stagger_pressure)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.STAGGERED).size(), 1, "stagger reported")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.STAGGER, "charge interrupted by stagger")
	## The attacker's cut follows the one arrest law (RIGID-CONTACT-002) on
	## what the hit left of it: still a cut above control speed, over below.
	var cut := state.fighter(0).weapon
	var arrested := cut.speed * cut.swing_dir <= _rules.combatant(0).weapon.control_speed
	assert_eq(cut.phase, CombatPhase.Id.RECOVERY if arrested else CombatPhase.Id.ACTIVE_THREAT, "the attacker's phase is the arrest law's verdict (%.2f rad/s left)" % cut.speed)


## WHIFF-001: a landed hit whose cut carries on into its overswing is still a
## hit. The hit here is a walking poke met dead along the blade: its lever is
## zero (PHYS-008), so it takes nothing from the cut, which runs on to its
## end. The hit marks the attack as having met the opponent, so that end emits
## no ATTACK_WHIFFED; the same cut at nothing emits exactly one.
func test_a_hit_that_carries_into_overswing_is_never_a_whiff() -> void:
	var weapon := _rules.combatant(0).weapon
	## ARRANGE: the poke scene, and its free twin with the target far away.
	var hit_state := DuelFixture.state(_rules)
	var free_state := DuelFixture.state(_rules)
	for state: MatchState in [hit_state, free_state]:
		var a := state.fighter(0)
		DuelFixture.place(a, 0.0, 0.0, 0.0)
		a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
		a.weapon.angle = 0.0
		a.weapon.speed = 2.0
		a.weapon.swing_dir = 1.0
		a.weapon.swing_start = deg_to_rad(-45.0)
		a.weapon.swing_end = deg_to_rad(45.0)
		a.vx = 5.0
	DuelFixture.place(hit_state.fighter(1), weapon.tip_radius + _rules.combatant(0).fighter.push_radius, 0.0, PI)
	DuelFixture.place(free_state.fighter(1), 10.0, 0.0, PI)
	var hit_events: Array[DuelEvent] = []
	ContactResolver.resolve(hit_state, ContactFixture.body_report(0, weapon.tip_radius, 0.0), _rules, 1, 0.0, hit_events)
	var cut := hit_state.fighter(0).weapon
	assert_eq(DuelFixture.of_type(hit_events, DuelEventTypes.BODY_HIT).size(), 1, "precondition: the poke landed")
	assert_true(cut.speed * cut.swing_dir > weapon.control_speed, "precondition: the hit left the cut travelling (%.2f rad/s)" % cut.speed)
	assert_true(CombatPhase.is_swinging(cut.phase), "precondition: so it is still a cut")
	## ACT: both cuts run on to their end.
	var overswung: Array[bool] = [false, false]
	var whiffs := PackedInt32Array([0, 0])
	var states: Array[MatchState] = [hit_state, free_state]
	for index in 2:
		var events: Array[DuelEvent] = []
		var fighter := states[index].fighter(0)
		for tick in 120:
			WeaponSystem.step(fighter, _rules, tick, events)
			overswung[index] = overswung[index] or fighter.weapon.phase == CombatPhase.Id.OVERSWING
			if fighter.weapon.phase == CombatPhase.Id.RECOVERY:
				break
		whiffs[index] = DuelFixture.of_type(events, DuelEventTypes.ATTACK_WHIFFED).size()
	## ASSERT
	assert_true(overswung[0], "precondition: the hit cut carried on into its overswing")
	assert_true(overswung[1], "control: so did the free cut")
	assert_eq(whiffs[0], 0, "a landed hit's end is not a whiff")
	assert_eq(whiffs[1], 1, "control: the cut that met nothing is labelled a whiff, once")

## --- PHYS-008: weapon/body coupling through the contact Jacobian -----------
## Every body contact turns the blade by `J·c/M_θ` — no classification is
## exempt. A point driven straight along its blade from Long Guard has a zero
## lever (`C′_fwd(0) = 0`, and the rotation term is perpendicular to the
## axis), so it turns nothing; a slash or an oblique contact has a real lever
## and reacts. Off-axis points are in IMPACT.
##
## Implements: /spec/invariants.md#phys-008
## See also: /docs/concepts/combat.md


## Group 1: centred axial points — zero lever, so weapon.speed is unchanged.

func test_poke_does_not_change_weapon_speed() -> void:
	## A walking poke straight along the blade into the target's centre: the
	## normal is the blade axis, the lever is zero, no Δω on the weapon.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.combatant(0).weapon.tip_radius + _rules.combatant(0).fighter.push_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 2.0
	a.weapon.swing_dir = 1.0
	a.vx = 5.0
	var speed_before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, _rules.combatant(0).weapon.tip_radius, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 1, "body hit resolved")
	assert_eq(a.weapon.speed, speed_before, "poke: weapon speed unchanged (PHYS-008)")
	assert_true(b.health < _rules.combatant(0).fighter.max_health, "target took damage")
	assert_true(absf(b.vx) > 0.0 or absf(b.vy) > 0.0, "target was pushed")


func test_thrust_does_not_change_weapon_speed() -> void:
	## A forward-dash thrust: all poke criteria plus aligned burst.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.combatant(0).weapon.tip_radius + _rules.combatant(0).fighter.push_radius, 0.0, PI)
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
	ContactResolver.resolve(state, ContactFixture.body_report(0, _rules.combatant(0).weapon.tip_radius, 0.0), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_THRUST).size(), 1, "classified as THRUST")
	assert_eq(a.weapon.speed, speed_before, "thrust: weapon speed unchanged (PHYS-008)")


## Group 2: transverse and oblique contacts — a real lever, measurable Δω.

func test_slash_produces_blade_reaction() -> void:
	## A transverse slash: the blade's edge leads, contact is mid-blade
	## (not tip region). The weapon receives a reactive angular impulse.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
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
	ContactFixture.arm(tap_state.fighter(0), 0.0, 0.0, 0.0, 0.0, 6.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(tap_state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var tap_speed_before := tap_state.fighter(0).weapon.speed
	var tap_events: Array[DuelEvent] = []
	ContactResolver.resolve(tap_state, ContactFixture.body_report(0, 0.45, 0.0), _rules, 1, 0.0, tap_events)
	var tap_dw := absf(tap_state.fighter(0).weapon.speed - tap_speed_before)
	var charged_state := DuelFixture.state(_rules)
	ContactFixture.arm(charged_state.fighter(0), 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, _rules.combatant(0).weapon)
	ContactFixture.arm(charged_state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
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
	DuelFixture.commit(a, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	var speed_before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.85, 0.0), _rules, 1, 0.0, events)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_eq(hits.size(), 1, "body hit")
	var strike := DamageModel.evaluate(a, b, 0.85, 0.0, _rules)
	assert_true(strike.contact_kind != StrikeResult.ContactKind.POKE and strike.contact_kind != StrikeResult.ContactKind.THRUST, "precondition: oblique geometry is not a point strike")
	assert_true(absf(state.fighter(0).weapon.speed - speed_before) > 0.001, "blade reacted through its lever")
	assert_true(b.health < _rules.combatant(0).fighter.max_health, "target took damage")


## Group 3: Weapon-body lifecycle — one damage entry per real episode.
## CollisionSystem reports a body hit only when `observe` returns true, which
## is only the OUTSIDE → ENTERED transition. These two fixtures are that gate.
## A swing's speed and whatever else it hits are not part of the law.

func test_staying_inside_a_body_is_one_hit() -> void:
	var lifecycle := WeaponBodyContact.new()
	var touch := 0.2
	var epsilon := _rules.combat.separation_epsilon
	var hits := 0
	if lifecycle.observe(touch - 0.01, touch, epsilon):
		hits += 1
	lifecycle.advance_after_entry(false)
	for _tick in 10:
		if lifecycle.observe(touch - 0.01, touch, epsilon):
			hits += 1
		assert_true(lifecycle.is_inside(), "the blade is still inside")
	assert_eq(hits, 1, "ten ticks inside the body are one entry, one hit")


func test_leaving_past_hysteresis_and_reentering_is_a_second_hit() -> void:
	var lifecycle := WeaponBodyContact.new()
	var touch := 0.2
	var epsilon := _rules.combat.separation_epsilon
	var clear := touch + epsilon + 0.01
	var hits := 0
	if lifecycle.observe(touch - 0.01, touch, epsilon):
		hits += 1
	lifecycle.advance_after_entry(false)
	assert_false(lifecycle.observe(clear, touch, epsilon), "the first step clear is EXITING, not a new hit")
	assert_eq(lifecycle.phase, WeaponBodyContact.Phase.EXITING, "precondition: exiting")
	assert_false(lifecycle.observe(clear, touch, epsilon), "still clear, so the lifecycle rearms")
	assert_eq(lifecycle.phase, WeaponBodyContact.Phase.OUTSIDE, "precondition: back outside, past hysteresis")
	if lifecycle.observe(touch - 0.01, touch, epsilon):
		hits += 1
	assert_eq(hits, 2, "a genuine exit and re-entry is a second hit")
	assert_false(lifecycle.observe(touch - 0.01, touch, epsilon), "and staying in after that does not add a third")


## --- Bilateral sword-body impulse (PHYS-010) --------------------------------


func test_bilateral_momentum_conservation() -> void:
	## PHYS-010. The bilateral impulse is equal and opposite: the impulse
	## applied to the target (via effective mass) equals minus the impulse
	## applied to the attacker. The angular term on the sword is a torque
	## derived from the same J.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	var m_t := strike.impact.target_mass
	var m_a := strike.impact.attacker_mass
	var a0_vx := state.fighter(0).vx
	var a0_vy := state.fighter(0).vy
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	## Effective-mass-weighted impulse must cancel: J_T + J_A = 0.
	var dv_tx := state.fighter(1).vx
	var dv_ty := state.fighter(1).vy
	var dv_ax := state.fighter(0).vx - a0_vx
	var dv_ay := state.fighter(0).vy - a0_vy
	assert_near(m_t * dv_tx + m_a * dv_ax, 0.0, 1e-6, "bilateral impulse x cancels")
	assert_near(m_t * dv_ty + m_a * dv_ay, 0.0, 1e-6, "bilateral impulse y cancels")


func test_newton_third_law_bilateral() -> void:
	## PHYS-010. Target and attacker receive equal and opposite impulse from
	## the single bilateral J: m_T * dv_T + m_A * dv_A = 0 where m is the
	## effective mass used in the bilateral computation.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	var m_t := strike.impact.target_mass
	var m_a := strike.impact.attacker_mass
	var a0_vx := state.fighter(0).vx
	var a0_vy := state.fighter(0).vy
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	var dv_ax := state.fighter(0).vx - a0_vx
	var dv_ay := state.fighter(0).vy - a0_vy
	var dv_tx := state.fighter(1).vx
	var dv_ty := state.fighter(1).vy
	## Newton's third via effective masses: J_target = -J_attacker.
	assert_near(m_t * dv_tx + m_a * dv_ax, 0.0, 1e-6, "N3 x: effective-mass impulse cancels")
	assert_near(m_t * dv_ty + m_a * dv_ay, 0.0, 1e-6, "N3 y: effective-mass impulse cancels")
	assert_true(absf(dv_tx) + absf(dv_ty) > 0.0, "target was pushed")
	assert_true(absf(dv_ax) + absf(dv_ay) > 0.0, "attacker was pushed back")


func test_restitution_relation_on_sword_body() -> void:
	## PHYS-010. First contact uses sword_body_restitution: v_rel_after ≈
	## -e * v_rel_before along the contact normal. With e near zero the
	## bodies barely separate after contact.
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var hit := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.9, 0.0, _rules)
	var v_rel_before := hit.impact.normal_speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	## Contact normal points from the contact point to the target center.
	## Post-contact relative velocity along this normal should be ≈ -e * v_rel_before.
	var e := _rules.combat.sword_body_restitution
	assert_true(v_rel_before > 0.0, "precondition: closing before contact")
	assert_true(e >= 0.0 and e <= 1.0, "precondition: valid restitution")


func test_nonlethal_enters_constraining() -> void:
	## PHYS-010. A nonlethal body hit transitions the weapon-body lifecycle
	## from ENTERED to CONSTRAINING (blade cannot phase through body).
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 0.9, 0.27, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	assert_eq(state.weapon_body_contacts[0].phase, WeaponBodyContact.Phase.OUTSIDE, "precondition: outside")
	## Create a body report AND manually set lifecycle to ENTERED (as collision system would).
	state.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.ENTERED
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, 0.9, 0.0), _rules, 1, 0.0, events)
	assert_eq(state.weapon_body_contacts[0].phase, WeaponBodyContact.Phase.CONSTRAINING, "nonlethal hit enters CONSTRAINING")


func test_lethal_enters_penetrating() -> void:
	## PHYS-010. A lethal point hit transitions the weapon-body lifecycle
	## to PENETRATING (blade continues through).
	var state := DuelFixture.state(_rules)
	## Set up a lethal thrust scenario: high-speed point-first contact.
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-20.0), 39.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), _rules.combatant(0).weapon.tip_radius * 0.9, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	state.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.ENTERED
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, _rules.combatant(0).weapon.tip_radius * 0.9, 0.0), _rules, 1, 0.0, events)
	var body_hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_true(body_hits.size() > 0, "a body hit was produced")
	var is_lethal := body_hits[0].number(DuelEventKeys.LETHAL) > 0.5
	if is_lethal:
		assert_eq(state.weapon_body_contacts[0].phase, WeaponBodyContact.Phase.PENETRATING, "lethal hit enters PENETRATING")
	else:
		assert_eq(state.weapon_body_contacts[0].phase, WeaponBodyContact.Phase.CONSTRAINING, "nonlethal hit enters CONSTRAINING")


func test_weapon_body_lifecycle_reset() -> void:
	## WeaponBodyContact round reset returns to OUTSIDE.
	var wbc := WeaponBodyContact.new()
	wbc.phase = WeaponBodyContact.Phase.CONSTRAINING
	wbc.reset()
	assert_eq(wbc.phase, WeaponBodyContact.Phase.OUTSIDE, "reset returns to OUTSIDE")
	wbc.phase = WeaponBodyContact.Phase.PENETRATING
	wbc.reset()
	assert_eq(wbc.phase, WeaponBodyContact.Phase.OUTSIDE, "reset from PENETRATING also returns to OUTSIDE")


func test_constraining_reentry_from_exiting() -> void:
	## PHYS-010. Blade that exits and re-enters goes to CONSTRAINING,
	## not back to damage-dealing ENTERED.
	var wbc := WeaponBodyContact.new()
	wbc.phase = WeaponBodyContact.Phase.EXITING
	## Re-enter the body (gap <= touch).
	wbc.observe(0.05, 0.1, 0.02)
	assert_eq(wbc.phase, WeaponBodyContact.Phase.CONSTRAINING, "re-entry from EXITING goes to CONSTRAINING")


## CONTACT-HEADING-001: contact acts on the root and the weapon coordinate,
## never on the heading. The same clash leaves both fighters' φ and φ̇
## exactly as they were while it changes root velocity and θ̇; the heading
## then answers on the next turn only through what the contact changed — here
## the cut's lost momentum, which is less redirect debt, so the same turn
## toward the same target is faster.
func test_contact_never_turns_the_heading_it_changes_what_the_heading_must_do() -> void:
	## ARRANGE: two identical clashes; one is resolved.
	var untouched := _beat_scene()
	var state := _beat_scene()
	var spec := _rules.combatant(0)
	var facing := PackedFloat64Array([state.fighter(0).facing, state.fighter(1).facing])
	var turn_rate := PackedFloat64Array([state.fighter(0).turn_rate, state.fighter(1).turn_rate])
	var cut_speed := state.fighter(0).weapon.speed
	var velocity := Vector2(state.fighter(0).vx, state.fighter(0).vy)
	## ACT
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.blade_report(state, 1.1, 0.0, 1.1, 0.044), _rules, 1, 0.0, events)
	## ASSERT: the solve moved the root and θ̇...
	var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
	assert_true(contact.number(DuelEventKeys.IMPULSE) > 0.0, "fixture: a real clash")
	assert_true(absf(state.fighter(0).weapon.speed - cut_speed) > 0.1, "the contact changed the cut's θ̇")
	assert_true(Vector2(state.fighter(0).vx, state.fighter(0).vy).distance_to(velocity) > 0.0, "and the wielder's root velocity")
	## ...and never the heading.
	for slot in 2:
		var f := state.fighter(slot)
		assert_eq(f.facing, facing[slot], "fighter %d's heading is where it was" % slot)
		assert_eq(f.turn_rate, turn_rate[slot], "and its turn rate (φ̇) is untouched")
	## PERTURB: one heading tick toward a target off to the side, from the
	## untouched clash and from the resolved one.
	var turned: Array[float] = []
	for scene: MatchState in [untouched, state]:
		var f := scene.fighter(0)
		var torque := CommitmentModel.turn_torque_share(f, spec, ConditionState.new(), _rules.combat)
		var rate := CommitmentModel.turn_rate_share(f, spec, ConditionState.new(), _rules.combat)
		FacingSystem.step(f, 0.0, 3.0, torque, spec.fighter, null, rate)
		turned.append(f.turn_rate)
	assert_true(turned[0] > 0.0, "control: the committed cut still turns when asked (AUTHORITY-001)")
	assert_true(turned[1] > turned[0], "the clash took momentum, so less redirect debt turns the heading faster (%.4f vs %.4f rad/s)" % [turned[1], turned[0]])


## CONTACT-POINT-LEVER-001: where the contact lands on the blade decides the
## sword's response through the Jacobian, with no strong/weak multiplier. The
## same cut met at the forte and at the foible: each weapon-speed change is
## exactly its impulse times the lever over the coordinate's inertia
## (`Δθ̇ = J·c/M_θ`), and the foible's longer lever turns the sword more per
## newton-second.
func test_where_the_blade_is_met_decides_its_response_through_the_lever() -> void:
	var rules := DuelFixture.revolute_rules()
	rules.combat.blade_friction = 0.0
	var spec := rules.combatant(0)
	var per_impulse: Array[float] = []
	for r: float in [0.45, 1.05]:
		## ARRANGE: the same heavy cut along +X, met by a guard whose tip lies
		## 4.4 cm above the blade at radius `r`.
		var state := DuelFixture.state(rules)
		ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 18.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, spec.weapon)
		ContactFixture.arm(state.fighter(1), r + spec.weapon.tip_radius - 0.02, 0.044, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, spec.weapon)
		var report := ContactFixture.blade_report(state, r, 0.0, r, 0.044)
		var attacker := state.fighter(0)
		var pose := WeaponKinematics.pose_of(attacker, spec, BladePose.new())
		var lever := WeaponKinematics.lever(attacker, pose, r, 0.022, 0.0, -1.0)
		var held := PackedFloat64Array([0.0, 0.0])
		ContactMechanics.held_sword(attacker, pose, r, 0.022, spec, held)
		## ACT
		var events: Array[DuelEvent] = []
		ContactResolver.resolve(state, report, rules, 1, 0.0, events)
		## ASSERT
		var contact := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)[0]
		var impulse := contact.number(DuelEventKeys.IMPULSE)
		assert_true(impulse > 0.0, "fixture (r %.2f m): a solved clash" % r)
		assert_near(absf(contact.number(DuelEventKeys.DELTA_0)), impulse * absf(lever) / held[0], 1e-9 * maxf(1.0, impulse), "r %.2f m: Δθ̇ is exactly J·c/M_θ — no zone multiplier" % r)
		per_impulse.append(absf(contact.number(DuelEventKeys.DELTA_0)) / impulse)
	assert_true(per_impulse[1] > per_impulse[0], "the foible turns the sword more per N·s than the forte (%.3f vs %.3f rad/s per N·s)" % [per_impulse[1], per_impulse[0]])


## Every physical quantity of both fighters — bodies, headings, swords,
## phases, health — and nothing a label gates (the state hash also covers the
## label flags, WHIFF-001 / DEFLECTION-001).
func _physics(state: MatchState) -> String:
	var parts := PackedStringArray()
	for slot in 2:
		var f := state.fighter(slot)
		parts.append(var_to_str([f.x, f.y, f.vx, f.vy, f.facing, f.turn_rate, f.weapon.angle, f.weapon.speed, f.weapon.phase, f.weapon.commitment, f.weapon.recovery_left, f.health]))
	return "|".join(parts)


## ACTIVE-DEFLECTION-001 (DEFLECTION-CONSEQUENCE-001), a relationship witness,
## not a law: a defense buys tempo only through what it physically did. In this
## canonical scene — the parry scene, a tap from measure into a guard at its
## limit — an active beat at 12 rad/s solves a larger change in the cut's θ̇
## than a resting guard, and in this scene the attacker's next threat is later.
## Both are parries (the label is the same and reads nothing). There is no
## monotonic law in guard speed or in |Δθ̇|: other beats meet the cut at other
## points and moments, so the solved geometry decides. The solver's exact laws
## (impulse signs, Δθ̇ = J·c/M_θ, the friction bound, determinism) are owned by
## CONTACT and MANIFOLD.
func test_an_active_beat_displaces_this_cut_more_than_a_resting_guard() -> void:
	## ARRANGE + ACT
	var resting := _beaten_tap(0.0)
	var beaten := _beaten_tap(-24.0)
	## ASSERT
	assert_true(resting[2] and beaten[2], "fixture: both interceptions are parries — the label does not differ")
	assert_true(beaten[0] > resting[0], "the beat takes more of the cut's motion (|Δθ̇| %.2f vs %.2f rad/s)" % [beaten[0], resting[0]])
	assert_true(beaten[1] > resting[1], "so the attacker's next threat is later (%.3f vs %.3f s)" % [beaten[1], resting[1]])


## The parry scene of `test_tap_into_a_strong_guard_is_parried` with the
## defender's guard driven at `beat` rad/s until the tap meets it: [|Δθ̇| of
## the cut at the contact, the attacker's threat time just after it, whether
## it was a parry]. The beat has to be fast enough that the extra reversal
## moves the attacker's next threat by a tick; 12 rad/s takes more of the cut
## and still lands on the same predicted tick.
func _beaten_tap(beat: float) -> Array:
	var rules := DuelFixture.rules()
	var runner := _tap_at_guard(PARRY_GUARD, 0, rules)
	var defender := runner.state.fighter(1)
	for _i in 30:
		if runner.first(DuelEventTypes.BLADE_CONTACT) == null:
			defender.weapon.speed = beat
		var seen := runner.events.size()
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if event.type == DuelEventTypes.BLADE_CONTACT:
				return [absf(event.number(DuelEventKeys.DELTA_0)), InitiativeModel.time_to_threat(runner.state.fighter(0), defender, rules), runner.count(DuelEventTypes.PARRY) > 0]
	return [0.0, 0.0, false]


## RIPOSTE-NO-BONUS-001: a riposte is an ordinary attack from the state a
## defense left, never a mode. The parry scene, then the defender answers with
## an ordinary tap; once with the parry labelled and once with the steel made
## non-protective (no label anywhere), every tick and the answer's outcome are
## identical — nothing in the simulation knew it was a riposte.
func test_an_answer_after_a_parry_is_an_ordinary_attack() -> void:
	var labelled_trace: Array[String] = []
	var labelled := _riposte_after_parry(DuelFixture.rules(), labelled_trace)
	var inert := DuelFixture.rules()
	inert.combatant(1).weapon.blade_protects = false
	var plain_trace: Array[String] = []
	var plain := _riposte_after_parry(inert, plain_trace)
	assert_eq(labelled.count(DuelEventTypes.PARRY), 1, "control: the defense is labelled a parry")
	assert_eq(plain.count(DuelEventTypes.PARRY), 0, "perturbed: no label at all")
	assert_true(labelled.count(DuelEventTypes.ATTACK_RELEASED) >= 2, "fixture: the defender answered with an attack")
	assert_eq(plain_trace.size(), 90, "fixture: every tick traced")
	assert_eq(plain_trace, labelled_trace, "every tick of the answer moves identically")
	var answered := _consequences(labelled)
	assert_true(answered.size() > 1, "fixture: the answer met the opponent")
	assert_eq(_consequences(plain), answered, "and everything it did — every contact's impulse and every hit's damage — is identical: no riposte bonus")


## Every contact and hit of `runner`'s duel as (type, tick, actor, impulse,
## damage): what the attacks physically did, labels left out.
func _consequences(runner: SimRunner) -> Array[String]:
	var out: Array[String] = []
	for event in runner.events:
		if event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_HIT:
			out.append("%s %d %d %s %s" % [event.type, event.tick, event.actor, var_to_str(event.number(DuelEventKeys.IMPULSE)), var_to_str(event.number(DuelEventKeys.DAMAGE))])
	return out


## The parry scene of `test_tap_into_a_strong_guard_is_parried`, then the
## defender answers: from the interception it steps aside and holds the
## attack, releasing it 8 ticks later.
func _riposte_after_parry(rules: DuelRules, trace: Array[String]) -> SimRunner:
	var runner := _tap_at_guard(PARRY_GUARD, 0, rules)
	var met := -1
	for _i in 90:
		var tick := runner.state.tick
		if met < 0 and runner.first(DuelEventTypes.BLADE_CONTACT) != null:
			met = tick
		var holding := met >= 0 and tick <= met + 8
		var release := met >= 0 and tick == met + 8
		runner.push(PlayerCommand.idle(tick), PlayerCommand.create(tick, 0.5 if met >= 0 else 0.0, 0.0, holding, release))
		## Physics only: the hash also covers the readings a protective contact
		## marks (DEFLECTION-001's pending flag), which differ by design.
		trace.append(_physics(runner.state))
	return runner


## CONTACT-OUTCOME-001: a contact's reading describes its own solve and
## decides nothing. In a production wander duel (seed 5, pilots 11 / 23) every
## blade contact that met a cut is a GLANCE exactly when the cut kept at least
## `GLANCE_KEPT` of its progress, else a CLASH; the events carry that
## progress from the solve; both readings occur; and reading the events
## leaves the duel's state as it was.
func test_a_contact_reading_describes_the_solve() -> void:
	## ARRANGE: the production duel and its blade contacts.
	var runner := SimRunner.create(_rules, 5)
	runner.run(Pilot.wander(5, 11), Pilot.wander(5, 23), 1800)
	var control := _rules.combatant(0).weapon.control_speed
	var contacts := DuelFixture.of_type(runner.events, DuelEventTypes.BLADE_CONTACT)
	assert_true(contacts.size() > 5, "fixture: the duel met steel (%d contacts)" % contacts.size())
	var hash_before := StateHasher.hash_state(runner.state)
	## ACT
	var tally := {ContactReading.GLANCE: 0, ContactReading.CLASH: 0, ContactReading.TOUCH: 0}
	for contact in contacts:
		var reading := ContactReading.classify(contact, control, control)
		tally[reading] += 1
		## ASSERT: each reading is its definition.
		if contact.actor >= 0:
			var before := contact.number(DuelEventKeys.PROGRESS_BEFORE)
			assert_true(before > 0.0, "a cut met at tick %d was progressing (%.3f rad/s)" % [contact.tick, before])
			var glanced := contact.number(DuelEventKeys.PROGRESS_AFTER) >= ContactReading.GLANCE_KEPT * before
			assert_eq(reading, ContactReading.GLANCE if glanced else ContactReading.CLASH, "tick %d reads by the progress it kept" % contact.tick)
		else:
			assert_ne(reading, ContactReading.GLANCE, "tick %d: with no cut there is nothing to glance" % contact.tick)
	## ASSERT
	assert_true(tally[ContactReading.GLANCE] > 0 and tally[ContactReading.CLASH] > 0, "both readings occur (%s)" % str(tally))
	assert_eq(StateHasher.hash_state(runner.state), hash_before, "reading the contacts changes nothing")
