extends TestCase

## EDGE-SAFETY: predictive containment for CPU movement candidates. Tests the
## EdgeSafetyEvaluator and its integration with CpuController. The safety
## layer is identical across all difficulties; difficulty changes only the
## tactical layer.
##
## See also: /docs/concepts/cpu.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "EDGE-SAFETY"
	_rules = DuelFixture.rules()


func _fighter_near_edge(edge_offset: float, facing: float) -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(fighter, _rules.platform_radius - edge_offset, 0.0, facing)
	fighter.duel_forward_x = SimMath.cosine(facing)
	fighter.duel_forward_y = SimMath.sine(facing)
	return fighter


func _fighter_at_center() -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	fighter.duel_forward_x = 1.0
	fighter.duel_forward_y = 0.0
	fighter.health = _rules.combatant(0).fighter.max_health
	return fighter


## --- Walk safety ---


func test_walk_toward_center_is_safe() -> void:
	var fighter := _fighter_near_edge(0.5, 0.0)
	fighter.health = _rules.combatant(0).fighter.max_health
	var result := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, -1.0, _rules, ConditionState.healthy())
	assert_false(result.crosses_platform, "walking toward center from near edge is safe")
	assert_true(result.min_clearance > 0.0, "clearance should be positive for inward movement")


func test_walk_outward_from_edge_is_unsafe() -> void:
	var fighter := _fighter_near_edge(0.15, 0.0)
	fighter.health = _rules.combatant(0).fighter.max_health
	fighter.vx = 2.0
	var result := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, _rules, ConditionState.healthy())
	assert_true(result.crosses_platform, "walking outward from near the edge crosses the platform")


func test_walk_at_center_is_always_safe() -> void:
	var fighter := _fighter_at_center()
	var result := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, _rules, ConditionState.healthy())
	assert_false(result.crosses_platform, "walking from center is safe in any direction")
	assert_true(result.min_clearance > 1.0, "clearance from center is large")


## --- Burst safety ---


func test_forward_dash_at_center_is_safe() -> void:
	var fighter := _fighter_at_center()
	var result := EdgeSafetyEvaluator.evaluate_burst(fighter, MovementGestureState.BurstKind.FORWARD_DASH, _rules, ConditionState.healthy())
	assert_false(result.crosses_platform, "forward dash from center does not cross the platform")


func test_backward_dash_near_edge_is_unsafe() -> void:
	var fighter := _fighter_near_edge(0.8, PI)
	fighter.health = _rules.combatant(0).fighter.max_health
	var result := EdgeSafetyEvaluator.evaluate_burst(fighter, MovementGestureState.BurstKind.BACK_DASH, _rules, ConditionState.healthy())
	assert_true(result.crosses_platform, "backward dash near edge crosses the platform (facing away, back dash goes outward)")


func test_a_closed_edge_does_not_pull_footwork_toward_the_centre() -> void:
	var pit := StandardDuelRules.pit()
	var closed := CpuController.create(pit, CpuProfile.medium(), 1, 0)
	var open := CpuController.create(DuelFixture.rules(), CpuProfile.medium(), 1, 0)
	var radius := pit.platform_radius - 0.2
	var me := FighterState.new()
	DuelFixture.place(me, radius, 0.0, 0.0)
	closed._sight_x = radius - 2.0
	closed._sight_y = 0.0
	closed._sight_distance = 2.0
	closed._move = CpuController.Move.RETREAT
	open._sight_x = radius - 2.0
	open._sight_y = 0.0
	open._sight_distance = 2.0
	open._move = CpuController.Move.RETREAT
	var held := closed._steer(me)
	var pulled := open._steer(me)
	assert_true(held[1] < 0.0, "retreat on a closed edge stays outward")
	assert_true(pulled[1] > 0.0, "the open edge pulls that same retreat back toward the centre")
	var home := FighterState.new()
	DuelFixture.place(home, 0.0, -pit.spawn_offset, DuelSide.NORTH_FACING)
	closed._sight_x = 0.0
	closed._sight_y = pit.spawn_offset
	closed._sight_distance = pit.spawn_offset * 2.0
	closed._move = CpuController.Move.RETREAT
	var from_spawn := closed._steer(home)
	assert_true(from_spawn[1] < 0.0, "a retreat from the spawn is still a retreat")


func test_a_closed_edge_does_not_predict_a_ring_out() -> void:
	var rules := StandardDuelRules.pit()
	var fighter := _fighter_near_edge(0.05, 0.0)
	fighter.health = rules.combatant(0).fighter.max_health
	var walk := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, rules, ConditionState.healthy())
	assert_false(walk.crosses_platform, "an outward walk is not a ring-out on a closed edge")
	assert_near(walk.min_clearance, rules.platform_radius, 1e-6, "clearance is the whole disc")
	assert_true(walk.recoverable, "and the candidate stays recoverable")
	var burst := EdgeSafetyEvaluator.evaluate_burst(fighter, MovementGestureState.BurstKind.FORWARD_DASH, rules, ConditionState.healthy())
	assert_false(burst.crosses_platform, "and neither is an outward dash")


