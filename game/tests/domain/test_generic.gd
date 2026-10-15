extends TestCase

## GENERIC: the simulation knows no fighter (COMBATANT-GENERIC-001,
## LOADOUT-001). Two synthetic combatants built only for this suite — a light
## fighter with a short, light sword and a heavy one with a long, heavy sword —
## fight through the same systems as the reference duelist, and every
## difference that appears is traced to their own content: `a = F/m`,
## `α = τ/M_θ`, each side's own masses in one contact, the attacker's reach
## against the target's torso. Swapping the two specs and the world gives the
## exact reflection with the actors exchanged, which is what catches a hidden
## slot-0 or reference-fighter assumption.
##
## Implements: /spec/invariants.md#combatant-generic-001
## Implements: /spec/invariants.md#loadout-001
## See also: /docs/concepts/combat.md, /examples/catalog-authoring.md

const LIGHT_ID := &"fighter.test_light"
const HEAVY_ID := &"fighter.test_heavy"
const SHORT_ID := &"weapon.test_short"
const LONG_ID := &"weapon.test_long"
const HANDLING_ID := &"handling.test"


func _init() -> void:
	suite_name = "GENERIC"


## 60 kg, a small torso and footprint, quick to turn; a short, light sword.
func _light_fighter() -> FighterDefinition:
	var fighter := FighterCatalog.duelist()
	fighter.id = LIGHT_ID
	fighter.mass = 60.0
	fighter.hand_mass = fighter.mass * PhysicalBaseline.HAND_REFLECTED_MASS_SHARE
	fighter.push_radius = 0.24
	fighter.hurt_radius = 0.17
	fighter.hand_radius = 0.032
	FighterCatalog.resolve_actuators(fighter, 0.9, 1.0, 1.15)
	return fighter


## 105 kg, a bigger torso and footprint and longer arms, stronger, slower to
## turn; a long, heavy sword with the reference crossguard.
func _heavy_fighter() -> FighterDefinition:
	var fighter := FighterCatalog.duelist()
	fighter.id = HEAVY_ID
	fighter.height = 1.9
	fighter.mass = 105.0
	fighter.hand_mass = fighter.mass * PhysicalBaseline.HAND_REFLECTED_MASS_SHARE
	fighter.push_radius = 0.30
	fighter.hurt_radius = 0.205
	fighter.grip_radius = PhysicalBaseline.GRIP_RADIUS_M * 1.08
	fighter.lying_half_length = 0.93
	FighterCatalog.resolve_actuators(fighter, 1.2, 1.15, 0.9)
	return fighter


func _short_weapon(fighter: FighterDefinition) -> WeaponDefinition:
	var weapon := WeaponCatalog.bastard_sword_at(0.8, 1.1, fighter.grip_radius)
	weapon.id = SHORT_ID
	return weapon


func _long_weapon(fighter: FighterDefinition) -> WeaponDefinition:
	var weapon := WeaponCatalog.bastard_sword_at(1.15, 2.1, fighter.grip_radius)
	weapon.id = LONG_ID
	## A longer blade with the reference crossguard: the bar does not grow.
	weapon.crossguard_half_span = PhysicalBaseline.CROSSGUARD_HALF_SPAN_M
	weapon.crossguard_radius = PhysicalBaseline.CROSSGUARD_DEPTH_M * 0.5
	return weapon


func _spec(fighter: FighterDefinition, weapon: WeaponDefinition) -> CombatantPhysicsSpec:
	return CombatantPhysicsSpec.compile(fighter, weapon, HandlingCatalog.two_handed_track(fighter, weapon, HANDLING_ID))


func _light() -> CombatantPhysicsSpec:
	var fighter := _light_fighter()
	return _spec(fighter, _short_weapon(fighter))


func _heavy() -> CombatantPhysicsSpec:
	var fighter := _heavy_fighter()
	return _spec(fighter, _long_weapon(fighter))


