extends TestCase

## AUTHORITY: one impact-authority dip per new steel episode, from that
## sword's own contact-caused change in angular velocity (IMPACT-AUTHORITY-001,
## rules 57). A shared normal impulse is not the measure. A torso entry is
## not a dip. Holds of the same episode do not dip again; they recover.
## A real separation and a later contact can dip again. Between dips the
## deficit fades at the guard return's natural frequency, and a tick that
## dipped does not also recover.
##
## Implements: /spec/invariants.md#impact-authority-001
## See also: /docs/reference/testing.md

const CLASH_DISTANCE := 2.1
const CLASH_SPEED := 6.0


func _init() -> void:
	suite_name = "AUTHORITY"


func test_a_speed_change_dips_once_and_compounds_to_the_floor() -> void:
	var floor_value := 0.5
	var full := 18.0
	assert_eq(ImpactAuthority.after_episode(1.0, 0.0, full, floor_value), 1.0, "a positive impulse is not an input: zero angular change does not dip")
	assert_eq(ImpactAuthority.after_episode(1.0, 4.0, 0.0, floor_value), 1.0, "a sword with no swing speed is left alone")
	var dipped := ImpactAuthority.after_episode(1.0, -4.0, full, floor_value)
	assert_eq(dipped, ImpactAuthority.after_episode(1.0, 4.0, full, floor_value), "the sign of the speed change is not a side")
	var share := 4.0 / (4.0 + full)
	assert_eq(dipped, maxf(floor_value, 1.0 * (1.0 - share)), "the dip is authority · (1 − |Δθ̇| / (|Δθ̇| + ω_full)), not a subtraction of the share")
	assert_true(dipped < 1.0 and dipped > floor_value, "a modest change dips and stays above the floor (%.3f)" % dipped)
	var again := ImpactAuthority.after_episode(dipped, 4.0, full, floor_value)
	assert_eq(again, maxf(floor_value, dipped * (1.0 - share)), "a second episode compounds by the same multiply")
	var floored := ImpactAuthority.after_episode(1.0, 80.0, full, floor_value)
	assert_eq(floored, floor_value, "a large change stops at the floor")
	assert_eq(ImpactAuthority.after_episode(floor_value, 80.0, full, floor_value), floor_value, "and another dip stays there")


func test_authority_multiplies_the_return_and_stamina_does_not() -> void:
	var rules := DuelFixture.rules()
	var full := _returning(rules, 1.0, 1.0)
	var tired := _returning(rules, 1.0, 0.0)
	var dipped := _returning(rules, rules.combat.impact_authority_floor, 1.0)
	var tired_dipped := _returning(rules, rules.combat.impact_authority_floor, 0.0)
	assert_true(absf(full) > absf(dipped), "half authority returns less in one tick (%.4f vs %.4f rad)" % [full, dipped])
	assert_eq(tired, full, "empty stamina does not change the return")
	assert_eq(tired_dipped, dipped, "and it does not change a dipped return either")


func test_recovery_closes_the_deficit_at_the_guard_frequency() -> void:
	var wn := 6.0
	var dt := 1.0 / 60.0
	var step := 1.0 - SimMath.exp_minus(wn * dt)
	assert_near(step, 0.0951625819640405, 1e-12, "exp(−0.1) is the reduced series, not a platform exp")
	assert_near(ImpactAuthority.recover(0.5, wn, dt), 0.5 + 0.5 * step, 1e-12, "one tick is the integral of da/dt = ωn·(1 − a)")
	assert_eq(ImpactAuthority.recover(1.0, wn, dt), 1.0, "full authority stays full")
	assert_true(ImpactAuthority.recover(0.5, wn, dt) > 0.5, "recovery leaves the floor; the floor binds a dip only")
	assert_true(ImpactAuthority.recover(0.5, 1000.0, 10.0) <= 1.0, "recovery cannot pass 1")
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	runner.state.fighter(0).impact_authority = 0.5
	runner.idle(1)
	var once := ImpactAuthority.recover(0.5, rules.combat.guard_return_natural_frequency, SimulationTimebase.TICK_SECONDS)
	assert_near(runner.state.fighter(0).impact_authority, once, 1e-12, "a quiet living tick recovers once")
	runner.idle(1)
	assert_near(runner.state.fighter(0).impact_authority, ImpactAuthority.recover(once, rules.combat.guard_return_natural_frequency, SimulationTimebase.TICK_SECONDS), 1e-12, "the next tick recovers from the new value, not twice from the old one")


