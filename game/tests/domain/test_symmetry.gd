extends TestCase

## SYM: the duel has no slot bias. The canonical setup is point-symmetric
## (180° rotation about the arena center), so a mirrored script must produce
## the mirrored outcome.
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "SYM"


func _scenario(attacker: int) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.rules(), 1)
	var pilots: Array[Pilot] = [Pilot.idle(), Pilot.idle()]
	pilots[attacker] = Pilot.approach_and_tap()
	runner.run(pilots[0], pilots[1], 260)
	return runner


func test_mirrored_attacks_produce_mirrored_outcomes() -> void:
	var left := _scenario(0)
	var right := _scenario(1)
	var left_hit := left.first(DuelEventTypes.BODY_HIT)
	var right_hit := right.first(DuelEventTypes.BODY_HIT)
	assert_true(left_hit != null and right_hit != null, "both scripted taps land")
	assert_eq(left_hit.tick, right_hit.tick, "same tick")
	assert_eq(left_hit.actor, 0, "slot 0 struck in its scenario")
	assert_eq(right_hit.actor, 1, "slot 1 struck in its scenario")
	assert_near(left_hit.number(DuelEventKeys.DAMAGE), right_hit.number(DuelEventKeys.DAMAGE), 1e-6, "equal damage")
	assert_near(left.state.fighter(1).health, right.state.fighter(0).health, 1e-6, "equal remaining health")
	assert_near(left.state.fighter(0).x, -right.state.fighter(1).x, 1e-6, "point-reflected attacker position")
	assert_near(left.state.fighter(0).y, -right.state.fighter(1).y, 1e-6, "point-reflected attacker lateral position")