func test_the_synthetic_combatants_are_legal_and_genuinely_different() -> void:
	## ARRANGE
	var light := _light()
	var heavy := _heavy()
	## ASSERT: both validate as whole loadouts, and differ in every axis the
	## suite relies on.
	assert_eq(light.problem(), "", "the light loadout is legal")
	assert_eq(heavy.problem(), "", "the heavy loadout is legal")
	assert_true(heavy.fighter.mass > light.fighter.mass * 1.5, "the heavy body is much heavier (%.0f vs %.0f kg)" % [heavy.fighter.mass, light.fighter.mass])
	assert_true(heavy.weapon.tip_radius > light.weapon.tip_radius, "the heavy sword is longer")
	assert_true(WeaponKinematics.motor_inertia(heavy, 0.0) > WeaponKinematics.motor_inertia(light, 0.0), "and harder to turn")
	assert_true(heavy.fighter.hurt_radius > light.fighter.hurt_radius, "with a bigger torso")
	var rules := DuelFixture.with_loadouts(light, heavy)
	assert_eq(rules.problem(), "", "the heterogeneous rules are legal")
	assert_true(DuelSimulation.create(rules) != null, "and start a duel")


## a = F/m: the same force accelerates the lighter body more, through the one
## footwork system, from each body's own mass.
func test_the_same_force_accelerates_the_lighter_body_more() -> void:
	## ARRANGE: two bodies at rest, perturbed to the same locomotion force.
	var light := _light_fighter()
	var heavy := _heavy_fighter()
	heavy.locomotion_force = light.locomotion_force
	heavy.braking_force = light.braking_force
	heavy.burst_force = light.burst_force
	var a := FighterState.new()
	var b := FighterState.new()
	## ACT: one tick of forward footwork each.
	DuelFixture.spar(a, 0.0, 1.0, light)
	DuelFixture.spar(b, 0.0, 1.0, heavy)
	## ASSERT
	assert_true(a.speed() > b.speed() and b.speed() > 0.0, "the lighter body gains more speed (%.4f vs %.4f m/s)" % [a.speed(), b.speed()])
	assert_near(a.speed() / b.speed(), heavy.mass / light.mass, 1e-9, "in exactly the inverse ratio of the masses")


## α = τ/M_θ: the same drive turns the lighter weapon faster, through the one
## motor, from each held weapon's own inertia.
func test_the_same_torque_turns_the_lighter_weapon_faster() -> void:
	## ARRANGE: a heterogeneous duel, both arms perturbed to the same drive,
	## both swords launching a tap from rest at the same angle.
	var light := _light()
	var heavy := _heavy()
	light.fighter.weapon_torque_scale = 1.0
	heavy.fighter.weapon_torque_scale = 1.0
	var rules := DuelFixture.with_loadouts(light, heavy)
	var state := DuelFixture.state(rules)
	var angle := deg_to_rad(-45.0)
	for slot in 2:
		var w := state.fighter(slot).weapon
		w.reset(angle)
		w.phase = CombatPhase.Id.LAUNCH
		w.swing_dir = 1.0
		w.swing_charge = 0.0
		w.launch_preparation = 1.0
		w.swing_start = angle
		w.swing_end = angle + rules.combatant(slot).weapon.arc(0.0)
	var events: Array[DuelEvent] = []
	## ACT: one motor tick each.
	for slot in 2:
		WeaponSystem.step(state.fighter(slot), rules, 0, events)
	## ASSERT
	var dt := SimulationTimebase.TICK_SECONDS
	var light_speed := absf(state.fighter(0).weapon.speed)
	var heavy_speed := absf(state.fighter(1).weapon.speed)
	assert_true(light_speed > heavy_speed and heavy_speed > 0.0, "the lighter sword gains more speed (%.3f vs %.3f rad/s)" % [light_speed, heavy_speed])
	assert_near(light_speed / dt * WeaponKinematics.motor_inertia(light, angle), light.weapon.swing_torque_tap, 1e-9, "each divides the same torque by its own M_θ (light)")
	assert_near(heavy_speed / dt * WeaponKinematics.motor_inertia(heavy, angle), heavy.weapon.swing_torque_tap, 1e-9, "and (heavy)")