func test_authority_does_not_scale_swing_brake_or_footwork() -> void:
	var open := _driven(1.0)
	var slow := _driven(0.5)
	assert_eq(open["swing"], slow["swing"], "a swing tick does not read impact authority")
	assert_eq(open["brake"], slow["brake"], "a brake tick does not read it")
	assert_eq(open["x"], slow["x"], "footwork does not read it")
	assert_eq(open["stamina"], slow["stamina"], "the stamina settle does not read it")


func test_a_steel_opening_dips_the_side_the_speed_change_hit() -> void:
	var runner := _cut(1.0)
	for _tick in 24:
		runner.idle(1)
		if runner.count(DuelEventTypes.BLADE_CONTACT) > 0:
			break
	var clash := runner.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(clash != null, "fixture: the cut meets steel")
	if clash == null:
		return
	assert_true(clash.number(DuelEventKeys.IMPULSE) > 0.0, "fixture: one shared normal impulse")
	var delta_0 := clash.number(DuelEventKeys.DELTA_0)
	var delta_1 := clash.number(DuelEventKeys.DELTA_1)
	var floor_value := runner.rules.combat.impact_authority_floor
	var expect_0 := ImpactAuthority.after_episode(1.0, delta_0, runner.rules.combatant(0).weapon.swing_speed_full, floor_value)
	var expect_1 := ImpactAuthority.after_episode(1.0, delta_1, runner.rules.combatant(1).weapon.swing_speed_full, floor_value)
	var auth_0 := runner.state.fighter(0).impact_authority
	var auth_1 := runner.state.fighter(1).impact_authority
	assert_near(auth_0, expect_0, 1e-9, "sword 0 takes one dip from its own solved Δθ̇, however many manifold points (%.0f)" % clash.number(DuelEventKeys.POINT_COUNT))
	assert_near(auth_1, expect_1, 1e-9, "sword 1 takes one dip from its own solved Δθ̇")
	assert_true(expect_0 < 1.0 or expect_1 < 1.0, "fixture: the solve changed at least one sword's angular velocity")
	assert_true(absf(absf(delta_0) - absf(delta_1)) > 0.05, "fixture: the two solved responses differ (%.3f vs %.3f)" % [delta_0, delta_1])
	if absf(delta_0) > absf(delta_1):
		assert_true(auth_0 < auth_1, "the larger angular response dipped further (%.3f vs %.3f)" % [auth_0, auth_1])
	else:
		assert_true(auth_1 < auth_0, "the larger angular response dipped further (%.3f vs %.3f)" % [auth_1, auth_0])
	if absf(delta_0) == 0.0:
		assert_eq(auth_0, 1.0, "a positive impulse with no angular change leaves sword 0 alone")
	else:
		var recovered_0 := ImpactAuthority.recover(expect_0, runner.rules.combat.guard_return_natural_frequency, SimulationTimebase.TICK_SECONDS)
		assert_true(absf(auth_0 - recovered_0) > 1e-6, "the dip tick does not also recover")
	var held_0 := auth_0
	var held_1 := auth_1
	var held_ticks := 0
	for _tick in 4:
		if runner.state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			break
		runner.idle(1)
		held_ticks += 1
	assert_true(held_ticks > 0, "fixture: the episode is still held after the opening")
	var wn := runner.rules.combat.guard_return_natural_frequency
	var dt := SimulationTimebase.TICK_SECONDS
	var later_0 := held_0
	var later_1 := held_1
	for _i in held_ticks:
		later_0 = ImpactAuthority.recover(later_0, wn, dt)
		later_1 = ImpactAuthority.recover(later_1, wn, dt)
	assert_near(runner.state.fighter(0).impact_authority, later_0, 1e-9, "a later hold recovers; it does not dip again")
	assert_near(runner.state.fighter(1).impact_authority, later_1, 1e-9, "nor the other sword")
	assert_true(runner.state.fighter(0).impact_authority + 1e-12 >= held_0, "the hold did not compound the dip")