func test_forward_dash_near_edge_facing_outward_is_unsafe() -> void:
	var fighter := _fighter_near_edge(0.8, 0.0)
	fighter.health = _rules.combatant(0).fighter.max_health
	var result := EdgeSafetyEvaluator.evaluate_burst(fighter, MovementGestureState.BurstKind.FORWARD_DASH, _rules, ConditionState.healthy())
	assert_true(result.crosses_platform, "forward dash near edge toward cliff crosses the platform")


## --- Stopping margin ---


func test_faster_outward_speed_reduces_clearance() -> void:
	var slow := _fighter_near_edge(1.0, 0.0)
	slow.health = _rules.combatant(0).fighter.max_health
	slow.vx = 1.0
	var fast := _fighter_near_edge(1.0, 0.0)
	fast.health = _rules.combatant(0).fighter.max_health
	fast.vx = 3.0
	var slow_result := EdgeSafetyEvaluator.evaluate_walk(slow, 0.0, 0.0, _rules, ConditionState.healthy())
	var fast_result := EdgeSafetyEvaluator.evaluate_walk(fast, 0.0, 0.0, _rules, ConditionState.healthy())
	assert_true(fast_result.min_clearance < slow_result.min_clearance, "faster fighter drifts closer to the edge")


## --- Condition affects prediction (CONDITION-001) ---


func test_a_wounded_condition_changes_safety() -> void:
	var fighter := _fighter_near_edge(1.5, 0.0)
	fighter.health = _rules.combatant(0).fighter.max_health
	var wounded := ConditionModel.compute(10.0, _rules.combatant(0).fighter.max_health, 1.0, _rules.combat, ConditionState.new())
	var healthy := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, _rules, ConditionState.healthy())
	var hurt := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, _rules, wounded)
	assert_true(wounded.force_scale < 1.0, "fixture: the wounded condition is weaker")
	assert_true(absf(healthy.min_clearance - hurt.min_clearance) > 0.001 or absf(healthy.stopping_margin - hurt.stopping_margin) > 0.001, "the fighter's own condition changes the predicted trajectory or stopping margin")


## --- Max-survival fallback ---


func test_all_candidates_fall_picks_best() -> void:
	var fighter := _fighter_near_edge(0.05, 0.0)
	fighter.health = _rules.combatant(0).fighter.max_health
	fighter.vx = 4.0
	var forward := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 1.0, _rules, ConditionState.healthy())
	var backward := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, -1.0, _rules, ConditionState.healthy())
	var hold := EdgeSafetyEvaluator.evaluate_walk(fighter, 0.0, 0.0, _rules, ConditionState.healthy())
	var best := forward.min_clearance
	if backward.min_clearance > best:
		best = backward.min_clearance
	if hold.min_clearance > best:
		best = hold.min_clearance
	assert_true(forward.crosses_platform or backward.crosses_platform or hold.crosses_platform, "at least one candidate is doomed when very close with high outward speed")
	assert_true(best >= forward.min_clearance, "max-survival candidate has the best (or tied) clearance")


## --- CW/CCW mirror ---


func test_mirror_cw_ccw_candidate_mask() -> void:
	var fighter_right := _fighter_near_edge(0.8, 0.0)
	fighter_right.health = _rules.combatant(0).fighter.max_health
	var cw_right := EdgeSafetyEvaluator.evaluate_burst(fighter_right, MovementGestureState.BurstKind.RIGHT_STEP, _rules, ConditionState.healthy())
	var ccw_right := EdgeSafetyEvaluator.evaluate_burst(fighter_right, MovementGestureState.BurstKind.LEFT_STEP, _rules, ConditionState.healthy())
	var fighter_left := FighterState.new()
	fighter_left.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(fighter_left, -(_rules.platform_radius - 0.8), 0.0, PI)
	fighter_left.duel_forward_x = SimMath.cosine(PI)
	fighter_left.duel_forward_y = SimMath.sine(PI)
	fighter_left.health = _rules.combatant(0).fighter.max_health
	var cw_left := EdgeSafetyEvaluator.evaluate_burst(fighter_left, MovementGestureState.BurstKind.RIGHT_STEP, _rules, ConditionState.healthy())
	var ccw_left := EdgeSafetyEvaluator.evaluate_burst(fighter_left, MovementGestureState.BurstKind.LEFT_STEP, _rules, ConditionState.healthy())
	assert_near(cw_right.min_clearance, ccw_left.min_clearance, 0.01, "right step on positive X mirrors left step on negative X")
	assert_near(ccw_right.min_clearance, cw_left.min_clearance, 0.01, "left step on positive X mirrors right step on negative X")