## One contact, both sides' own masses: the light attacker's held sword and
## body, and the heavy target's body — no averaged or reference mass.
func test_one_contact_solve_uses_each_sides_own_masses() -> void:
	## ARRANGE: the light fighter's blade on the heavy fighter's torso.
	var rules := DuelFixture.with_loadouts(_light(), _heavy())
	var state := DuelFixture.state(rules)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	DuelFixture.place(target, 1.2, 0.3, PI)
	attacker.weapon.angle = 0.0
	attacker.weapon.speed = 8.0
	var pose := WeaponKinematics.pose_of(attacker, rules.combatant(0), BladePose.new())
	var r := (rules.combatant(0).weapon.blade_base_radius + rules.combatant(0).weapon.tip_radius) * 0.5
	## ACT
	var impact := ImpactModel.resolve(attacker, target, pose.point_x(r), pose.point_y(r), rules)
	## ASSERT
	assert_eq(impact.attacker_mass, 60.0, "the attacker answers with its own body")
	assert_eq(impact.target_mass, 105.0, "the target with its own")
	var held := WeaponKinematics.held_inertia(rules.combatant(0), pose)
	assert_near(impact.weapon_inertia, held, 1e-12, "and the attacker's own held sword")
	var expected := 1.0 / 60.0 + 1.0 / 105.0 + impact.lever_cross * impact.lever_cross / held
	assert_near(impact.inverse_effective_mass, expected, 1e-12, "k = 1/m_attacker + 1/m_target + c²/M_θ")
	## PERTURB: the same blade with a reference-mass target is a different contact.
	var reference_spec := DuelFixture.with_loadouts(rules.combatant(0), LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD))
	var baseline := ImpactModel.resolve(attacker, target, pose.point_x(r), pose.point_y(r), reference_spec)
	assert_true(baseline.inverse_effective_mass > impact.inverse_effective_mass, "a lighter target makes a softer contact: the heavy body is really in the solve")


## Reach is the attacker's weapon against the target's torso: at a measure
## between the two reaches only the long sword's body contact exists.
func test_only_the_long_weapon_reaches_between_the_two_reaches() -> void:
	## ARRANGE
	var rules := DuelFixture.with_loadouts(_light(), _heavy())
	var light_reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var heavy_reach := WeaponKinematics.strike_reach(rules.combatant(1), rules.combatant(0))
	assert_true(heavy_reach > light_reach + 0.2, "fixture: the long sword out-reaches the short one (%.3f vs %.3f m)" % [heavy_reach, light_reach])
	var measure := (light_reach + heavy_reach) * 0.5
	## ACT: each sword in Long Guard down the line in turn, the other fighter
	## turned side-on so its own sword and hands are off the line — a
	## centreline point otherwise meets the opponent's hands before the torso,
	## which is the contact physics' business, not this reach test's.
	var heavy_aims := _reach_report(rules, measure, 1)
	var light_aims := _reach_report(rules, measure, 0)
	## ASSERT
	assert_false(heavy_aims.blade or light_aims.blade, "fixture: the swords do not touch")
	assert_true(heavy_aims.body[1], "the long sword in Long Guard reaches the light torso at %.3f m" % measure)
	assert_false(light_aims.body[0], "the short sword cannot reach the heavy torso from there")
	## PERTURB: the same two scenes, read by the threat estimate — the light
	## fighter's must close the gap first. (Both in Long Guard on one line the
	## swords would lie through each other, a state no tick reaches; each
	## target stands side-on, as above.)
	var light_threat := _threat_down_the_line(rules, measure, 0)
	var heavy_threat := _threat_down_the_line(rules, measure, 1)
	assert_true(heavy_threat < light_threat, "so the long sword threatens first (%.3f vs %.3f s)" % [heavy_threat, light_threat])