func test_a_resting_overlap_does_not_dip_and_an_open_episode_does_not_either() -> void:
	var rules := DuelFixture.revolute_rules()
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, PI / 2.0, deg_to_rad(45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), 0.0, ContactFixture.crossed_guard_separation(spec, -0.01), -PI / 2.0, deg_to_rad(-45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	runner.idle(1)
	assert_true(runner.state.blade_contact.phase != SwordContactSet.Phase.SEPARATED, "fixture: the resting blades are in contact")
	assert_eq(runner.state.fighter(0).impact_authority, 1.0, "a resting overlap does not dip")
	assert_eq(runner.state.fighter(1).impact_authority, 1.0, "nor the other sword")
	runner.state.blade_contact.phase_ticks = 4
	runner.state.fighter(0).weapon.speed = 4.0
	runner.idle(2)
	assert_eq(runner.state.fighter(0).impact_authority, 1.0, "an episode already open does not dip when the solve still pushes")
	assert_eq(runner.state.fighter(1).impact_authority, 1.0, "nor the sword it pushes against")


func test_a_separated_pair_that_meets_again_dips_again() -> void:
	var runner := _cut(1.0)
	for _tick in 24:
		runner.idle(1)
		if runner.count(DuelEventTypes.BLADE_CONTACT) > 0:
			break
	assert_true(runner.count(DuelEventTypes.BLADE_CONTACT) > 0, "fixture: the first episode lands")
	var once := minf(runner.state.fighter(0).impact_authority, runner.state.fighter(1).impact_authority)
	assert_true(once < 1.0, "fixture: the first episode dipped")
	var weapon := runner.rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), 4.0, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var parted := false
	for _tick in 8:
		runner.idle(1)
		if runner.state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			parted = true
			break
	assert_true(parted, "fixture: the blades have parted")
	var parted_0 := runner.state.fighter(0).impact_authority
	var parted_1 := runner.state.fighter(1).impact_authority
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-110.0), CLASH_SPEED, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), CLASH_DISTANCE, 0.0, PI, deg_to_rad(30.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var again := false
	for _tick in 24:
		runner.idle(1)
		if runner.state.fighter(0).impact_authority < parted_0 or runner.state.fighter(1).impact_authority < parted_1:
			again = true
			break
	assert_true(again, "a new episode after a real separation dips again")


func test_a_torso_entry_does_not_dip_either_sword() -> void:
	var rules := DuelFixture.revolute_rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var weapon := rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, 0.0, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, weapon)
	var target := runner.state.fighter(1)
	ContactFixture.arm(target, 0.9, 0.35, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var hit := false
	for _tick in 20:
		runner.idle(1)
		if runner.count(DuelEventTypes.BODY_HIT) > 0:
			hit = true
			break
	assert_true(hit, "fixture: the blade enters the torso")
	assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT), 0, "fixture: the defender's sword is not in the way")
	assert_eq(runner.state.fighter(0).impact_authority, 1.0, "a torso entry is not an authority episode")
	assert_eq(runner.state.fighter(1).impact_authority, 1.0, "nor is the sword that was not struck")


func test_the_mirror_of_a_cut_dips_the_same() -> void:
	var left := _played_cut(1.0)
	var right := _played_cut(-1.0)
	assert_true(left.count(DuelEventTypes.BLADE_CONTACT) > 0 and right.count(DuelEventTypes.BLADE_CONTACT) > 0, "fixture: both chiralities meet steel")
	assert_near(left.state.fighter(0).impact_authority, right.state.fighter(0).impact_authority, 1e-9, "the striker's dip mirrors")
	assert_near(left.state.fighter(1).impact_authority, right.state.fighter(1).impact_authority, 1e-9, "and the defender's")


## The estimate copies the swords and writes the stop into its own buffers.
## A blade already in the arrival band, and the other sword swept with it,
## still leaves the hashed duel where it was.
func test_a_prediction_does_not_write_the_duel() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	var weapon := rules.combatant(0).weapon
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	DuelFixture.place(target, 1.4, 0.35, PI)
	attacker.weapon.angle = weapon.guard_limit - WeaponSystem.STOP_ARRIVAL_RAD * 0.5
	attacker.weapon.speed = 6.0
	attacker.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	attacker.weapon.stable_side = 1.0
	target.weapon.angle = -weapon.guard_limit + WeaponSystem.STOP_ARRIVAL_RAD * 0.5
	target.weapon.speed = -4.0
	target.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	target.weapon.stable_side = -1.0
	var before := StateHasher.hash_state(state)
	var angle := attacker.weapon.angle
	var speed := attacker.weapon.speed
	var their_angle := target.weapon.angle
	var their_speed := target.weapon.speed
	InitiativeModel.estimate(attacker, rules.combatant(0), target, rules.combatant(1), rules.combat, ThreatEstimate.new(), ThreatContinuation.planted(true))
	assert_eq(StateHasher.hash_state(state), before, "the estimate does not change the hashed state")
	assert_eq(attacker.weapon.angle, angle, "the attacker's angle is the one the estimate copied")
	assert_eq(attacker.weapon.speed, speed, "and so is its speed")
	assert_eq(target.weapon.angle, their_angle, "the swept target's angle is untouched")
	assert_eq(target.weapon.speed, their_speed, "and so is its speed")


