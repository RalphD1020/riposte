extends TestCase

## RULES: standard content is valid and expresses the specified geometry.
##
## See also: /docs/concepts/combat.md


func _init() -> void:
	suite_name = "RULES"


func test_standard_rules_are_valid() -> void:
	var rules := StandardDuelRules.create()
	assert_true(rules.is_valid(), "standard duel rules validate")
	assert_eq(rules.id, ContentIds.RULES_STANDARD_DUEL, "rules id")
	assert_eq(rules.combatant(0).weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "weapon id")
	assert_eq(rules.combatant(0).fighter.id, ContentIds.FIGHTER_DUELIST, "fighter id")
	assert_eq(rules.rounds_to_win, 3, "best of five is first to three")


func test_bastard_sword_geometry_matches_spec() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_near(weapon.length(), 1.22, 1e-12, "1.22 m overall")
	assert_near(weapon.blade_length(), 0.97, 1e-9, "~0.97 m effective blade")
	assert_near(rad_to_deg(weapon.guard_limit) * 2.0, 270.0, 1e-9, "270° coverage")


func test_arc_grows_ninety_degrees_with_charge() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_near(rad_to_deg(weapon.arc(0.0)), 90.0, 1e-9, "tap arc 90°")
	assert_near(rad_to_deg(weapon.arc(0.5)), 135.0, 1e-9, "half charge 135°")
	assert_near(rad_to_deg(weapon.arc(1.0)), 180.0, 1e-9, "full charge 180°")
	assert_near(rad_to_deg(weapon.windback_span()), 90.0, 1e-9, "full charge is bought with 90° of wind-back")
	assert_eq(weapon.earned_charge(weapon.windback_span()), 1.0, "the whole span is full charge")
	assert_eq(weapon.earned_charge(0.0), 0.0, "no travel, no charge")
	assert_near(weapon.windback_baseline(deg_to_rad(20.0)), weapon.guard_angle, 1e-12, "an under-prepared hold must still reach the canonical guard")
	assert_near(weapon.windback_baseline(deg_to_rad(-100.0)), deg_to_rad(100.0), 1e-12, "an over-displaced hold must beat where it started")


## ATTACK-ARC-001: the 270° control domain is not an attack. A full charge
## commands 180° from the guard limit (−135° → +45°); the blade then sweeps on
## into its overswing until its own brake stops it, still inside the domain.
## The left attack is the exact mirror.
func test_the_control_domain_is_not_the_attack_arc() -> void:
	var rules := StandardDuelRules.create()
	var weapon := rules.combatant(0).weapon
	var domain := weapon.guard_limit * 2.0
	## ARRANGE: a full charge wound back on each side.
	var swings := {}
	for side: float in [-1.0, 1.0]:
		var rig := WeaponRig.create(rules)
		rig.fighter.weapon.angle = side * weapon.guard_angle
		WeaponSystem.update_stable_side(rig.fighter.weapon, weapon)
		rig.press()
		rig.hold(600)
		assert_eq(rig.fighter.weapon.charge, 1.0, "fixture: full charge on side %+.0f" % side)
		## ACT: release and let the swing run out.
		rig.release()
		var start := rig.fighter.weapon.swing_start
		var finish := rig.fighter.weapon.swing_end
		var from := rig.angles.size()
		rig.step_until_phase(CombatPhase.Id.RECOVERY)
		var reached := start
		for k in range(from, rig.angles.size()):
			reached = maxf(reached, rig.angles[k]) if side < 0.0 else minf(reached, rig.angles[k])
		swings[side] = [start, finish, reached, rig.events_of(DuelEventTypes.ATTACK_RELEASED)[0].number(DuelEventKeys.ARC)]
	## ASSERT
	var right: Array = swings[-1.0]
	var left: Array = swings[1.0]
	assert_near(rad_to_deg(domain), 270.0, 1e-9, "the control domain spans 270°")
	assert_near(rad_to_deg(weapon.arc(1.0)), 180.0, 1e-9, "the largest commanded attack is 180°")
	assert_near(rad_to_deg(right[3]), 180.0, 1e-9, "the released full attack reports 180°")
	assert_near(rad_to_deg(right[0]), -135.0, 1e-9, "a full right attack starts at the guard limit")
	assert_near(rad_to_deg(right[1]), 45.0, 1e-9, "and is commanded to +45°")
	assert_true(right[2] > right[1], "its blade sweeps on past the commanded end into the overswing (%.1f°)" % rad_to_deg(right[2]))
	assert_true(right[2] <= weapon.guard_limit, "and stays inside the domain")
	assert_true(right[2] - right[0] < domain, "so no attack sweeps the whole domain")
	assert_near(left[0], -right[0], 1e-12, "the left attack starts at the mirrored limit")
	assert_near(left[1], -right[1], 1e-12, "is commanded to the mirrored end")
	assert_near(left[2], -right[2], 1e-9, "and overswings to the mirrored angle")