## `aimer`'s time to threaten the other fighter (`InitiativeModel`) with its
## sword in Long Guard down the line at `measure`, the other side-on.
func _threat_down_the_line(rules: DuelRules, measure: float, aimer: int) -> float:
	var state := DuelFixture.state(rules)
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0 if aimer == 0 else PI / 2.0)
	DuelFixture.place(state.fighter(1), measure, 0.0, PI if aimer == 1 else PI / 2.0)
	state.fighter(0).weapon.angle = 0.0
	state.fighter(1).weapon.angle = 0.0
	return InitiativeModel.time_to_threat(state.fighter(aimer), state.fighter(1 - aimer), rules)


## The collision report with `aimer`'s sword in Long Guard down the line at
## `measure` and the other fighter facing side-on, its sword pointing away.
func _reach_report(rules: DuelRules, measure: float, aimer: int) -> ContactReport:
	var state := DuelFixture.state(rules)
	var light := state.fighter(0)
	var heavy := state.fighter(1)
	DuelFixture.place(light, 0.0, 0.0, 0.0 if aimer == 0 else PI / 2.0)
	DuelFixture.place(heavy, measure, 0.0, PI if aimer == 1 else PI / 2.0)
	light.weapon.angle = 0.0
	heavy.weapon.angle = 0.0
	var poses := ContactFixture.poses(FighterPose.capture(light, rules.combatant(0)), FighterPose.capture(heavy, rules.combatant(1)))
	var report := ContactReport.new()
	state.blade_contact.begin_search()
	CollisionSystem.new().detect(state, poses, poses, rules, state.blade_contact, report)
	return report


## The duel's canonical symmetry is the point reflection through the arena
## centre. Reflect the world and swap the specs (and the pilots with them): the
## result is the exact reflection with the actors exchanged — so no system
## favours a slot or quietly reads the reference fighter.
func test_a_reflected_world_with_swapped_specs_is_the_exact_reflection() -> void:
	## ARRANGE
	var light := _light()
	var heavy := _heavy()
	var tap := WeaponKinematics.strike_reach(light, heavy) * 0.95
	var first := _duel(light, heavy, Pilot.approach_and_tap(tap), Pilot.idle())
	var swapped := _duel(heavy, light, Pilot.idle(), Pilot.approach_and_tap(tap))
	## Precondition: something physical happened to compare.
	assert_true(first.count(DuelEventTypes.ATTACK_RELEASED) > 0, "fixture: attacks were thrown")
	assert_true(first.count(DuelEventTypes.BLADE_CONTACT) + first.count(DuelEventTypes.BODY_HIT) + first.count(DuelEventTypes.BODY_PUSH) > 0, "fixture: the bodies or blades met")
	assert_true(first.is_sound() and swapped.is_sound(), "both duels stay legal (%s / %s)" % [first.violation_summary(), swapped.violation_summary()])
	## ASSERT: each fighter in the swapped duel is the reflection of its twin.
	for slot in 2:
		var twin := first.state.fighter(1 - slot)
		var me := swapped.state.fighter(slot)
		assert_near(me.x, -twin.x, 1e-6, "slot %d is its twin reflected (x)" % slot)
		assert_near(me.y, -twin.y, 1e-6, "slot %d is its twin reflected (y)" % slot)
		assert_near(SimMath.wrap_angle(me.facing - twin.facing - PI), 0.0, 1e-6, "slot %d faces its twin's heading turned half round" % slot)
		assert_near(me.weapon.angle, twin.weapon.angle, 1e-6, "slot %d holds its twin's weapon angle" % slot)
		assert_near(me.health, twin.health, 1e-6, "slot %d has its twin's health" % slot)
	assert_eq(swapped.count(DuelEventTypes.BODY_HIT), first.count(DuelEventTypes.BODY_HIT), "the same hits land")
	## PERTURB: the reflection without the spec swap is not the same duel.
	var unswapped := _duel(light, heavy, Pilot.idle(), Pilot.approach_and_tap(tap))
	var gap := absf(unswapped.state.fighter(0).x + first.state.fighter(1).x) + absf(unswapped.state.fighter(0).y + first.state.fighter(1).y)
	assert_true(gap > 1e-3, "control: keeping the specs on their slots breaks the reflection (%.4f m)" % gap)


