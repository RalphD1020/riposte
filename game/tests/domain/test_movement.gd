extends TestCase

## MOVE: footwork accelerates, brakes, respects direction and commitment,
## stays inside the arena, and never overlaps bodies (COMBAT §23–§25, §61).
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "MOVE"
	_rules = DuelFixture.rules()


func _fighter() -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	return fighter


func test_velocity_ramps_instead_of_teleporting() -> void:
	var fighter := _fighter()
	assert_eq(fighter.speed(), 0.0, "starts at rest")
	MovementSystem.step(fighter, 1.0, 0.0, _rules.fighter)
	assert_near(fighter.speed(), 22.0 / 60.0, 1e-9, "one tick adds accel × dt")
	var reached := DuelFixture.steady_speed(fighter, 1.0, 0.0, _rules.fighter, 40)
	assert_near(reached, 4.2, 1e-9, "settles at forward max speed")


func test_backward_and_lateral_are_slower_than_forward() -> void:
	var forward := DuelFixture.steady_speed(_fighter(), 1.0, 0.0, _rules.fighter, 60)
	var lateral := DuelFixture.steady_speed(_fighter(), 0.0, 1.0, _rules.fighter, 60)
	var backward := DuelFixture.steady_speed(_fighter(), -1.0, 0.0, _rules.fighter, 60)
	assert_near(forward, 4.2, 1e-9, "forward 4.2 m/s")
	assert_near(lateral, 4.2 * 0.92, 1e-9, "lateral 92%")
	assert_near(backward, 4.2 * 0.78, 1e-9, "backward 78%")


func test_reversal_is_not_instant() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 1.0, 0.0, _rules.fighter, 60)
	assert_near(fighter.vx, 4.2, 1e-9, "precondition: full forward speed")
	MovementSystem.step(fighter, -1.0, 0.0, _rules.fighter)
	assert_true(fighter.vx > 0.0, "still moving forward one tick after reversing input")


func test_braking_beats_accelerating() -> void:
	var fighter := _fighter()
	var accelerate_ticks := 0
	while fighter.speed() < 4.2 - 1e-9 and accelerate_ticks < 120:
		MovementSystem.step(fighter, 1.0, 0.0, _rules.fighter)
		accelerate_ticks += 1
	var brake_ticks := 0
	while fighter.speed() > 0.0 and brake_ticks < 120:
		MovementSystem.step(fighter, 0.0, 0.0, _rules.fighter)
		brake_ticks += 1
	assert_true(brake_ticks < accelerate_ticks, "stopping (%d) is quicker than reaching speed (%d)" % [brake_ticks, accelerate_ticks])


func test_commitment_cuts_top_speed() -> void:
	var fighter := _fighter()
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	assert_near(fighter.weapon.commitment, 1.0, 1e-9, "precondition: heavy swing is fully committed")
	var committed := DuelFixture.steady_speed(fighter, 1.0, 0.0, _rules.fighter, 120)
	assert_between(committed / 4.2, 0.6, 0.8, "heavy attack translation within 60–80%")


func test_staggered_and_dead_fighters_move_poorly() -> void:
	var staggered := _fighter()
	staggered.weapon.phase = CombatPhase.Id.STAGGER
	assert_near(DuelFixture.steady_speed(staggered, 1.0, 0.0, _rules.fighter, 120), 4.2 * 0.55, 1e-9, "stagger slows footwork")
	var dead := _fighter()
	dead.weapon.phase = CombatPhase.Id.DEAD
	assert_eq(DuelFixture.steady_speed(dead, 1.0, 0.0, _rules.fighter, 10), 0.0, "the dead do not walk")


func test_arena_boundary_is_hard() -> void:
	var fighter := _fighter()
	var limit := _rules.arena_radius - _rules.fighter.body_radius
	DuelFixture.place(fighter, limit + 0.5, 0.0, 0.0)
	fighter.vx = 3.0
	fighter.vy = 1.0
	ArenaConstraints.confine(fighter, limit)
	assert_near(SimMath.length(fighter.x, fighter.y), limit, 1e-9, "pulled back onto the boundary")
	assert_eq(fighter.vx, 0.0, "outward velocity removed")
	assert_eq(fighter.vy, 1.0, "tangential velocity kept")


func test_bodies_never_overlap() -> void:
	var a := _fighter()
	var b := _fighter()
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.3, 0.0, PI)
	a.vx = 2.0
	b.vx = -2.0
	ArenaConstraints.separate(a, b, _rules.fighter.body_radius)
	assert_near(DuelGeometry.distance(a, b), 0.54, 1e-9, "pushed apart to two radii")
	assert_near(a.vx - b.vx, 0.0, 1e-9, "approach velocity removed")


func test_coincident_bodies_separate_deterministically() -> void:
	var a := _fighter()
	var b := _fighter()
	DuelFixture.place(a, 1.0, 1.0, 0.0)
	DuelFixture.place(b, 1.0, 1.0, 0.0)
	ArenaConstraints.separate(a, b, _rules.fighter.body_radius)
	assert_near(a.x, 0.73, 1e-9, "slot 0 resolved toward -x")
	assert_near(b.x, 1.27, 1e-9, "slot 1 resolved toward +x")
	assert_eq(a.y, 1.0, "no vertical drift")


func test_violent_reversal_costs_stability() -> void:
	var calm := _fighter()
	DuelFixture.steady_speed(calm, 0.0, 0.0, _rules.fighter, 30)
	assert_eq(calm.stability, 1.0, "standing still is planted")
	var lunging := _fighter()
	DuelFixture.steady_speed(lunging, 1.0, 0.0, _rules.fighter, 60)
	DuelFixture.steady_speed(lunging, -1.0, 0.0, _rules.fighter, 8)
	assert_true(lunging.stability < 0.95, "reversing at speed unsettles the body (%s)" % str(lunging.stability))
	assert_true(lunging.stability >= _rules.fighter.stability_floor, "never below the floor")


func test_coast_brakes_to_rest() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 1.0, 0.0, _rules.fighter, 60)
	for _i in 30:
		MovementSystem.coast(fighter, _rules.fighter)
	assert_eq(fighter.speed(), 0.0, "coasting body comes to rest")