## The Combat Speed Ledger page is the shipped rules, not a memory of them:
## its generated table equals what the rules and the motor give today.
func test_the_speed_ledger_matches_the_rules() -> void:
	## ARRANGE + ACT
	var expected := SpeedLedger.table(StandardDuelRules.create())
	var committed := SpeedLedger.committed()
	## ASSERT
	assert_true(not committed.is_empty(), "the ledger page exists with its markers (%s)" % SpeedLedger.DOC)
	assert_true(expected.contains("| Full attack arc (ATTACK-ARC-001) | ° | 180 |"), "fixture: the generated ledger reads the rules")
	assert_eq(committed, expected, "the ledger page matches the rules — regenerate with tools/speed_ledger.gd -- --write")


func test_inertia_is_mass_times_length_squared() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	var expected := weapon.inertia_coefficient * weapon.mass * weapon.length() * weapon.length()
	assert_near(weapon.moment_of_inertia(), expected, 1e-12, "inertia is k·m·L² about the origin")
	assert_true(weapon.moment_of_inertia() > 0.0, "precondition: a real weapon resists being turned")
	## Sanity against the hand calculation for a rod pivoting about its end:
	## ⅓ × 1.6 × 1.22² ≈ 0.794 kg·m². This blade's mass starts at the hilt
	## rather than the origin, so it sits a little above that — but not
	## anywhere near a different order of magnitude.
	var rod_about_end := PhysicalBaseline.SWORD_MASS_KG * PhysicalBaseline.SWORD_LENGTH_M * PhysicalBaseline.SWORD_LENGTH_M / 3.0
	assert_near(rod_about_end, 0.794, 1e-3, "precondition: the baseline hand calculation is ~0.794 kg·m²")
	assert_between(weapon.moment_of_inertia(), rod_about_end, rod_about_end * 1.5, "the shipped blade is in that neighbourhood")


func test_mass_distribution_is_authored_not_assumed() -> void:
	## The uniform rod must be one authorable case, not a hard-wired law: a
	## tip-heavy weapon of identical length and mass is harder to turn.
	var rod := WeaponCatalog.bastard_sword()
	var tip_heavy := WeaponCatalog.bastard_sword()
	tip_heavy.inertia_coefficient = rod.inertia_coefficient * 1.5
	assert_true(tip_heavy.moment_of_inertia() > rod.moment_of_inertia(), "a tip-heavy blade has more inertia")
	var duelist := FighterCatalog.duelist()
	var rod_inertia := WeaponKinematics.motor_inertia(CombatantPhysicsSpec.compile(duelist, rod, HandlingCatalog.of(duelist, rod)), 0.0)
	var heavy_inertia := WeaponKinematics.motor_inertia(CombatantPhysicsSpec.compile(duelist, tip_heavy, HandlingCatalog.of(duelist, tip_heavy)), 0.0)
	assert_true(tip_heavy.swing_accel(1.0, 1.0, heavy_inertia) < rod.swing_accel(1.0, 1.0, rod_inertia), "so the same torque accelerates it less")
	assert_true(tip_heavy.brake_accel(1.0, 1.0, heavy_inertia) < rod.brake_accel(1.0, 1.0, rod_inertia), "and arrests it less")


func test_mass_profile_derives_a_uniform_blade_exactly() -> void:
	## ARRANGE: a uniform blade segment of a known mass and span.
	var a := 0.25
	var b := 1.22
	var mass := 1.6
	var profile := WeaponMassProfile.new().add_segment(a, b, mass)
	## ACT + ASSERT: mass, balance point and inertia are the exact rod integrals.
	assert_near(profile.total_mass(), mass, 1e-12, "a uniform segment carries all of its mass")
	assert_near(profile.center_of_mass_radius(), (a + b) * 0.5, 1e-12, "its centre of mass is the midpoint")
	assert_near(profile.moment_of_inertia_about_origin(), mass * (a * a + a * b + b * b) / 3.0, 1e-12, "its inertia about the origin is the rod integral")
	assert_near(profile.inertia_coefficient(b), (a * a + a * b + b * b) / (3.0 * b * b), 1e-12, "and k = I / (m·L²)")