## ASYMMETRIC-MASS-001: both fighters driving into each other — a Light and a
## Heavy pressing through their swords and bodies — is slot-independent too:
## swap the specs and reflect the world, and every body, heading and sword is
## its twin's reflection on every tick. Both move, so a fighter stepped second
## that steered by where the first had already gone would show here.
func test_a_heterogeneous_press_is_slot_independent() -> void:
	## ARRANGE
	var light := _light()
	var heavy := _heavy()
	var first := SimRunner.create(DuelFixture.with_loadouts(light, heavy), 3)
	var swapped := SimRunner.create(DuelFixture.with_loadouts(heavy, light), 3)
	first.skip_intro()
	swapped.skip_intro()
	## ACT
	var worst := 0.0
	for _i in 240:
		first.drive(0.0, 1.0, 1)
		swapped.drive(0.0, 1.0, 1)
		for slot in 2:
			var twin := first.state.fighter(1 - slot)
			var me := swapped.state.fighter(slot)
			worst = maxf(worst, absf(me.x + twin.x) + absf(me.y + twin.y) + absf(me.vx + twin.vx) + absf(me.vy + twin.vy) + absf(me.weapon.angle - twin.weapon.angle))
	## ASSERT
	assert_true(first.count(DuelEventTypes.BLADE_CONTACT) + first.count(DuelEventTypes.BODY_PUSH) > 0, "fixture: they pressed into each other")
	assert_true(first.is_sound() and swapped.is_sound(), "both stay legal (%s / %s)" % [first.violation_summary(), swapped.violation_summary()])
	assert_true(worst < 1.0e-6, "every tick is the exact reflection with the actors exchanged (%s)" % String.num_scientific(worst))


func _duel(first: CombatantPhysicsSpec, second: CombatantPhysicsSpec, pilot_0: Pilot, pilot_1: Pilot) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.with_loadouts(first, second), 3)
	runner.run(pilot_0, pilot_1, 300)
	return runner


## One body, two weapons: choosing the other weapon (and its handling) changes
## exactly what the weapon and the pairing own, and nothing the body owns.
func test_another_weapon_changes_only_what_the_weapon_owns() -> void:
	## ARRANGE
	var body := _light_fighter()
	var long_spec := _spec(body, _long_weapon(body))
	var short_spec := _spec(body, _short_weapon(body))
	assert_eq(long_spec.problem(), "", "fixture: the light body can hold the long sword")
	assert_true(long_spec.fighter == short_spec.fighter, "fixture: one body object")
	## ACT
	var long_inertia := WeaponKinematics.motor_inertia(long_spec, 0.0)
	var short_inertia := WeaponKinematics.motor_inertia(short_spec, 0.0)
	## ASSERT: weapon-owned quantities move.
	assert_true(long_inertia > short_inertia, "the long sword is harder to turn")
	assert_true(WeaponKinematics.forward_reach(long_spec) > WeaponKinematics.forward_reach(short_spec), "and reaches further")
	assert_ne(ContactMechanics.percussion_radius(long_spec.weapon), ContactMechanics.percussion_radius(short_spec.weapon), "and has its own centre of percussion")
	assert_ne(long_spec.fingerprint(), short_spec.fingerprint(), "and resolves to different content")
	## Body-owned quantities do not.
	var a := FighterState.new()
	var b := FighterState.new()
	DuelFixture.spar(a, 0.0, 1.0, long_spec.fighter)
	DuelFixture.spar(b, 0.0, 1.0, short_spec.fighter)
	assert_eq(a.speed(), b.speed(), "the body accelerates exactly the same")
	assert_eq(long_spec.fighter.moment_of_inertia(), short_spec.fighter.moment_of_inertia(), "and turns the same")


