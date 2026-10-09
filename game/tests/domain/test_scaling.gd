extends TestCase

## SCALING: the physical baseline and the scaling laws built on it.
##
## The law under test is that **scale changes physical inputs, and physical
## equations produce gameplay outputs** — never "bigger fighter, +20% damage".
## So these are mostly property tests: perturb one authored physical fact and
## prove the consequence falls out of `a = F/m` and `α = τ/I` rather than out
## of a lookup.
##
## Implements: /spec/invariants.md#content-002
## Implements: /spec/invariants.md#phys-005
## Implements: /spec/invariants.md#phys-006
## See also: /docs/concepts/content.md, /docs/concepts/combat.md


func _init() -> void:
	suite_name = "SCALING"


func _fighter() -> FighterDefinition:
	return FighterCatalog.duelist()


func _weapon() -> WeaponDefinition:
	return WeaponCatalog.bastard_sword()


# ── BASELINE-PHYSICS ────────────────────────────────────────────────────────


func test_shipped_content_sits_exactly_on_the_baseline() -> void:
	## Scale 1.0 has to be a real, specific fighter holding a real, specific
	## sword. If the shipped content drifts off the baseline then every ratio
	## derived from it is measuring the wrong thing.
	var fighter := _fighter()
	var weapon := _weapon()
	assert_near(fighter.height, PhysicalBaseline.FIGHTER_HEIGHT_M, 1e-12, "1.75 m tall")
	assert_near(fighter.mass, PhysicalBaseline.FIGHTER_MASS_KG, 1e-12, "80 kg")
	assert_near(fighter.body_radius, PhysicalBaseline.FIGHTER_RADIUS_M, 1e-12, "0.27 m footprint")
	assert_near(weapon.length(), PhysicalBaseline.SWORD_LENGTH_M, 1e-12, "1.22 m sword")
	assert_near(weapon.blade_length(), PhysicalBaseline.SWORD_BLADE_M, 1e-9, "0.97 m blade")
	assert_near(weapon.mass, PhysicalBaseline.SWORD_MASS_KG, 1e-12, "1.60 kg")


func test_every_baseline_ratio_reads_one() -> void:
	var fighter := _fighter()
	var weapon := _weapon()
	assert_near(fighter.height_ratio(), 1.0, 1e-12, "baseline height ratio")
	assert_near(fighter.mass_ratio(), 1.0, 1e-12, "baseline mass ratio")
	assert_near(fighter.radius_ratio(), 1.0, 1e-12, "baseline radius ratio")
	assert_near(weapon.length_ratio(), 1.0, 1e-12, "baseline weapon length ratio")
	assert_near(weapon.mass_ratio(), 1.0, 1e-12, "baseline weapon mass ratio")
	assert_near(weapon.inertia_ratio(), 1.0, 1e-12, "baseline weapon inertia ratio")


func test_the_baseline_blade_is_near_the_hand_calculation() -> void:
	## A rod of this mass and length pivoting about its end is ~0.794 kg·m².
	## The shipped blade must be recognizably that object, not an order of
	## magnitude away because a coefficient was typed wrong.
	var rod := PhysicalBaseline.SWORD_MASS_KG * PhysicalBaseline.SWORD_LENGTH_M * PhysicalBaseline.SWORD_LENGTH_M / 3.0
	assert_near(rod, 0.794, 1e-3, "precondition: the hand calculation is ~0.794 kg·m²")
	assert_between(_weapon().moment_of_inertia(), rod * 0.8, rod * 1.5, "the shipped blade is that object")


func test_geometry_scales_linearly() -> void:
	## Twice as tall is twice as wide, and twice as long a sword has twice the
	## blade. Nothing here may pick up a square or a cube.
	assert_near(PhysicalBaseline.fighter_height(2.0), PhysicalBaseline.FIGHTER_HEIGHT_M * 2.0, 1e-12, "height is linear")
	assert_near(PhysicalBaseline.fighter_radius(2.0), PhysicalBaseline.FIGHTER_RADIUS_M * 2.0, 1e-12, "radius is linear")
	assert_near(PhysicalBaseline.sword_length(0.5), PhysicalBaseline.SWORD_LENGTH_M * 0.5, 1e-12, "sword length is linear")
	assert_near(PhysicalBaseline.sword_blade(0.5), PhysicalBaseline.SWORD_BLADE_M * 0.5, 1e-12, "blade is linear")


