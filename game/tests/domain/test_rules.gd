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
	assert_eq(rules.weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "weapon id")
	assert_eq(rules.fighter.id, ContentIds.FIGHTER_DUELIST, "fighter id")
	assert_eq(rules.rounds_to_win, 3, "best of five is first to three")


func test_bastard_sword_geometry_matches_spec() -> void:
	var weapon := StandardDuelRules.bastard_sword()
	assert_near(weapon.tip_radius, 1.22, 1e-12, "1.22 m overall")
	assert_near(weapon.blade_length(), 0.97, 1e-9, "~0.97 m effective blade")
	assert_near(rad_to_deg(weapon.guard_limit) * 2.0, 270.0, 1e-9, "270° coverage")


func test_arc_grows_ninety_degrees_with_charge() -> void:
	var weapon := StandardDuelRules.bastard_sword()
	assert_near(rad_to_deg(weapon.arc(0.0)), 90.0, 1e-9, "tap arc 90°")
	assert_near(rad_to_deg(weapon.arc(0.5)), 135.0, 1e-9, "half charge 135°")
	assert_near(rad_to_deg(weapon.arc(1.0)), 180.0, 1e-9, "full charge 180°")
	assert_near(rad_to_deg(weapon.windup_angle(1.0)), 90.0, 1e-9, "full windup retracts 90°")


func test_tap_threshold_is_in_the_specified_window() -> void:
	var ms := float(StandardDuelRules.bastard_sword().tap_threshold_ticks) * 1000.0 / float(SimulationTimebase.TICK_RATE)
	assert_between(ms, 100.0, 130.0, "tap threshold 100–130 ms")


func test_sweet_spot_is_outer_middle() -> void:
	var weapon := StandardDuelRules.bastard_sword()
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(1.0), "outer-middle beats the tip")
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(0.2), "outer-middle beats near the hilt")


func test_broken_rules_fail_validation() -> void:
	var rules := StandardDuelRules.create()
	rules.weapon.tip_radius = rules.weapon.hilt_radius
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