## LOADOUT-001: a pairing nobody authored fails closed, and a handling made for
## another fighter is refused — never a fallback to someone else's track.
func test_an_unauthored_pairing_fails_closed() -> void:
	## ARRANGE + ACT
	var unknown_weapon := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, &"weapon.nothing")
	var unknown_fighter := LoadoutCatalog.compile(&"fighter.nobody", ContentIds.WEAPON_BASTARD_SWORD)
	var light := _light_fighter()
	var unpaired := LoadoutCatalog.assemble(light, _short_weapon(light))
	## ASSERT
	assert_true(unknown_weapon == null and unknown_fighter == null, "unknown ids yield nothing")
	assert_true(unpaired == null, "a pair with no authored handling yields nothing")
	var rules := StandardDuelRules.with_combatants(ContentIds.FIGHTER_DUELIST, &"weapon.nothing", ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	assert_true(rules.problem().contains("combatant 0"), "the rules name the missing combatant (%s)" % rules.problem())
	assert_true(DuelSimulation.create(rules) == null, "and no duel starts")
	## PERTURB: Wolf's handling handed to another fighter is refused.
	var reference_spec := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	var borrowed := CombatantPhysicsSpec.compile(light, _short_weapon(light), reference_spec.handling)
	assert_true(borrowed.problem().contains("authored for"), "a borrowed track is refused (%s)" % borrowed.problem())


## The replay header pins each slot's loadout: the same ids over different
## content are refused, never reinterpreted.
func test_the_replay_header_pins_each_loadout() -> void:
	## ARRANGE
	var rules := DuelFixture.with_loadouts(_light(), _heavy())
	var runner := SimRunner.create(rules, 7)
	runner.run(Pilot.wander(7, 1), Pilot.wander(7, 2), 120)
	## ACT
	var record := ReplayRecord.from_dictionary(runner.record.to_dictionary())
	## ASSERT
	assert_true(record != null, "the header survives serialization")
	assert_eq(record.combatants.size(), 2, "one loadout per slot")
	assert_eq(record.combatants[0][0], String(LIGHT_ID), "slot 0's character")
	assert_eq(record.combatants[1][1], String(LONG_ID), "slot 1's weapon")
	assert_eq(record.combatants[1][2], String(HANDLING_ID), "and its handling")
	assert_eq(ReplayVerifier.verify(record, DuelFixture.with_loadouts(_light(), _heavy())), ReplayVerifier.VERIFIED, "the same content verifies")
	## PERTURB: one kilogram on the heavy fighter under the same ids.
	var retuned := DuelFixture.with_loadouts(_light(), _heavy())
	retuned.combatant(1).fighter.mass += 1.0
	assert_eq(ReplayVerifier.verify(record, retuned), ReplayVerifier.RULES_MISMATCH, "different content under the same ids is refused")
	var exchanged := DuelFixture.with_loadouts(_heavy(), _light())
	assert_eq(ReplayVerifier.verify(record, exchanged), ReplayVerifier.RULES_MISMATCH, "and so are the loadouts on the other slots")


## A heterogeneous duel is an ordinary duel: legal every tick, deterministic.
func test_a_heterogeneous_duel_is_legal_and_deterministic() -> void:
	## ARRANGE + ACT
	var first := _wandering(23)
	var second := _wandering(23)
	## ASSERT
	assert_true(first.count(DuelEventTypes.BLADE_CONTACT) + first.count(DuelEventTypes.BODY_HIT) > 0, "fixture: the duel has contacts")
	assert_true(first.is_sound(), "every tick satisfies the invariants (%s)" % first.violation_summary())
	assert_eq(StateHasher.hash_state(second.state), StateHasher.hash_state(first.state), "and two runs are one duel")
	first.seal()
	assert_eq(ReplayVerifier.verify(first.record, DuelFixture.with_loadouts(_light(), _heavy())), ReplayVerifier.VERIFIED, "the recording verifies")


func _wandering(seed_value: int) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.with_loadouts(_light(), _heavy()), seed_value)
	runner.run(Pilot.wander(seed_value, 1), Pilot.wander(seed_value, 2), 1500)
	return runner