func test_default_mass_is_volumetric_and_strength_is_structural() -> void:
	## The *default* generator for same-density geometry: mass goes as the
	## cube, force and torque as the square. Together they are the whole of
	## "larger is stronger but slower", with no authored speed penalty.
	var doubled := 2.0
	assert_near(PhysicalBaseline.volumetric_mass(80.0, doubled), 640.0, 1e-12, "mass goes as the cube")
	assert_near(PhysicalBaseline.structural_scale(1760.0, doubled), 7040.0, 1e-12, "force goes as the square")
	var small := PhysicalBaseline.structural_scale(1760.0, 1.0) / PhysicalBaseline.volumetric_mass(80.0, 1.0)
	var large := PhysicalBaseline.structural_scale(1760.0, doubled) / PhysicalBaseline.volumetric_mass(80.0, doubled)
	assert_near(large, small / doubled, 1e-9, "so acceleration falls off as 1/s, for free")
	assert_true(large < small, "the larger build accelerates less")


# ── CONTENT-CATALOG ───────────────────────────────────────────────────────


func test_content_is_selected_by_identity_and_fails_closed() -> void:
	## A rule set names what it wants; it never assembles it. An id nobody
	## ships yields nothing rather than a plausible substitute, so a typo
	## cannot silently become a different duel.
	assert_eq(FighterCatalog.of(ContentIds.FIGHTER_DUELIST).id, ContentIds.FIGHTER_DUELIST, "the duelist is in the catalog")
	assert_eq(WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD).id, ContentIds.WEAPON_BASTARD_SWORD, "so is the sword")
	assert_true(FighterCatalog.of(&"fighter.nobody") == null, "an unknown fighter id yields nothing")
	assert_true(WeaponCatalog.of(&"weapon.nothing") == null, "and so does an unknown weapon id")
	var rules := StandardDuelRules.create()
	assert_eq(rules.fighter.id, ContentIds.FIGHTER_DUELIST, "the standard rules select the duelist by id")
	assert_eq(rules.weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "and the bastard sword")


func test_each_catalog_entry_is_a_fresh_object() -> void:
	## Definitions are immutable for the life of a match, but the catalog is a
	## function, not a shared singleton: tuning one match must not reach into
	## another (CONTENT-001).
	var first := FighterCatalog.duelist()
	var second := FighterCatalog.duelist()
	assert_false(first == second, "two requests are two objects")
	first.mass = 999.0
	assert_near(second.mass, PhysicalBaseline.FIGHTER_MASS_KG, 1e-12, "and mutating one leaves the other alone")
	var blade := WeaponCatalog.bastard_sword()
	blade.mass = 99.0
	assert_near(WeaponCatalog.bastard_sword().mass, PhysicalBaseline.SWORD_MASS_KG, 1e-12, "same for weapons")