func test_mass_profile_point_mass_sits_where_it_is_placed() -> void:
	## ARRANGE + ACT: a single point mass at a radius.
	var profile := WeaponMassProfile.new().add_point(0.9, 2.0)
	## ASSERT: a point's centre of mass is itself and its inertia is m·r².
	assert_near(profile.total_mass(), 2.0, 1e-12, "a point carries its mass")
	assert_near(profile.center_of_mass_radius(), 0.9, 1e-12, "a point's centre of mass is where it sits")
	assert_near(profile.moment_of_inertia_about_origin(), 2.0 * 0.9 * 0.9, 1e-12, "a point's inertia is m·r²")


func test_mass_profile_distribution_changes_handling_by_itself() -> void:
	## A pommel-weighted sword and a tip-weighted sword of the SAME total mass
	## and length differ only in where the mass sits, and that alone must move
	## the balance point and the inertia (EMERGENT-COMBAT-001) — no coefficient
	## is authored.
	var pommel_heavy := WeaponMassProfile.new().add_point(0.1, 1.0).add_segment(0.25, 1.22, 0.6)
	var tip_heavy := WeaponMassProfile.new().add_segment(0.25, 1.22, 0.6).add_point(1.2, 1.0)
	assert_near(pommel_heavy.total_mass(), tip_heavy.total_mass(), 1e-12, "precondition: same total mass")
	assert_true(pommel_heavy.center_of_mass_radius() < tip_heavy.center_of_mass_radius(), "the pommel-weighted balance point sits nearer the hand")
	assert_true(pommel_heavy.moment_of_inertia_about_origin() < tip_heavy.moment_of_inertia_about_origin(), "and it is easier to turn")


func test_bastard_sword_physics_is_derived_from_its_mass_profile() -> void:
	## ARRANGE: the shipped sword and its authored distribution.
	var weapon := WeaponCatalog.bastard_sword()
	var profile := WeaponCatalog.reference_mass_profile()
	assert_true(weapon.mass_profile != null, "the shipped sword carries its mass distribution")
	## ACT + ASSERT: mass, balance point and k are the distribution's, exactly —
	## one source of physical truth, no hand-copied scalar beside it.
	assert_near(weapon.mass, profile.total_mass(), 1e-15, "its mass is the distribution's")
	assert_near(weapon.center_of_mass_radius, profile.center_of_mass_radius(), 1e-15, "its balance point is the distribution's")
	assert_near(weapon.inertia_coefficient, profile.inertia_coefficient(weapon.tip_radius), 1e-15, "its k is the distribution's")
	assert_near(weapon.moment_of_inertia(), profile.moment_of_inertia_about_origin(), 1e-12, "so I about the pommel is the distribution's second moment")
	assert_true(weapon.is_valid(), "precondition: the derived weapon is valid")
	## PERTURB: overwrite a derived scalar and the weapon must fail validation,
	## so the distribution and the runtime numbers can never disagree.
	weapon.inertia_coefficient *= 1.0 + 1.0e-6
	assert_false(weapon.is_valid(), "a coefficient that no longer matches the distribution is invalid")


