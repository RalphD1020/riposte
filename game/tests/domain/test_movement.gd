extends TestCase

## MOVE: footwork accelerates, brakes, respects direction and commitment,
## stays inside the arena, and never overlaps bodies (COMBAT §23–§25, §61).
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "MOVE"
	_rules = DuelFixture.rules()


## Furthest a body centre may sit from the arena centre.
func _limit() -> float:
	return _rules.arena_radius - _rules.fighter.body_radius


func _fighter() -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	return fighter


func test_velocity_ramps_instead_of_teleporting() -> void:
	var fighter := _fighter()
	assert_eq(fighter.speed(), 0.0, "starts at rest")
	DuelFixture.spar(fighter, 0.0, 1.0, _rules.fighter)
	assert_near(fighter.speed(), 22.0 / 60.0, 1e-9, "one tick adds accel × dt")
	var reached := DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.fighter, 40)
	assert_near(reached, 4.2, 1e-9, "settles at forward max speed")


## Duel axes: `(0, 1)` closes, `(0, -1)` retreats, `(±1, 0)` orbits.
func test_backward_and_lateral_are_slower_than_forward() -> void:
	var forward := DuelFixture.steady_speed(_fighter(), 0.0, 1.0, _rules.fighter, 60)
	var lateral := DuelFixture.steady_speed(_fighter(), 1.0, 0.0, _rules.fighter, 60)
	var backward := DuelFixture.steady_speed(_fighter(), 0.0, -1.0, _rules.fighter, 60)
	assert_near(forward, 4.2, 1e-9, "forward 4.2 m/s")
	assert_near(lateral, 4.2 * 0.92, 1e-9, "lateral 92%")
	assert_near(backward, 4.2 * 0.78, 1e-9, "backward 78%")


func test_reversal_is_not_instant() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.fighter, 60)
	assert_near(fighter.vx, 4.2, 1e-9, "precondition: full forward speed")
	DuelFixture.spar(fighter, 0.0, -1.0, _rules.fighter)
	assert_true(fighter.vx > 0.0, "still moving forward one tick after reversing input")


func test_braking_beats_accelerating() -> void:
	var fighter := _fighter()
	var accelerate_ticks := 0
	while fighter.speed() < 4.2 - 1e-9 and accelerate_ticks < 120:
		DuelFixture.spar(fighter, 0.0, 1.0, _rules.fighter)
		accelerate_ticks += 1
	var brake_ticks := 0
	while fighter.speed() > 0.0 and brake_ticks < 120:
		DuelFixture.spar(fighter, 0.0, 0.0, _rules.fighter)
		brake_ticks += 1
	assert_true(brake_ticks < accelerate_ticks, "stopping (%d) is quicker than reaching speed (%d)" % [brake_ticks, accelerate_ticks])