func test_a_catalog_entry_is_a_size_not_a_column_of_numbers() -> void:
	## The payoff of authoring content as a scale: ask for a bigger duelist
	## and every physical quantity moves by its own law, with nobody writing
	## a second set of magic numbers.
	var base := FighterCatalog.duelist()
	var big := FighterCatalog.duelist_at(1.5)
	assert_near(big.height, base.height * 1.5, 1e-9, "geometry is linear")
	assert_near(big.body_radius, base.body_radius * 1.5, 1e-9, "all of it")
	assert_near(big.mass, base.mass * 1.5 * 1.5 * 1.5, 1e-9, "mass is volumetric by default")
	assert_near(big.locomotion_force, base.locomotion_force * 1.5 * 1.5, 1e-9, "force is structural")
	assert_near(big.turn_torque, base.turn_torque * 1.5 * 1.5 * 1.5, 1e-9, "torque is force times a lever")
	assert_near(big.weapon_torque_scale, base.weapon_torque_scale * 1.5 * 1.5 * 1.5, 1e-9, "including the arm driving the sword")
	assert_near(big.max_health, base.max_health, 1e-12, "and nothing about how they fight moved")
	assert_near(big.max_speed, base.max_speed, 1e-12, "least of all a hand-authored speed penalty")
	assert_true(big.is_valid(), "the scaled build is a legal fighter")
	## Bigger drives the same sword faster, and turns its own body slower.
	var sword := WeaponCatalog.bastard_sword()
	assert_true(
		sword.swing_accel(1.0, big.weapon_torque_scale) > sword.swing_accel(1.0, base.weapon_torque_scale),
		"the same sword accelerates faster in the larger arm"
	)
	assert_true(big.turn_accel() < base.turn_accel(), "while the larger body turns more slowly")


func test_volumetric_mass_is_a_default_that_content_overrides() -> void:
	## Same height, different build. Volumetric mass is a starting guess about
	## uniform density, not a law, so a lean duelist is authored by assigning
	## mass — and the accelerations follow from `a = F/m` on their own.
	var standard := FighterCatalog.duelist_at(1.3)
	var lean := FighterCatalog.duelist_at(1.3)
	lean.mass = standard.mass * 0.8
	assert_near(lean.height, standard.height, 1e-12, "the override did not touch geometry")
	assert_near(lean.locomotion_force, standard.locomotion_force, 1e-12, "or strength")
	assert_true(lean.move_accel() > standard.move_accel(), "the lean build is quicker off the mark")
	assert_true(lean.turn_accel() > standard.turn_accel(), "and quicker to turn")
	assert_true(lean.is_valid(), "and is a perfectly legal fighter")


func test_a_weapon_must_state_its_mass() -> void:
	## Weapons get no volumetric default. Longer blades are made thinner so
	## they stay wieldable, so a cubic rule would invent a crowbar: the
	## catalog requires the mass to be stated alongside the length.
	var long_sword := WeaponCatalog.bastard_sword_at(1.4, PhysicalBaseline.SWORD_MASS_KG * 1.15)
	assert_near(long_sword.blade_length(), PhysicalBaseline.SWORD_BLADE_M * 1.4, 1e-9, "the blade came from the length scale")
	assert_near(long_sword.length(), PhysicalBaseline.GRIP_RADIUS_M + PhysicalBaseline.SWORD_BLADE_M * 1.4, 1e-9, "held at the baseline grip, so reach is grip plus blade")
	assert_near(long_sword.mass, PhysicalBaseline.SWORD_MASS_KG * 1.15, 1e-9, "and mass came from the author, not the length")
	assert_true(long_sword.mass < PhysicalBaseline.volumetric_mass(PhysicalBaseline.SWORD_MASS_KG, 1.4), "a longer blade need not be a cubically heavier one")
	assert_true(long_sword.moment_of_inertia() > WeaponCatalog.bastard_sword().moment_of_inertia() * 1.9, "yet reach is still expensive, because length is squared")
	assert_true(long_sword.is_valid(), "and it is a legal weapon")


func test_reach_is_the_wielders_grip_plus_the_blade() -> void:
	## Grip belongs to the fighter: the same sword in longer arms reaches
	## further, and nothing about the sword itself changed.
	var base := FighterCatalog.duelist()
	var long_arms := FighterCatalog.duelist_at(1.2)
	assert_near(base.grip_radius, PhysicalBaseline.GRIP_RADIUS_M, 1e-12, "precondition: the duelist holds at the baseline grip")
	assert_true(long_arms.grip_radius > base.grip_radius, "precondition: a bigger duelist has a longer grip")
	var held := WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, base.grip_radius)
	var held_long := WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, long_arms.grip_radius)
	assert_eq(held.length(), PhysicalBaseline.SWORD_LENGTH_M, "the baseline duelist's reach is exactly the baseline sword length")
	assert_near(held_long.blade_length(), held.blade_length(), 1e-12, "the blade is the same blade")
	assert_near(held_long.length() - held.length(), long_arms.grip_radius - base.grip_radius, 1e-12, "only the grip added reach")
	var rules := StandardDuelRules.create()
	assert_eq(rules.weapon.hilt_radius, rules.fighter.grip_radius, "standard rules mount the sword at the duelist's grip")
	assert_true(rules.is_valid(), "precondition: and validate")
	rules.weapon = held_long
	assert_false(rules.is_valid(), "a weapon mounted for a different grip is refused")