func test_held_inertia_adds_the_hands_riding_the_grip() -> void:
	## ARRANGE: the shipped pair, sampled across the hilt track.
	var rules := StandardDuelRules.create()
	var pose := BladePose.new()
	assert_true(rules.combatant(0).fighter.hand_mass > 0.5 and rules.combatant(0).fighter.hand_mass < 1.5, "precondition: about a kilogram of hand and forearm per hand (%.2f kg)" % rules.combatant(0).fighter.hand_mass)
	for degrees: float in [-135.0, -80.0, -45.0, 0.0, 45.0, 80.0, 135.0]:
		WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(degrees), rules.combatant(0), pose)
		## ACT
		var sword := WeaponKinematics.generalized_inertia(rules.combatant(0), pose)
		var held := WeaponKinematics.held_inertia(rules.combatant(0), pose)
		## ASSERT: the hands are point masses on the rigid sword at the grip
		## markers, so they add exactly what a point mass there would.
		var expected := sword
		for r: float in [rules.combatant(0).weapon.offhand_grip_radius, rules.combatant(0).weapon.dominant_grip_radius]:
			var vx := pose.dorigin_x - r * pose.uy
			var vy := pose.dorigin_y + r * pose.ux
			expected += rules.combatant(0).fighter.hand_mass * (vx * vx + vy * vy)
		## (`SimMath`'s deterministic sine/cosine are unit-length to ~1e-10.)
		assert_near(held, expected, 1e-9, "at %+.0f° the hands add m·|dP/dθ|² at each grip point" % degrees)
		assert_true(held > sword, "and a held sword is harder to turn than a loose one")
		assert_true(held < sword * 1.5, "but the sword still dominates (%.3f vs %.3f kg·m²)" % [held, sword])
	## PERTURB: no hands, no extra inertia. More hand mass adds inertia and
	## sheds less speed under the same impulse. The mirror of a pose is the
	## same inertia. The authored kilogram is a content approximation, not a
	## claimed measurement of a hand.
	var light := WeaponKinematics.held_inertia(rules.combatant(0), pose)
	var hand_mass := rules.combatant(0).fighter.hand_mass
	rules.combatant(0).fighter.hand_mass = 0.0
	assert_near(WeaponKinematics.held_inertia(rules.combatant(0), pose), WeaponKinematics.generalized_inertia(rules.combatant(0), pose), 1e-15, "a sword with no hands on it is just the sword")
	rules.combatant(0).fighter.hand_mass = hand_mass * 2.0
	var heavy := WeaponKinematics.held_inertia(rules.combatant(0), pose)
	rules.combatant(0).fighter.hand_mass = hand_mass
	assert_true(heavy > light and light > 0.0, "more reflected grip mass makes the held sword harder to turn")
	var lever := 0.4
	var impulse := 2.0
	assert_true(absf(impulse * lever / heavy) < absf(impulse * lever / light), "the same impulse changes θ̇ less behind the heavier grip")
	for degrees: float in [15.0, 45.0, 80.0, 135.0]:
		var right := BladePose.new()
		var left := BladePose.new()
		WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(degrees), rules.combatant(0), right)
		WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(-degrees), rules.combatant(0), left)
		assert_near(
			WeaponKinematics.held_inertia(rules.combatant(0), right),
			WeaponKinematics.held_inertia(rules.combatant(0), left),
			1e-12,
			"held inertia mirrors at %.0f°" % degrees
		)


func test_motor_accelerations_derive_from_torque_over_inertia() -> void:
	var spec := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	var weapon := spec.weapon
	var inertia := WeaponKinematics.motor_inertia(spec, 0.0)
	assert_near(weapon.swing_accel(0.0, 1.0, inertia), weapon.swing_torque_tap / inertia, 1e-12, "tap swing is τ/M_θ")
	assert_near(weapon.swing_accel(1.0, 1.0, inertia), weapon.swing_torque_full / inertia, 1e-12, "full swing is τ/M_θ")
	assert_near(weapon.brake_accel(0.0, 1.0, inertia), weapon.brake_torque_tap / inertia, 1e-12, "tap brake is τ/M_θ")
	assert_near(weapon.windup_accel(1.0, inertia), weapon.windup_torque / inertia, 1e-12, "wind-back is τ/M_θ")
	assert_near(weapon.hold_accel(1.0, inertia), weapon.hold_torque / inertia, 1e-12, "settling is τ/M_θ")
	assert_true(weapon.brake_accel(0.0, 1.0, inertia) > weapon.brake_accel(1.0, 1.0, inertia), "a full swing is far more reluctant to be arrested than a tap")