func test_commitment_costs_acceleration_not_top_speed() -> void:
	## PHYS-003: a committed fighter is not slowed, only made sluggish. Given
	## enough runway they reach the same top speed; what they lose is the
	## ability to get there — or away — quickly.
	var fighter := _fighter()
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	assert_near(fighter.weapon.commitment, 1.0, 1e-9, "precondition: heavy swing is fully committed")
	var free := _fighter()
	var free_speed := DuelFixture.steady_speed(free, 0.0, 1.0, _rules.fighter, 120)
	var committed := DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.fighter, 120)
	assert_near(committed, free_speed, 1e-9, "the same top speed is reachable while committed")
	var sluggish := _fighter()
	DuelFixture.commit(sluggish, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	var quick := _fighter()
	for _i in 6:
		DuelFixture.spar(sluggish, 0.0, 1.0, _rules.fighter)
		DuelFixture.spar(quick, 0.0, 1.0, _rules.fighter)
	assert_true(sluggish.speed() < quick.speed() * 0.6, "but reaching it takes far longer (%.2f vs %.2f after 6 ticks)" % [sluggish.speed(), quick.speed()])


func test_staggered_and_dead_fighters_move_poorly() -> void:
	var staggered := _fighter()
	staggered.weapon.phase = CombatPhase.Id.STAGGER
	assert_near(DuelFixture.steady_speed(staggered, 0.0, 1.0, _rules.fighter, 120), 4.2 * 0.55, 1e-9, "stagger slows footwork")
	var dead := _fighter()
	dead.weapon.phase = CombatPhase.Id.DEAD
	assert_eq(DuelFixture.steady_speed(dead, 0.0, 1.0, _rules.fighter, 10), 0.0, "the dead do not walk")


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
	ArenaConstraints.separate(a, b, _rules.fighter.body_radius, _limit())
	assert_near(DuelGeometry.distance(a, b), 0.54, 1e-9, "pushed apart to two radii")
	assert_near(a.vx - b.vx, 0.0, 1e-9, "approach velocity removed")


func test_coincident_bodies_separate_deterministically() -> void:
	var a := _fighter()
	var b := _fighter()
	DuelFixture.place(a, 1.0, 1.0, 0.0)
	DuelFixture.place(b, 1.0, 1.0, 0.0)
	ArenaConstraints.separate(a, b, _rules.fighter.body_radius, _limit())
	assert_near(a.x, 0.73, 1e-9, "slot 0 resolved toward -x")
	assert_near(b.x, 1.27, 1e-9, "slot 1 resolved toward +x")
	assert_eq(a.y, 1.0, "no vertical drift")


## The wall cannot move. Splitting the push evenly and then pulling the pinned
## fighter back inside would silently undo half of it, so a pair crowded into
## the boundary would stay overlapped — which is exactly where duel-relative
## footwork drives them, since both players push straight at each other.
func test_bodies_crowded_against_the_wall_still_separate() -> void:
	var limit := _limit()
	var a := _fighter()
	var b := _fighter()
	b.slot = 1
	DuelFixture.place(a, limit, 0.0, 0.0)
	DuelFixture.place(b, limit - 0.05, 0.0, PI)
	ArenaConstraints.resolve(a, b, _rules)
	assert_true(SimMath.length(a.x, a.y) <= limit + 1e-9, "the pinned fighter stays inside the arena")
	assert_true(SimMath.length(b.x, b.y) <= limit + 1e-9, "and so does the other")
	assert_true(DuelGeometry.distance(a, b) >= 2.0 * _rules.fighter.body_radius - 1e-9, "yet they are fully apart")


func test_violent_reversal_costs_stability() -> void:
	var calm := _fighter()
	DuelFixture.steady_speed(calm, 0.0, 0.0, _rules.fighter, 30)
	assert_eq(calm.stability, 1.0, "standing still is planted")
	var lunging := _fighter()
	DuelFixture.steady_speed(lunging, 0.0, 1.0, _rules.fighter, 60)
	DuelFixture.steady_speed(lunging, 0.0, -1.0, _rules.fighter, 8)
	assert_true(lunging.stability < 0.95, "reversing at speed unsettles the body (%s)" % str(lunging.stability))
	assert_true(lunging.stability >= _rules.fighter.stability_floor, "never below the floor")


## MOVE-001. A duel is fought along the line between two people, so that is
## what the controls have to mean. The same key must close the distance no
## matter where the pair has drifted to — not advance, sidestep, or retreat
## depending on the arena's compass.
func test_forward_closes_on_the_opponent_from_any_bearing() -> void:
	for bearing in PackedFloat64Array([0.0, PI / 2.0, 2.4, -1.1, PI]):
		var fighter := _fighter()
		var opponent := _fighter()
		opponent.slot = 1
		DuelFixture.place(opponent, 4.0 * SimMath.cosine(bearing), 4.0 * SimMath.sine(bearing), bearing + PI)
		var before := DuelGeometry.distance(fighter, opponent)
		for _i in 20:
			MovementSystem.step(fighter, opponent, 0.0, 1.0, 0, _rules.fighter)
		assert_true(DuelGeometry.distance(fighter, opponent) < before, "forward closes from bearing %.2f" % bearing)
		assert_near(SimMath.length(fighter.duel_forward_x, fighter.duel_forward_y), 1.0, 1e-9, "and the remembered axis stays a unit vector")


## The bearing is the opponent's *position*, not the fighter's torso. A body
## mid-recovery is turning, and if footwork rode the facing the fighter would
## walk off at an angle they never asked for.
func test_footwork_follows_the_opponents_bearing_not_the_bodys_facing() -> void:
	var fighter := _fighter()
	var opponent := _fighter()
	opponent.slot = 1
	DuelFixture.place(opponent, 0.0, 4.0, -PI / 2.0)
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	assert_eq(fighter.facing, 0.0, "precondition: the torso points along +X, the opponent lies along +Y")
	MovementSystem.step(fighter, opponent, 0.0, 1.0, 0, _rules.fighter)
	assert_near(fighter.vx, 0.0, 1e-9, "no drift along the facing")
	assert_true(fighter.vy > 0.0, "the step goes toward the opponent")


## Two fighters can end up standing on the same spot, where the bearing is
## numerically meaningless. Rather than invent a direction or stall, the last
## heading that *was* meaningful carries the step.
func test_coincident_fighters_keep_their_last_duel_axis() -> void:
	var fighter := _fighter()
	var opponent := _fighter()
	opponent.slot = 1
	DuelFixture.place(opponent, 0.0, 4.0, -PI / 2.0)
	MovementSystem.step(fighter, opponent, 0.0, 1.0, 0, _rules.fighter)
	assert_near(fighter.duel_forward_y, 1.0, 1e-9, "precondition: the axis points along +Y")
	DuelFixture.place(opponent, fighter.x, fighter.y, 0.0)
	MovementSystem.step(fighter, opponent, 0.0, 1.0, 0, _rules.fighter)
	assert_near(fighter.duel_forward_y, 1.0, 1e-9, "the remembered axis survives zero separation")
	assert_true(fighter.vy > 0.0, "and footwork keeps going rather than stalling or snapping")


## MOVE-001. Retreating does recover facing faster, but only because walking
## backwards shrinks the circle the opponent has to be tracked around.
## Granting a turn-speed bonus for it would be an invisible stat buff.
func test_retreat_recovers_facing_through_geometry_not_a_turn_bonus() -> void:
	var definition := _rules.fighter
	var near := _fighter()
	var orbiting := _fighter()
	orbiting.slot = 1
	DuelFixture.place(orbiting, 1.0, 0.0, PI)
	orbiting.vy = 2.0
	var far := _fighter()
	var distant := _fighter()
	distant.slot = 1
	DuelFixture.place(distant, 4.0, 0.0, PI)
	distant.vy = 2.0
	assert_true(
		absf(DuelGeometry.orbit_rate(near, orbiting)) > absf(DuelGeometry.orbit_rate(far, distant)),
		"the same sidestep sweeps a wider angle up close, so measure alone changes how hard tracking is"
	)
	var retreating := _fighter()
	DuelFixture.steady_speed(retreating, 0.0, -1.0, definition, 60)
	assert_true(retreating.speed() > 0.0, "precondition: actually backpedalling")
	assert_eq(_rules.fighter.turn_speed_max, definition.turn_speed_max, "and no movement state touches the turn ceiling")


## MOVE-001. Two fighters both pushing forward are each driving straight at
## the other, which is the hardest case for separation: no tick may end with
## their centers overlapping, and neither may end up behind the other.
func test_both_fighters_charging_never_cross_through_each_other() -> void:
	var runner := SimRunner.create(_rules, 11)
	runner.skip_intro()
	var touching := 2.0 * _rules.fighter.body_radius
	var opening := signf(runner.state.fighter(1).x - runner.state.fighter(0).x)
	for _i in 180:
		runner.simulation.step(
			runner.state,
			PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false),
			PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false)
		)
		var gap := DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1))
		assert_true(gap >= touching - 1e-9, "bodies stay apart (gap %.6f)" % gap)
		assert_eq(signf(runner.state.fighter(1).x - runner.state.fighter(0).x), opening, "and neither walks through the other")


## MOVE-001. A buffer longer than a few frames fires an attack the player has
## already mentally abandoned, which reads as the game acting on its own.
func test_the_input_buffer_stays_short() -> void:
	assert_true(_rules.weapon.buffer_ticks <= WeaponDefinition.BUFFER_TICKS_LIMIT, "authored buffer is within the limit")
	var over := DuelFixture.rules()
	over.weapon.buffer_ticks = WeaponDefinition.BUFFER_TICKS_LIMIT + 1
	assert_false(over.weapon.is_valid(), "a longer buffer is rejected as invalid rules")


func test_coast_brakes_to_rest() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.fighter, 60)
	for _i in 30:
		MovementSystem.coast(fighter, _rules.fighter)
	assert_eq(fighter.speed(), 0.0, "coasting body comes to rest")