# ── FIGHTER-SCALING ────────────────────────────────────────────────────────


func test_heavier_fighters_accelerate_less_for_the_same_force() -> void:
	var light := _fighter()
	var heavy := _fighter()
	heavy.mass = light.mass * 1.5
	assert_near(heavy.locomotion_force, light.locomotion_force, 1e-12, "precondition: identical strength")
	assert_true(heavy.move_accel() < light.move_accel(), "mass resists being started")
	assert_true(heavy.brake_accel() < light.brake_accel(), "and resists being stopped")
	assert_true(heavy.burst_accel() < light.burst_accel(), "and resists being burst")
	assert_near(heavy.move_accel(), light.move_accel() / 1.5, 1e-9, "exactly a = F/m")


func test_stronger_fighters_accelerate_more_for_the_same_mass() -> void:
	var weak := _fighter()
	var strong := _fighter()
	strong.locomotion_force = weak.locomotion_force * 2.0
	assert_near(strong.mass, weak.mass, 1e-12, "precondition: identical build")
	assert_near(strong.move_accel(), weak.move_accel() * 2.0, 1e-9, "force and acceleration are proportional")


func test_mass_and_size_are_independent_facts() -> void:
	## A lean duelist and a heavy one of the same height are both legitimate,
	## and neither value may be derived from the other.
	var lean := _fighter()
	var heavy := _fighter()
	heavy.mass = lean.mass * 1.4
	assert_near(heavy.height, lean.height, 1e-12, "mass did not change height")
	assert_near(heavy.body_radius, lean.body_radius, 1e-12, "or footprint")
	var tall := _fighter()
	tall.height = lean.height * 1.2
	assert_near(tall.mass, lean.mass, 1e-12, "and height did not change mass")
	assert_true(lean.is_valid() and heavy.is_valid() and tall.is_valid(), "all three are authorable fighters")


func test_a_wider_body_turns_more_reluctantly() -> void:
	## I_body = k·m·r², so both mass and footprint resist turning, and neither
	## may be ignored.
	var base := _fighter()
	var wide := _fighter()
	wide.body_radius = base.body_radius * 1.3
	var heavy := _fighter()
	heavy.mass = base.mass * 1.3
	assert_true(wide.moment_of_inertia() > base.moment_of_inertia(), "a wider body has more rotational inertia")
	assert_true(heavy.moment_of_inertia() > base.moment_of_inertia(), "so does a heavier one")
	assert_true(wide.turn_accel() < base.turn_accel(), "and turns more slowly under the same torque")
	assert_true(heavy.turn_accel() < base.turn_accel(), "likewise")
	assert_near(
		wide.moment_of_inertia(), base.moment_of_inertia() * 1.3 * 1.3, 1e-9, "radius enters squared, mass linearly"
	)


func test_more_turn_torque_turns_faster() -> void:
	var base := _fighter()
	var torquey := _fighter()
	torquey.turn_torque = base.turn_torque * 2.0
	assert_near(torquey.turn_accel(), base.turn_accel() * 2.0, 1e-9, "α = τ / I_body")