## UNIFIED-MASS-001: the weapon coordinate has one inertia. Through the real
## motor step, a swing launched from rest at θ gains exactly `τ·dt / M_θ(θ)` of
## speed in one tick — `M_θ` the held sword's generalized inertia at that pose,
## the very one every contact divides its impulse by — so the motor feels the
## hilt track and the hands as a contact does, and the same torque turns the
## sword at different rates where the track makes it heavier.
func test_the_motor_and_every_contact_share_one_weapon_inertia() -> void:
	var rules := StandardDuelRules.create()
	var weapon := rules.combatant(0).weapon
	var dt := SimulationTimebase.TICK_SECONDS
	var inertias := PackedFloat64Array()
	for degrees: float in [-135.0, -80.0, -45.0, 0.0, 45.0, 80.0, 135.0]:
		var angle := deg_to_rad(degrees)
		var fighter := FighterState.new()
		fighter.health = rules.combatant(0).fighter.max_health
		fighter.weapon.reset(angle)
		var opponent := FighterState.new()
		DuelFixture.place(opponent, 10.0, 0.0, PI)
		var w := fighter.weapon
		w.phase = CombatPhase.Id.LAUNCH
		w.swing_dir = -1.0 if angle > 0.0 else 1.0
		w.swing_charge = 0.0
		w.launch_preparation = 1.0
		w.swing_start = angle
		w.swing_end = angle + w.swing_dir * weapon.arc(0.0)
		w.speed = 0.0
		var events: Array[DuelEvent] = []
		WeaponSystem.step(fighter, rules, 0, events)
		var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle, rules.combatant(0), BladePose.new())
		var contact_inertia := ContactMechanics.weapon_inertia(pose, rules.combatant(0))
		var torque := rules.combatant(0).fighter.weapon_torque_scale * weapon.swing_torque_tap
		assert_near(absf(w.speed) / dt * contact_inertia, torque, 1e-9, "at %.0f° the motor's τ divides by the contact's own M_θ" % degrees)
		inertias.append(contact_inertia)
	assert_near(inertias[0], inertias[6], 1e-12, "the inertia mirrors")
	assert_true(absf(inertias[3] - inertias[6]) > 1e-3, "and is not one constant: the track makes the sword heavier in some poses (%.4f vs %.4f kg·m²)" % [inertias[3], inertias[6]])


func test_tap_threshold_is_in_the_specified_window() -> void:
	var ms := float(WeaponCatalog.bastard_sword().tap_threshold_ticks) * 1000.0 / float(SimulationTimebase.TICK_RATE)
	assert_between(ms, 100.0, 130.0, "tap threshold 100–130 ms")


func test_sweet_spot_is_outer_middle() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(1.0), "outer-middle beats the tip")
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(0.2), "outer-middle beats near the hilt")


func test_broken_rules_fail_validation() -> void:
	var rules := StandardDuelRules.create()
	rules.combatant(0).weapon.tip_radius = rules.combatant(0).weapon.blade_base_radius
	assert_false(rules.is_valid(), "zero-length blade is invalid")
	var empty := DuelRules.new()
	assert_false(empty.is_valid(), "neutral defaults are invalid until content fills them")


func test_damage_curve_is_monotonic_and_nonlinear() -> void:
	var combat := StandardDuelRules.combat_tuning()
	var previous := -1.0
	var first_drop := -1
	for i in range(0, 121):
		var damage := combat.damage_for(float(i) / 100.0)
		if damage < previous and first_drop < 0:
			first_drop = i
		previous = damage
	assert_eq(first_drop, -1, "damage never decreases as quality rises")
	assert_true(combat.damage_for(0.9) - combat.damage_for(0.7) > combat.damage_for(0.3) - combat.damage_for(0.1), "top of curve is steeper")


func test_current_rules_version() -> void:
	var rules := StandardDuelRules.create()
	assert_eq(rules.version, 52, "rules version tracks gameplay-affecting changes (52: each crossguard protects its blade side as a guard-root steel pair)")


