extends TestCase

## PRES-SNAPSHOT: one read boundary from simulation to presentation, and one
## plane→world mapping.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-SNAPSHOT"


func test_projector_copies_authoritative_facts() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(1)
	fighter.x = 1.5
	fighter.y = -0.5
	fighter.health = 42.0
	fighter.weapon.angle = 0.3
	fighter.weapon.phase = CombatPhase.Id.CHARGING
	fighter.weapon.charge = 0.6
	state.scores[0] = 2
	var snapshot := SnapshotProjector.project(state, rules)
	var row := snapshot.fighter(1)
	assert_eq(row.x, 1.5, "x")
	assert_eq(row.y, -0.5, "y")
	assert_eq(row.health, 42.0, "health")
	assert_eq(row.max_health, rules.fighter.max_health, "health scale")
	assert_eq(row.phase, CombatPhase.Id.CHARGING, "phase")
	assert_eq(row.charge, 0.6, "charge")
	assert_near(row.blade_angle, SimMath.wrap_angle(PI + 0.3), 1e-12, "absolute blade angle")
	assert_eq(snapshot.scores[0], 2, "score")
	assert_eq(row.tip_radius, rules.weapon.tip_radius, "blade geometry")
	state.scores[0] = 3
	assert_eq(snapshot.scores[0], 2, "the snapshot does not alias live state")


func test_time_left_counts_down_from_the_limit() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	state.round_ticks = 600
	assert_eq(SnapshotProjector.project(state, rules).time_left_ticks, rules.round_time_limit_ticks - 600, "remaining ticks")


func test_plane_maps_to_world_with_up_away_from_camera() -> void:
	assert_eq(ArenaTransform.to_world(1.0, 2.0), Vector3(1.0, 0.0, -2.0), "+Y is world -Z")
	assert_eq(ArenaTransform.to_plane(Vector3(3.0, 1.0, -4.0)), Vector2(3.0, 4.0), "round trip")
	for degrees: float in [0.0, 90.0, 180.0, -45.0]:
		var heading := deg_to_rad(degrees)
		var probe := Node3D.new()
		probe.rotation.y = ArenaTransform.yaw(heading)
		var front := probe.basis.z
		probe.free()
		assert_true(front.is_equal_approx(ArenaTransform.direction(heading)), "model front follows heading %s°" % str(degrees))