func test_a_fighter_must_be_physically_possible() -> void:
	assert_true(_fighter().is_valid(), "precondition: the baseline duelist is valid")
	for mutation in PackedStringArray(["height", "mass", "body_radius", "locomotion_force", "weapon_torque_scale", "body_inertia_coefficient"]):
		var broken := _fighter()
		broken.set(mutation, 0.0)
		assert_false(broken.is_valid(), "a fighter with no %s is impossible" % mutation)
	var wider_than_tall := _fighter()
	wider_than_tall.body_radius = wider_than_tall.height
	assert_false(wider_than_tall.is_valid(), "a footprint as wide as the body is tall is impossible")
	var unstoppable := _fighter()
	unstoppable.braking_force = unstoppable.locomotion_force * 0.5
	assert_false(unstoppable.is_valid(), "a fighter who cannot stop as hard as they start is impossible")


# ── WEAPON-SCALING / INERTIA-SCALING ──────────────────────────────────────


func test_a_heavier_blade_is_harder_to_swing() -> void:
	var light := _weapon()
	var heavy := _weapon()
	heavy.mass = light.mass * 2.0
	assert_near(heavy.moment_of_inertia(), light.moment_of_inertia() * 2.0, 1e-9, "mass enters inertia linearly")
	assert_true(heavy.swing_accel(1.0, 1.0) < light.swing_accel(1.0, 1.0), "so the same torque drives it less")
	assert_true(heavy.brake_accel(1.0, 1.0) < light.brake_accel(1.0, 1.0), "and arrests it less")
	assert_true(heavy.windup_accel(1.0) < light.windup_accel(1.0), "and winds it back less")


func test_a_longer_blade_is_much_harder_to_swing() -> void:
	## Length enters squared and mass linearly, which is the single most
	## important asymmetry in weapon design: reach is expensive.
	var short_blade := _weapon()
	var long_blade := _weapon()
	long_blade.tip_radius = short_blade.tip_radius * 1.5
	assert_near(long_blade.mass, short_blade.mass, 1e-12, "precondition: identical mass")
	assert_near(
		long_blade.moment_of_inertia(), short_blade.moment_of_inertia() * 2.25, 1e-9, "length enters inertia squared"
	)
	var heavier := _weapon()
	heavier.mass = short_blade.mass * 1.5
	assert_true(
		long_blade.moment_of_inertia() > heavier.moment_of_inertia(),
		"+50% length costs more than +50% mass, because only one of them is squared"
	)


func test_torque_and_inertia_are_the_only_inputs_to_angular_acceleration() -> void:
	## No weapon may author an angular acceleration beside its inertia: the
	## two would drift apart and the blade would stop obeying its own mass.
	var weapon := _weapon()
	var inertia := weapon.moment_of_inertia()
	assert_near(weapon.swing_accel(0.0, 1.0), weapon.swing_torque_tap / inertia, 1e-12, "α = τ / I")
	var torquey := _weapon()
	torquey.swing_torque_tap = weapon.swing_torque_tap * 3.0
	assert_near(torquey.swing_accel(0.0, 1.0), weapon.swing_accel(0.0, 1.0) * 3.0, 1e-9, "torque and α are proportional")


func test_the_same_sword_behaves_differently_in_different_hands() -> void:
	## A stronger arm drives the same object harder. Crucially it is the
	## *effort* that scales, never the weapon: a sword does not become lighter
	## because a strong fighter picked it up.
	var weapon := _weapon()
	var baseline_arm := _fighter().weapon_torque_scale
	var strong := baseline_arm * 1.4
	assert_near(weapon.swing_accel(0.5, strong), weapon.swing_accel(0.5, baseline_arm) * 1.4, 1e-9, "a stronger arm drives it harder")
	assert_near(weapon.brake_accel(0.5, strong), weapon.brake_accel(0.5, baseline_arm) * 1.4, 1e-9, "and arrests it harder")
	assert_near(weapon.windup_accel(strong), weapon.windup_accel(baseline_arm) * 1.4, 1e-9, "and winds it back harder")
	assert_near(weapon.hold_accel(strong), weapon.hold_accel(baseline_arm) * 1.4, 1e-9, "and settles it harder")
	assert_near(weapon.moment_of_inertia(), _weapon().moment_of_inertia(), 1e-12, "the weapon itself is unchanged")
	assert_near(weapon.mass, PhysicalBaseline.SWORD_MASS_KG, 1e-12, "its mass especially")


