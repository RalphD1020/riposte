extends TestCase

## FACE: facing has angular inertia and must be earned (COMBAT §9–§10, §26, §62).
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "FACE"
	_rules = DuelFixture.rules()


func _pair() -> MatchState:
	var state := DuelFixture.state(_rules)
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0)
	DuelFixture.place(state.fighter(1), 0.0, 2.0, 0.0)
	return state


func test_turns_toward_target_without_snapping() -> void:
	var fighter := _pair().fighter(0)
	FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.fighter)
	assert_true(fighter.facing > 0.0, "turned toward the target")
	assert_true(fighter.facing <= 9.0 / 60.0 + 1e-12, "first tick bounded by turn speed")
	for _i in 60:
		FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.fighter)
	assert_near(fighter.facing, PI / 2.0, deg_to_rad(1.0), "settles on the target within 1°")


func test_angular_inertia_resists_reversal() -> void:
	var fighter := _pair().fighter(0)
	fighter.turn_rate = -9.0
	FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.fighter)
	assert_true(fighter.turn_rate < 0.0, "still rotating clockwise one tick after the target flips")


func test_commitment_degrades_tracking() -> void:
	var state := _pair()
	var neutral := state.fighter(0)
	var committed := FighterState.new()
	committed.weapon.reset(-_rules.weapon.guard_angle)
	DuelFixture.place(committed, 0.0, 0.0, 0.0)
	DuelFixture.commit(committed, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	var tracking := CommitmentModel.tracking_multiplier(committed, state.fighter(1), _rules.fighter)
	for _i in 12:
		FacingSystem.step(neutral, 0.0, 2.0, 1.0, _rules.fighter)
		FacingSystem.step(committed, 0.0, 2.0, tracking, _rules.fighter)
	assert_true(committed.facing < neutral.facing * 0.5, "heavy commitment turns less than half as far")


func test_tracking_matches_commitment_table() -> void:
	var opponent := FighterState.new()
	DuelFixture.place(opponent, 2.0, 0.0, PI)
	var fighter := FighterState.new()
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	assert_eq(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 1.0, "neutral tracks fully")
	DuelFixture.commit(fighter, CombatPhase.Id.CHARGING, 1.0, _rules.weapon)
	assert_between(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 0.8, 0.95, "charging 80–95%")
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 0.0, _rules.weapon)
	assert_between(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 0.6, 0.8, "tap attack 60–80%")
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.weapon)
	assert_between(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 0.45, 0.65, "medium attack 45–65%")
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	assert_between(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 0.2, 0.4, "heavy attack 20–40%")
	DuelFixture.commit(fighter, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	assert_between(CommitmentModel.tracking_multiplier(fighter, opponent, _rules.fighter), 0.15, 0.35, "overswing 15–35%")


func test_counter_rotation_is_harder_to_track() -> void:
	var fighter := FighterState.new()
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	fighter.weapon.swing_dir = 1.0
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.weapon)
	var with_swing := FighterState.new()
	DuelFixture.place(with_swing, 1.0, 0.0, PI)
	with_swing.vy = 3.0
	var against_swing := FighterState.new()
	DuelFixture.place(against_swing, 1.0, 0.0, PI)
	against_swing.vy = -3.0
	assert_true(DuelGeometry.orbit_rate(fighter, with_swing) > 0.0, "precondition: orbiting with the counter-clockwise swing")
	var easy := CommitmentModel.tracking_multiplier(fighter, with_swing, _rules.fighter)
	var hard := CommitmentModel.tracking_multiplier(fighter, against_swing, _rules.fighter)
	assert_true(hard < easy, "stepping against committed rotation defeats tracking (%s < %s)" % [str(hard), str(easy)])
	assert_eq(CommitmentModel.counter_rotation_pressure(fighter, with_swing, _rules.fighter), 0.0, "same direction adds no pressure")


func test_geometry_helpers_describe_the_relationship() -> void:
	var a := FighterState.new()
	var b := FighterState.new()
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.0, 3.0, 0.0)
	assert_near(DuelGeometry.distance(a, b), 3.0, 1e-12, "distance")
	assert_near(DuelGeometry.facing_error(a, b), PI / 2.0, 1e-9, "opponent is 90° to the left")
	b.vy = -2.0
	assert_near(DuelGeometry.closing_speed(a, b), 2.0, 1e-9, "closing at 2 m/s")
	assert_eq(DuelGeometry.orbit_rate(a, a), 0.0, "no orbit around oneself")