## IMPACT-PHYSICS-001 (rules 42): the injury calibration is a named physical
## constant with units, not "whatever the reference strike delivers today".
## Changing the sword's swing speed — or its hilt track — changes what a cut
## delivers, never what the same energy does to a body, so the references do
## not move with it; the reference strike measured on the current mechanics is
## only their witness, and stays close.
func test_the_injury_calibration_is_a_named_physical_constant() -> void:
	var rules := StandardDuelRules.create()
	assert_eq(rules.combat.reference_impulse, StandardDuelRules.REFERENCE_STAGGER_IMPULSE_NS, "the stagger impulse (N·s) is the pinned constant")
	assert_eq(rules.combat.reference_severity, StandardDuelRules.REFERENCE_CUT_ENERGY_J, "and the cut's dissipated energy (J)")
	assert_eq(rules.combat.reference_thrust_severity, StandardDuelRules.REFERENCE_THRUST_ENERGY_J, "and the thrust energy (J)")
	## Perturb the mechanics: the rules-39 hilt track the calibration was
	## measured on. The witness moves with it; the calibration does not.
	var calibrated := StandardDuelRules.create()
	var knots := PackedFloat64Array()
	for degrees in HandlingCatalog.ATTACK_PATH_DEGREES:
		knots.append(deg_to_rad(degrees))
	calibrated.combatant(0).handling.attack_path = WeaponAttackPath.from_carriage_knots(knots, PackedFloat64Array([0.63, 0.615, 0.56, 0.45, 0.30]), PackedFloat64Array([0.0, 0.045, 0.13, 0.18, 0.20]))
	assert_near(ContactMechanics.reference_severity(calibrated.combatant(0), calibrated.combatant(0), calibrated.combat), StandardDuelRules.REFERENCE_STRIKE_ENERGY_J, 1e-9, "on the rules-39 track the reference strike delivers exactly the pinned energy")
	assert_near(ContactMechanics.reference_impulse(calibrated.combatant(0), calibrated.combatant(0), calibrated.combat), StandardDuelRules.REFERENCE_STAGGER_IMPULSE_NS, 1e-9, "and the pinned stagger impulse")
	assert_near(StandardDuelRules.REFERENCE_STRIKE_ENERGY_J / rules.combat.reference_severity, StandardDuelRules.REFERENCE_STRIKE_SEVERITY, 1e-12, "and that strike is the pinned number of reference-quality wounds (rules 49)")
	var witness := ContactMechanics.reference_severity(rules.combatant(0), rules.combatant(0), rules.combat)
	assert_ne(witness, StandardDuelRules.REFERENCE_STRIKE_ENERGY_J, "on today's track the strike delivers a little differently")
	assert_eq(calibrated.combat.reference_severity, rules.combat.reference_severity, "yet the calibration is the same constant")
	assert_between(witness / rules.combat.reference_severity / StandardDuelRules.REFERENCE_STRIKE_SEVERITY, 0.9, 1.1, "the reference strike on today's mechanics is its witness (%.2f J, a %.2f-severity wound)" % [witness, witness / rules.combat.reference_severity])
	assert_between(rules.combat.reference_impulse / ContactMechanics.reference_impulse(rules.combatant(0), rules.combatant(0), rules.combat), 0.9, 1.1, "and the stagger impulse's")
	assert_near(rules.combat.reference_thrust_severity, ContactMechanics.reference_thrust_severity(rules.combatant(0), rules.combatant(0), rules.combat), 1e-6, "a point driven straight in does not see the track at all")


func test_the_hurt_torso_never_exceeds_the_push_footprint() -> void:
	var rules := StandardDuelRules.create()
	assert_true(rules.is_valid(), "fixture: the shipped rules are valid")
	assert_near(rules.combatant(0).fighter.hurt_radius, PhysicalBaseline.TORSO_HURT_RADIUS_M, 1e-12, "the shipped torso is the measured one")
	rules.combatant(0).fighter.hurt_radius = rules.combatant(0).fighter.push_radius * 1.01
	assert_false(rules.is_valid(), "a torso wider than the footprint is invalid")
	rules.combatant(0).fighter.hurt_radius = 0.0
	assert_false(rules.is_valid(), "and so is no torso at all")


## A fallen body and the clash reference are rules content like any other:
## one bad value refuses the whole duel rather than dividing by zero or
## sliding a body with no friction.
func test_fallen_body_and_clash_reference_fail_closed() -> void:
	var broken := {
		"fallen_settle_ticks_cut": -1,
		"fallen_settle_ticks_point": -1,
		"fallen_ground_friction": 0.0,
		"reference_clash_energy": 0.0,
	}
	for field: String in broken:
		var rules := StandardDuelRules.create()
		assert_true(rules.is_valid() and DuelSimulation.create(rules) != null, "fixture: the shipped rules start a duel (%s)" % field)
		rules.combat.set(field, broken[field])
		assert_eq(rules.combat.get(field), broken[field], "perturbed: %s" % field)
		assert_false(rules.is_valid(), "%s out of range is invalid" % field)
		assert_true(DuelSimulation.create(rules) == null, "and no duel starts on it (%s)" % field)