func test_a_dipped_blade_is_predicted_with_its_authority() -> void:
	var rules := DuelFixture.rules()
	var open := _predicted(rules, 1.0)
	var slow := _predicted(rules, rules.combat.impact_authority_floor)
	assert_true(slow.hit_time > open.hit_time or slow.residual_gap > open.residual_gap, "lower authority leaves the point later or farther (%.3f s / %.3f m vs %.3f s / %.3f m)" % [slow.hit_time, slow.residual_gap, open.hit_time, open.residual_gap])


func _predicted(rules: DuelRules, authority: float) -> ThreatEstimate:
	var state := DuelFixture.state(rules)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	var weapon := rules.combatant(0).weapon
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	DuelFixture.place(target, 0.70, -0.55, PI)
	## Still above control, so the predictor coasts the return before it may
	## strike. A stopped blade is already ready and the swing ignores authority.
	attacker.weapon.angle = 0.9
	attacker.weapon.speed = weapon.control_speed + 4.0
	attacker.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	attacker.weapon.stable_side = -1.0
	attacker.impact_authority = authority
	return InitiativeModel.estimate(attacker, rules.combatant(0), target, rules.combatant(1), rules.combat, ThreatEstimate.new(), ThreatContinuation.planted())


func test_authority_is_hashed_projected_and_reset_with_the_round() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var before := StateHasher.hash_state(state)
	state.fighter(0).impact_authority = 0.75
	assert_ne(StateHasher.hash_state(state), before, "the field is in the hash")
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(row.impact_authority, 0.75, "and in the snapshot")
	DuelSetup.reset_round(state, rules)
	assert_eq(state.fighter(0).impact_authority, 1.0, "a new round starts full")
	state.fighter(1).impact_authority = 0.2
	assert_eq(StateInvariants.check(state, rules), StateInvariants.IMPACT_AUTHORITY_RANGE, "below the floor is not a state")
	state.fighter(1).impact_authority = 1.2
	assert_eq(StateInvariants.check(state, rules), StateInvariants.IMPACT_AUTHORITY_RANGE, "above 1 is not a state")
	state.fighter(1).impact_authority = NAN
	assert_eq(StateInvariants.check(state, rules), StateInvariants.IMPACT_AUTHORITY_RANGE, "a non-finite value is not a state")
	state.fighter(1).impact_authority = 1.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "fixture: the repaired state is sound")


func _returning(rules: DuelRules, authority: float, stamina: float) -> float:
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	var blade := runner.state.fighter(0).weapon
	blade.angle = 0.0
	blade.speed = 0.0
	runner.state.fighter(0).impact_authority = authority
	runner.state.fighter(0).stamina = stamina
	runner.idle(1)
	return blade.angle


func _cut(side: float) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.rules(), 5)
	runner.skip_intro()
	var weapon := runner.rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, side * deg_to_rad(-110.0), side * CLASH_SPEED, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), CLASH_DISTANCE, 0.0, PI, side * deg_to_rad(30.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return runner


func _played_cut(side: float) -> SimRunner:
	var runner := _cut(side)
	for _tick in 24:
		runner.idle(1)
		if runner.count(DuelEventTypes.BLADE_CONTACT) > 0:
			break
	return runner


func _driven(authority: float) -> Dictionary:
	var rules := DuelFixture.rules()
	var swing := SimRunner.create(rules, 1)
	swing.skip_intro()
	var weapon := rules.combatant(0).weapon
	ContactFixture.arm(swing.state.fighter(0), 0.0, 0.0, 0.0, 0.4, 2.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, weapon)
	swing.state.fighter(0).impact_authority = authority
	swing.idle(1)
	var braking := SimRunner.create(rules, 1)
	braking.skip_intro()
	ContactFixture.arm(braking.state.fighter(0), 0.0, 0.0, 0.0, 0.4, weapon.control_speed + 4.0, CombatPhase.Id.OVERSWING, 0.5, weapon)
	braking.state.fighter(0).impact_authority = authority
	braking.idle(1)
	var walking := SimRunner.create(rules, 1)
	walking.skip_intro()
	walking.state.fighter(0).impact_authority = authority
	walking.drive(1.0, 0.0, 5)
	return {
		"swing": swing.state.fighter(0).weapon.speed,
		"brake": braking.state.fighter(0).weapon.speed,
		"x": walking.state.fighter(0).x,
		"stamina": swing.state.fighter(0).stamina,
	}