func test_a_weapon_must_be_physically_possible() -> void:
	assert_true(_weapon().is_valid(), "precondition: the baseline sword is valid")
	var massless := _weapon()
	massless.mass = 0.0
	assert_false(massless.is_valid(), "a weightless sword is impossible")
	var no_inertia := _weapon()
	no_inertia.inertia_coefficient = 0.0
	assert_false(no_inertia.is_valid(), "a sword with no resistance to turning is impossible")
	var overlong_blade := _weapon()
	overlong_blade.hilt_radius = -0.1
	assert_false(overlong_blade.is_valid(), "a blade longer than the weapon is impossible")
	var no_coverage := _weapon()
	no_coverage.guard_limit = no_coverage.guard_angle
	assert_false(no_coverage.is_valid(), "a blade that cannot leave its guard is impossible")


# ── MASS-ASYMMETRY ────────────────────────────────────────────────────────


func test_an_asymmetric_pairing_differs_only_through_physics() -> void:
	## The acid test for the whole scheme. Give one side a heavier build and a
	## lighter sword, and every difference that appears must be traceable to
	## `a = F/m` or `α = τ/I` — never to which slot they occupy.
	## Built through the shipping catalog, not by hand, so this proves the
	## path real content would take rather than a fixture that agrees with it.
	var small := _fighter()
	var large := FighterCatalog.duelist_at(1.2)
	assert_true(large.is_valid(), "precondition: the large build is a legal fighter")
	assert_true(large.mass > small.mass, "precondition: the large build is heavier")
	assert_true(large.locomotion_force > small.locomotion_force, "precondition: and stronger")
	## Stronger *and* slower, which is the whole point: the strength is real
	## and visible in the force, and the sluggishness is not a penalty anyone
	## authored — it is the quotient.
	assert_true(large.move_accel() < small.move_accel(), "larger is stronger but slower to accelerate")
	assert_near(large.move_accel(), small.move_accel() / 1.2, 1e-9, "by exactly 1/s")
	assert_true(large.moment_of_inertia() > small.moment_of_inertia(), "and far more reluctant to turn")

	var heavy_sword := _weapon()
	var light_sword := _weapon()
	light_sword.mass = heavy_sword.mass * 0.7
	assert_true(light_sword.moment_of_inertia() < heavy_sword.moment_of_inertia(), "precondition: the light sword turns easier")
	assert_true(light_sword.swing_accel(1.0, 1.0) > heavy_sword.swing_accel(1.0, 1.0), "so it reaches speed sooner")
	## And the trade is honest in both directions: the light sword is quicker
	## to start *and* quicker to be knocked aside, since blade contact divides
	## impulse by the same inertia.
	assert_true(light_sword.brake_accel(1.0, 1.0) > heavy_sword.brake_accel(1.0, 1.0), "and is displaced more easily")


func test_scale_never_touches_reaction_or_timing() -> void:
	## Size and mass are physical. They must not reach into the input or
	## decision layers: a big fighter is not a laggy one, and a small fighter
	## does not get a wider tap window.
	var small := _fighter()
	var large := _fighter()
	large.height = small.height * 1.5
	large.mass = small.mass * 2.0
	large.body_radius = small.body_radius * 1.5
	assert_eq(large.tap_window_ticks, small.tap_window_ticks, "tap window is unchanged by size")
	assert_eq(large.double_tap_window_ticks, small.double_tap_window_ticks, "so is the double-tap window")
	assert_eq(large.burst_ticks, small.burst_ticks, "and the burst duration")
	assert_near(large.burst_enter_deflection, small.burst_enter_deflection, 1e-12, "and the input thresholds")
	var heavy_sword := _weapon()
	heavy_sword.mass = _weapon().mass * 2.0
	assert_eq(heavy_sword.tap_threshold_ticks, _weapon().tap_threshold_ticks, "a heavy sword does not change what a tap is")
	assert_eq(heavy_sword.buffer_ticks, _weapon().buffer_ticks, "or the input buffer")
