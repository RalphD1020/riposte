extends TestCase

## GUARD-45: the Ready guard (θ = −45°, mirrored +45°) is the one guarding
## calibration anchor. On the reference duelist its grip, its nearest guarded
## steel and its protection midpoint are pinned; every other angle follows the
## one compiled carriage and the rigid sword, measured, never fitted to its own
## midpoint target. Distances, not block probabilities.
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "GUARD-45"
	_rules = DuelFixture.rules()


## Grip radius, nearest guarded steel surface from the torso centre, and which
## feature it is, at `degrees` (the blade capsule from the guard-root apex to
## the point with its radius, and the guard root's bar).
func _guard(degrees: float) -> Dictionary:
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(degrees), spec, BladePose.new())
	var apex := Vector2(pose.point_x(weapon.guard_root_apex_radius()), pose.point_y(weapon.guard_root_apex_radius()))
	var tip := Vector2(pose.point_x(weapon.tip_radius), pose.point_y(weapon.tip_radius))
	var t := SimMath.closest_param_on_segment(apex.x, apex.y, tip.x, tip.y, 0.0, 0.0)
	var blade := apex.lerp(tip, t).length() - weapon.blade_radius
	var guard := WeaponKinematics.crossguard_gap_at(spec, deg_to_rad(degrees)) + spec.fighter.hurt_radius
	var nearest := minf(blade, guard)
	return {"grip": Vector2(pose.carriage_forward, pose.carriage_left).length(), "nearest": nearest, "feature": "guard_root" if guard <= blade else "blade",
		"midpoint": maxf(0.0, nearest - spec.fighter.hurt_radius) * 0.5}


func test_the_ready_guard_is_the_pinned_guarding_anchor() -> void:
	## ARRANGE: the reference body.
	var hurt := _rules.combatant(0).fighter.hurt_radius
	assert_near(hurt, 0.195, 1e-9, "fixture: the reference torso circle is 0.195 m")
	## ACT
	var right := _guard(-45.0)
	var left := _guard(45.0)
	## ASSERT: Wolf's Ready, right side, and its exact planar mirror.
	assert_near(right["grip"], 0.556, 0.001, "the Ready grip sits 0.556 m from the torso centre")
	assert_near(right["grip"] - hurt, 0.361, 0.001, "0.361 m beyond the torso")
	assert_eq(right["feature"], "guard_root", "the nearest guarded steel is the guard root (the sword's reference feature)")
	assert_near(right["nearest"], 0.524, 0.001, "0.524 m from the centre")
	assert_near(right["midpoint"], 0.1645, 0.001, "so the protection midpoint is (0.524 − 0.195) / 2 ≈ 0.1645 m beyond the torso")
	assert_near(left["grip"], right["grip"], 1e-9, "the left Ready is the mirror: same grip")
	assert_near(left["midpoint"], right["midpoint"], 1e-9, "and the same midpoint")


func test_the_guard_track_is_continuous_mirrored_and_clear_everywhere() -> void:
	## ARRANGE: the one compiled carriage, swept every quarter degree over ±135°.
	var spec := _rules.combatant(0)
	var hurt := spec.fighter.hurt_radius
	var limit := rad_to_deg(spec.weapon.guard_limit)
	assert_near(limit, 135.0, 1e-9, "fixture: the domain is ±135°")
	var least := INF
	var least_at := NAN
	var largest_step := 0.0
	var previous := Vector2.INF
	var step := 0.25
	var samples := 0
	var degrees := -limit
	while degrees <= limit + 1e-9:
		## ACT
		var reading := _guard(degrees)
		var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(degrees), spec, BladePose.new())
		var carriage := Vector2(pose.carriage_forward, pose.carriage_left)
		var clearance: float = reading["nearest"] - hurt
		if clearance < least:
			least = clearance
			least_at = degrees
		if previous != Vector2.INF:
			largest_step = maxf(largest_step, carriage.distance_to(previous))
		previous = carriage
		## ASSERT: the mirror is exact — forward even, lateral odd, slope mirrored.
		var mirrored := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(-degrees), spec, BladePose.new())
		assert_near(mirrored.carriage_forward, pose.carriage_forward, 1e-12, "forward is even at %.2f°" % degrees)
		assert_near(mirrored.carriage_left, -pose.carriage_left, 1e-12, "lateral is odd at %.2f°" % degrees)
		assert_near(mirrored.d_carriage_forward, -pose.d_carriage_forward, 1e-9, "the forward slope mirrors at %.2f°" % degrees)
		assert_near(mirrored.d_carriage_left, pose.d_carriage_left, 1e-9, "the lateral slope mirrors at %.2f°" % degrees)
		samples += 1
		degrees += step
	## The guarded steel never enters the torso anywhere on the swept track, and the
	## tightest place is the full load (the measured 5 mm).
	assert_eq(samples, 1081, "fixture: every quarter degree over ±135° was swept")
	assert_true(least > 0.0, "guarded steel stays outside the torso everywhere (least %.1f mm at %.2f°)" % [least * 1000.0, least_at])
	assert_near(absf(least_at), 135.0, 0.5, "the tightest clearance is at the full wind-back")
	assert_true(largest_step < 0.01, "the carriage has no jump: at most %.2f mm per quarter degree" % (largest_step * 1000.0))
	## PERTURB: the slope is continuous through the centre (no kink at θ = 0).
	var just_right := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(-0.01), spec, BladePose.new())
	var just_left := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(0.01), spec, BladePose.new())
	assert_near(just_right.d_carriage_left, just_left.d_carriage_left, 1e-3, "the lateral slope is continuous through the centre")


func test_away_from_ready_the_midpoint_is_measured_from_the_one_track() -> void:
	## ARRANGE / ACT: the other knots, read from the same compiled carriage.
	var centre := _guard(0.0)
	var gather := _guard(-80.0)
	var loaded := _guard(-135.0)
	## ASSERT: the measured geometry (no per-knot target exists to match): the
	## guard root stays the nearest steel, the wind-back draws it toward the
	## torso, and at the full load it sits just outside it.
	for reading: Dictionary in [centre, gather, loaded]:
		assert_eq(reading["feature"], "guard_root", "the guard root is the nearest steel at every knot")
	assert_near(centre["midpoint"], 0.240, 0.001, "Long Guard: 0.240 m")
	assert_near(gather["midpoint"], 0.079, 0.001, "gathered (80°): 0.079 m")
	assert_near(loaded["midpoint"], 0.002, 0.001, "full load (135°): 0.002 m")
	assert_near(loaded["nearest"] - _rules.combatant(0).fighter.hurt_radius, 0.005, 0.001, "the loaded guard root is 5 mm outside the torso")
	## PERTURB: winding back from Ready shrinks the gap — a geometric trend, not a
	## protection rule (coverage is measured by the planned harness).
	var ready := _guard(-45.0)
	assert_true(ready["midpoint"] > gather["midpoint"] and gather["midpoint"] > loaded["midpoint"], "Ready > gather > load along this wind-back")
