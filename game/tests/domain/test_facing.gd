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
	FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.combatant(0).fighter)
	assert_true(fighter.facing > 0.0, "turned toward the target")
	assert_true(fighter.facing <= 9.0 / 60.0 + 1e-12, "first tick bounded by turn speed")
	for _i in 60:
		FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.combatant(0).fighter)
	assert_near(fighter.facing, PI / 2.0, deg_to_rad(1.0), "settles on the target within 1°")


func test_angular_inertia_resists_reversal() -> void:
	var fighter := _pair().fighter(0)
	fighter.turn_rate = -9.0
	FacingSystem.step(fighter, 0.0, 2.0, 1.0, _rules.combatant(0).fighter)
	assert_true(fighter.turn_rate < 0.0, "still rotating clockwise one tick after the target flips")


## A full-charge cut at speed costs the heading authority
## (DIRECTIONAL-COMMIT-001): over the same twelve ticks it turns less far
## than a neutral fighter.
func test_commitment_degrades_tracking() -> void:
	var state := _pair()
	var neutral := state.fighter(0)
	var committed := FighterState.new()
	committed.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(committed, 0.0, 0.0, 0.0)
	DuelFixture.commit(committed, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	committed.weapon.launch_preparation = 1.0
	committed.weapon.speed = _rules.combatant(0).weapon.achievable_swing_speed(1.0, 1.0)
	var tracking := CommitmentModel.turn_torque_share(committed, _rules.combatant(0), ConditionState.new(), _rules.combat)
	for _i in 12:
		FacingSystem.step(neutral, 0.0, 2.0, 1.0, _rules.combatant(0).fighter)
		FacingSystem.step(committed, 0.0, 2.0, tracking, _rules.combatant(0).fighter)
	assert_true(tracking < 1.0, "precondition: the cut costs authority (%.3f)" % tracking)
	assert_true(committed.facing < neutral.facing, "heavy commitment turns less far (%.3f < %.3f rad)" % [committed.facing, neutral.facing])

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
