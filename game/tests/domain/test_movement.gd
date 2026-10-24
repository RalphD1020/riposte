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
	return _rules.platform_radius - _rules.combatant(0).fighter.push_radius


func _fighter() -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	return fighter


func test_velocity_ramps_instead_of_teleporting() -> void:
	var fighter := _fighter()
	assert_eq(fighter.speed(), 0.0, "starts at rest")
	DuelFixture.spar(fighter, 0.0, 1.0, _rules.combatant(0).fighter)
	assert_near(fighter.speed(), 22.0 / 60.0, 1e-9, "one tick adds accel × dt")
	var reached := DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.combatant(0).fighter, 40)
	assert_near(reached, 4.2, 1e-9, "settles at forward max speed")


## Duel axes: `(0, 1)` closes, `(0, -1)` retreats, `(±1, 0)` orbits.
func test_backward_and_lateral_are_slower_than_forward() -> void:
	var forward := DuelFixture.steady_speed(_fighter(), 0.0, 1.0, _rules.combatant(0).fighter, 60)
	var lateral := DuelFixture.steady_speed(_fighter(), 1.0, 0.0, _rules.combatant(0).fighter, 60)
	var backward := DuelFixture.steady_speed(_fighter(), 0.0, -1.0, _rules.combatant(0).fighter, 60)
	assert_near(forward, 4.2, 1e-9, "forward 4.2 m/s")
	assert_near(lateral, 4.2 * 0.92, 1e-9, "lateral 92%")
	assert_near(backward, 4.2 * 0.78, 1e-9, "backward 78%")


func test_reversal_is_not_instant() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.combatant(0).fighter, 60)
	assert_near(fighter.vx, 4.2, 1e-9, "precondition: full forward speed")
	DuelFixture.spar(fighter, 0.0, -1.0, _rules.combatant(0).fighter)
	assert_true(fighter.vx > 0.0, "still moving forward one tick after reversing input")


func test_braking_beats_accelerating() -> void:
	var fighter := _fighter()
	var accelerate_ticks := 0
	while fighter.speed() < 4.2 - 1e-9 and accelerate_ticks < 120:
		DuelFixture.spar(fighter, 0.0, 1.0, _rules.combatant(0).fighter)
		accelerate_ticks += 1
	var brake_ticks := 0
	while fighter.speed() > 0.0 and brake_ticks < 120:
		DuelFixture.spar(fighter, 0.0, 0.0, _rules.combatant(0).fighter)
		brake_ticks += 1
	assert_true(brake_ticks < accelerate_ticks, "stopping (%d) is quicker than reaching speed (%d)" % [brake_ticks, accelerate_ticks])


func test_commitment_costs_acceleration_not_top_speed() -> void:
	## PHYS-003: a committed fighter is not slowed, only made sluggish. Given
	## enough runway they reach the same top speed; what they lose is the
	## ability to get there — or away — quickly.
	var fighter := _fighter()
	DuelFixture.commit(fighter, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	assert_near(fighter.weapon.commitment, 1.0, 1e-9, "precondition: heavy swing is fully committed")
	var free := _fighter()
	var free_speed := DuelFixture.steady_speed(free, 0.0, 1.0, _rules.combatant(0).fighter, 120)
	var committed := DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.combatant(0).fighter, 120)
	assert_near(committed, free_speed, 1e-9, "the same top speed is reachable while committed")
	var sluggish := _fighter()
	DuelFixture.commit(sluggish, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	var quick := _fighter()
	for _i in 6:
		DuelFixture.spar(sluggish, 0.0, 1.0, _rules.combatant(0).fighter)
		DuelFixture.spar(quick, 0.0, 1.0, _rules.combatant(0).fighter)
	assert_true(sluggish.speed() < quick.speed() * 0.6, "but reaching it takes far longer (%.2f vs %.2f after 6 ticks)" % [sluggish.speed(), quick.speed()])


func test_staggered_and_dead_fighters_move_poorly() -> void:
	var staggered := _fighter()
	staggered.weapon.phase = CombatPhase.Id.STAGGER
	assert_near(DuelFixture.steady_speed(staggered, 0.0, 1.0, _rules.combatant(0).fighter, 120), 4.2 * 0.55, 1e-9, "stagger slows footwork")
	var dead := _fighter()
	dead.weapon.phase = CombatPhase.Id.DEAD
	assert_eq(DuelFixture.steady_speed(dead, 0.0, 1.0, _rules.combatant(0).fighter, 10), 0.0, "the dead do not walk")


func test_arena_edge_is_open() -> void:
	var fighter := _fighter()
	DuelFixture.place(fighter, _rules.platform_radius - 0.01, 0.0, 0.0)
	fighter.vx = 3.0
	var finish_x := fighter.x + fighter.vx / 60.0
	var crossing := ArenaConstraints.detect_edge_crossing(
		fighter.x, fighter.y, finish_x, fighter.y, _rules.platform_radius
	)
	assert_true(crossing > 0.0, "a fighter moving outward near the edge crosses it")


func test_bodies_never_overlap() -> void:
	var a := _fighter()
	var b := _fighter()
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.3, 0.0, PI)
	a.vx = 2.0
	b.vx = -2.0
	ArenaConstraints.separate(a, b, _rules.combatant(0).fighter.push_radius, _rules.combatant(1).fighter.push_radius, 1.0, 1.0)
	assert_near(DuelGeometry.distance(a, b), 0.54 + ArenaConstraints.BODY_CONTACT_REST_EPSILON, 1e-9, "pushed apart to two radii (resting just outside touching)")
	assert_near(a.vx - b.vx, 0.0, 1e-9, "approach velocity removed")


func test_coincident_bodies_separate_deterministically() -> void:
	var a := _fighter()
	var b := _fighter()
	DuelFixture.place(a, 1.0, 1.0, 0.0)
	DuelFixture.place(b, 1.0, 1.0, 0.0)
	ArenaConstraints.separate(a, b, _rules.combatant(0).fighter.push_radius, _rules.combatant(1).fighter.push_radius, 1.0, 1.0)
	var half := ArenaConstraints.BODY_CONTACT_REST_EPSILON * 0.5
	assert_near(a.x, 0.73 - half, 1e-9, "slot 0 resolved toward -x")
	assert_near(b.x, 1.27 + half, 1e-9, "slot 1 resolved toward +x")
	assert_eq(a.y, 1.0, "no vertical drift")


## Body separation works near the edge without confinement. With an open arena,
## overlapping bodies push apart normally; there is no wall to complicate the
## mass-weighted correction.
func test_bodies_near_edge_still_separate() -> void:
	var a := _fighter()
	var b := _fighter()
	b.slot = 1
	DuelFixture.place(a, 6.0, 0.0, 0.0)
	DuelFixture.place(b, 6.05, 0.0, PI)
	ArenaConstraints.resolve(a, b, _rules)
	assert_true(DuelGeometry.distance(a, b) >= 2.0 * _rules.combatant(0).fighter.push_radius - 1e-9, "bodies are fully apart")


func test_violent_reversal_costs_stability() -> void:
	var calm := _fighter()
	DuelFixture.steady_speed(calm, 0.0, 0.0, _rules.combatant(0).fighter, 30)
	assert_eq(calm.stability, 1.0, "standing still is planted")
	var lunging := _fighter()
	DuelFixture.steady_speed(lunging, 0.0, 1.0, _rules.combatant(0).fighter, 60)
	DuelFixture.steady_speed(lunging, 0.0, -1.0, _rules.combatant(0).fighter, 8)
	assert_true(lunging.stability < 0.95, "reversing at speed unsettles the body (%s)" % str(lunging.stability))
	assert_true(lunging.stability >= _rules.combatant(0).fighter.stability_floor, "never below the floor")


## MOVE-FRAME-001 (MOVEMENT-FRAME-001). Footwork is expressed in the fighter's
## CombatHeading φ, read at the start of the tick. Wherever the opponent
## stands — the bearing τ anywhere round the compass, φ unchanged — the same
## forward key drives the body down φ, identically. τ reaches the feet only
## by turning φ, which takes ticks.
func test_forward_follows_the_heading_wherever_the_opponent_stands() -> void:
	var heading := 0.3
	var velocities: Array[Vector2] = []
	for bearing: float in [0.0, PI / 2.0, 2.4, -1.1, PI]:
		## ARRANGE
		var runner := SimRunner.create(_rules, 1)
		runner.skip_intro()
		var me := runner.state.fighter(0)
		var opponent := runner.state.fighter(1)
		DuelFixture.place(me, 0.0, 0.0, heading)
		## PERTURB: τ swings round the compass; φ stays put.
		DuelFixture.place(opponent, 3.0 * cos(bearing), 3.0 * sin(bearing), bearing + PI)
		## ACT: one tick of forward from rest.
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		## ASSERT
		var along := me.vx * SimMath.cosine(heading) + me.vy * SimMath.sine(heading)
		var across := -me.vx * SimMath.sine(heading) + me.vy * SimMath.cosine(heading)
		assert_true(along > 0.0, "forward drives down the heading (τ = %.2f)" % bearing)
		assert_near(across, 0.0, 1e-12, "with nothing toward the opponent (τ = %.2f)" % bearing)
		velocities.append(Vector2(me.vx, me.vy))
	for index in range(1, velocities.size()):
		assert_eq(velocities[index], velocities[0], "and the step is the same step whatever τ is (case %d)" % index)


## MOVE-FRAME-002. Let φ catch τ: the opponent broadside, the forward key
## held. Every tick the frame footwork used is exactly the heading the tick
## started with, the heading moves a bounded amount per tick, and once φ has
## caught τ, forward closes on the opponent — continuously, never by a snap.
func test_forward_follows_the_heading_as_it_catches_the_bearing() -> void:
	## ARRANGE
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var me := runner.state.fighter(0)
	var opponent := runner.state.fighter(1)
	DuelFixture.place(me, 0.0, 0.0, 0.0)
	DuelFixture.place(opponent, 0.0, 3.0, -PI / 2.0)
	var definition := _rules.combatant(0).fighter
	## ACT + ASSERT, tick by tick.
	var largest_turn := 0.0
	for _i in 90:
		var start := me.facing
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		assert_eq(me.duel_forward_x, SimMath.cosine(start), "the frame is the tick-start heading (x)")
		assert_eq(me.duel_forward_y, SimMath.sine(start), "the frame is the tick-start heading (y)")
		largest_turn = maxf(largest_turn, absf(SimMath.wrap_angle(me.facing - start)))
	var bearing := atan2(opponent.y - me.y, opponent.x - me.x)
	assert_true(largest_turn <= definition.turn_speed_max * SimulationTimebase.TICK_SECONDS + 1e-12, "the heading never jumps more than its rate cap (%.4f rad)" % largest_turn)
	assert_true(absf(SimMath.wrap_angle(me.facing - bearing)) < 0.1, "φ has caught τ (%.3f rad off)" % SimMath.wrap_angle(me.facing - bearing))
	assert_true(me.vx * cos(bearing) + me.vy * sin(bearing) > 0.0, "and forward now closes on the opponent")


## MOVE-FRAME-003. Reflect the scene across the world X axis and flip the
## lateral key: every step, slide and dash comes out the reflection — exact to
## the last rounding of the sine series, the one part that is not exactly odd.
## Right is right of φ, left is left of it, on either side of the arena.
func test_frame_movement_mirrors_exactly() -> void:
	## ARRANGE: a fighter turned off-axis, already drifting, and its reflection.
	var definition := _rules.combatant(0).fighter
	var me := _fighter()
	var mirrored := _fighter()
	DuelFixture.place(me, 0.4, 0.7, 0.6)
	DuelFixture.place(mirrored, 0.4, -0.7, -0.6)
	me.vx = 1.1
	me.vy = 0.5
	mirrored.vx = 1.1
	mirrored.vy = -0.5
	var inputs: Array[Vector2] = [Vector2(0.7, 0.4), Vector2(1.0, 0.0), Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(-0.3, -1.0)]
	## ACT: varied footwork including a lateral double-tap.
	var worst := 0.0
	for tick in 60:
		var input := inputs[int(tick / 3.0) % inputs.size()]
		MovementSystem.step(me, input.x, input.y, tick, definition)
		MovementSystem.step(mirrored, -input.x, input.y, tick, definition)
		worst = maxf(worst, absf(me.vx - mirrored.vx) + absf(me.vy + mirrored.vy) + absf(me.duel_forward_x - mirrored.duel_forward_x) + absf(me.duel_forward_y + mirrored.duel_forward_y))
	## ASSERT
	assert_true(SimMath.length(me.vx, me.vy) > 0.0, "precondition: the fighter moved")
	assert_true(worst < 1e-12, "every tick is the reflection (%s)" % String.num_scientific(worst))
	assert_eq(me.gesture.burst_kind == MovementGestureState.BurstKind.NONE, mirrored.gesture.burst_kind == MovementGestureState.BurstKind.NONE, "and the gestures agree on whether a burst is live")


## MOVE-001. Retreating does recover facing faster, but only because walking
## backwards shrinks the circle the opponent has to be tracked around.
## Granting a turn-speed bonus for it would be an invisible stat buff.
func test_retreat_recovers_facing_through_geometry_not_a_turn_bonus() -> void:
	var definition := _rules.combatant(0).fighter
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
	assert_eq(_rules.combatant(0).fighter.turn_speed_max, definition.turn_speed_max, "and no movement state touches the turn ceiling")


## MOVE-001. Two fighters both pushing forward are each driving straight at
## the other, which is the hardest case for separation: no tick may end with
## their centers overlapping, and neither may end up behind the other.
func test_both_fighters_charging_never_cross_through_each_other() -> void:
	var runner := SimRunner.create(_rules, 11)
	runner.skip_intro()
	var touching := 2.0 * _rules.combatant(0).fighter.push_radius
	var separation := DuelFixture.separation(runner.state)
	assert_true(separation.length() > touching, "fixture: the fighters open apart")
	for _i in 180:
		runner.simulation.step(
			runner.state,
			PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false),
			PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false)
		)
		var gap := DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1))
		assert_true(gap >= touching - 1e-9, "bodies stay apart (gap %.6f)" % gap)
		var now := DuelFixture.separation(runner.state)
		assert_true(now.dot(separation) > 0.0, "and neither walks through the other (tick %d)" % runner.state.tick)
		separation = now


## MOVE-001. A buffer longer than a few frames fires an attack the player has
## already mentally abandoned, which reads as the game acting on its own.
func test_a_closed_edge_holds_the_centre_and_drops_outward_speed() -> void:
	var rules := StandardDuelRules.pit()
	var fighter := _fighter()
	var push := rules.spec_of(fighter).fighter.push_radius
	var limit := rules.platform_radius - push
	fighter.x = limit + 1.0
	fighter.y = 0.0
	fighter.vx = 4.0
	fighter.vy = 1.0
	ArenaConstraints.constrain(fighter, rules)
	assert_near(fighter.x, limit, 1e-9, "the centre comes back to the support radius")
	assert_near(fighter.vx, 0.0, 1e-9, "outward speed is removed")
	assert_near(fighter.vy, 1.0, 1e-9, "tangent speed stays")
	fighter.x = limit
	fighter.vx = 2.0
	ArenaConstraints.constrain(fighter, rules)
	assert_near(fighter.x, limit, 1e-9, "a centre already on the support radius stays")
	assert_near(fighter.vx, 0.0, 1e-9, "and still cannot keep walking out")
	fighter.vx = -2.0
	fighter.vy = 1.5
	ArenaConstraints.constrain(fighter, rules)
	assert_near(fighter.vx, -2.0, 1e-9, "inward speed on the circle stays")
	assert_near(fighter.vy, 1.5, 1e-9, "tangent speed on the circle stays")
	var inside := _fighter()
	inside.x = rules.spawn_offset
	inside.vx = 3.0
	inside.vy = 1.0
	ArenaConstraints.constrain(inside, rules)
	assert_eq(inside.x, rules.spawn_offset, "a centre inside the disc is not pulled")
	assert_eq(inside.vx, 3.0, "and its outward speed is not taken")
	assert_eq(inside.vy, 1.0, "nor its tangent")
	var open := _fighter()
	open.x = _rules.platform_radius
	open.vx = 3.0
	ArenaConstraints.constrain(open, _rules)
	assert_eq(open.x, _rules.platform_radius, "an open edge does not pull the centre back")
	assert_eq(open.vx, 3.0, "and does not take its speed")
	var falling := _fighter()
	falling.is_falling = true
	falling.x = limit + 2.0
	ArenaConstraints.constrain(falling, rules)
	assert_eq(falling.x, limit + 2.0, "a fighter who already lost support is left on the fall")
	var centre := _fighter()
	centre.vx = 3.0
	ArenaConstraints.constrain(centre, rules)
	assert_eq(centre.vx, 3.0, "a centre at the origin is not given a normal")
	var tight := StandardDuelRules.pit()
	tight.platform_radius = push
	var parked := _fighter()
	parked.x = 1.0
	ArenaConstraints.constrain(parked, tight)
	assert_eq(parked.x, 1.0, "no support radius means no pull")


## MOVE-001. Both fighters face each other, so a retreat is away from the
## centre. The closed hold must not delete that step. These drives go through
## `DuelSimulation`, which is what calls `constrain` after the movement system.
func test_retreat_from_the_spawn_on_a_closed_edge_moves_outward() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 21)
	runner.skip_intro()
	var mover := runner.state.fighter(0)
	var home := SimMath.length(mover.x, mover.y)
	assert_near(home, rules.spawn_offset, 1e-6, "fixture: the production spawn")
	_drive(runner, 0, 0.0, -1.0, 45)
	var retreated := SimMath.length(mover.x, mover.y)
	assert_true(retreated > home + 0.4, "retreat increases distance from the centre (%.3f -> %.3f)" % [home, retreated])
	assert_true(retreated < rules.platform_radius - 1.0, "and has not reached the wall")
	assert_true(_radial(mover) > 0.4, "outward speed survives inside the disc")
	assert_eq(runner.count(DuelEventTypes.RING_OUT), 0, "the arena does not ring out")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_forward_from_the_spawn_on_a_closed_edge_closes() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 21)
	runner.skip_intro()
	var mover := runner.state.fighter(0)
	var home := SimMath.length(mover.x, mover.y)
	_drive(runner, 0, 0.0, 1.0, 30)
	var closed := SimMath.length(mover.x, mover.y)
	assert_true(closed < home - 0.3, "forward stride decreases distance from the centre (%.3f -> %.3f)" % [home, closed])
	assert_true(_radial(mover) < -0.4, "that velocity points inward")
	assert_eq(runner.count(DuelEventTypes.RING_OUT), 0, "closing is not a ring-out")


func test_lateral_and_diagonal_footwork_keep_their_components() -> void:
	var rules := StandardDuelRules.pit()
	var lateral := SimRunner.create(rules, 21)
	lateral.skip_intro()
	var side := lateral.state.fighter(0)
	assert_near(side.x, 0.0, 1e-6, "fixture: the spawn is on the north-south axis")
	_drive(lateral, 0, 1.0, 0.0, 30)
	assert_true(absf(side.x) > 0.3, "lateral footwork leaves the spawn axis")
	assert_true(absf(side.vx) > 0.4, "and keeps a tangent speed")
	var diagonal := SimRunner.create(rules, 21)
	diagonal.skip_intro()
	var mover := diagonal.state.fighter(0)
	var home := SimMath.length(mover.x, mover.y)
	_drive(diagonal, 0, 1.0, -1.0, 30)
	assert_true(absf(mover.x) > 0.2, "a diagonal keeps its lateral part")
	assert_true(SimMath.length(mover.x, mover.y) > home + 0.2, "and its retreat still leaves the centre")
	assert_true(_radial(mover) > 0.2, "so the outward part was not stripped")


func test_the_support_circle_removes_only_outward_speed() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 21)
	runner.skip_intro()
	var mover := runner.state.fighter(0)
	var push := rules.combatant(0).fighter.push_radius
	var limit := rules.platform_radius - push
	_drive(runner, 0, 0.0, -1.0, 160)
	var reached := SimMath.length(mover.x, mover.y)
	assert_true(reached > limit - 0.15, "the retreat arrived at the wall (%.3f, limit %.3f)" % [reached, limit])
	assert_true(reached <= limit + 1e-4, "and did not pass it")
	assert_true(_radial(mover) <= 0.05, "outward speed is gone on the circle")
	assert_eq(runner.count(DuelEventTypes.RING_OUT), 0, "holding the wall is not a ring-out")
	var along := mover.x
	_drive(runner, 0, 1.0, 0.0, 30)
	assert_true(absf(mover.x - along) > 0.2, "tangent footwork still slides along the wall")
	assert_true(SimMath.length(mover.x, mover.y) <= limit + 1e-4, "the slide stays inside")
	assert_true(runner.is_sound(), runner.violation_summary())


func test_a_meeting_along_a_closed_wall_does_not_stick() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(DuelFixture.mirror(rules), 8)
	runner.skip_intro()
	var push := rules.combatant(0).fighter.push_radius
	var limit := rules.platform_radius - push
	var touching := 2.0 * push
	DuelFixture.place(runner.state.fighter(0), limit - 1.0, 1.1, 0.0)
	DuelFixture.place(runner.state.fighter(1), limit - 1.0, -1.1, 0.0)
	var start_0 := Vector2(runner.state.fighter(0).x, runner.state.fighter(0).y)
	var start_1 := Vector2(runner.state.fighter(1).x, runner.state.fighter(1).y)
	for i in 70:
		var dash := i % 20 == 0
		var east := PlayerCommand.create(runner.state.tick, 1.0, 0.0, false, false, false, dash)
		var west := PlayerCommand.create(runner.state.tick, -1.0, 0.0, false, false, false, dash)
		runner.push(east, west)
		var gap := DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1))
		assert_true(gap >= touching - 1e-6, "bodies stay apart along the wall (gap %.4f)" % gap)
		for slot in 2:
			var fighter := runner.state.fighter(slot)
			assert_true(SimMath.length(fighter.x, fighter.y) <= limit + 1e-4, "slot %d stays inside" % slot)
	assert_eq(runner.count(DuelEventTypes.RING_OUT), 0, "the meeting is not a ring-out")
	var mark_0 := Vector2(runner.state.fighter(0).x, runner.state.fighter(0).y)
	var mark_1 := Vector2(runner.state.fighter(1).x, runner.state.fighter(1).y)
	for _i in 30:
		var east := PlayerCommand.create(runner.state.tick, 1.0, 0.0)
		var west := PlayerCommand.create(runner.state.tick, -1.0, 0.0)
		runner.push(east, west)
	var later_0 := Vector2(runner.state.fighter(0).x, runner.state.fighter(0).y).distance_to(mark_0)
	var later_1 := Vector2(runner.state.fighter(1).x, runner.state.fighter(1).y).distance_to(mark_1)
	assert_true(later_0 > 0.25 or later_1 > 0.25, "footwork still covers ground after they meet (%.3f, %.3f)" % [later_0, later_1])
	assert_true(Vector2(runner.state.fighter(0).x, runner.state.fighter(0).y).distance_to(start_0) > 0.5, "slot 0 was not pinned at the start")
	assert_true(Vector2(runner.state.fighter(1).x, runner.state.fighter(1).y).distance_to(start_1) > 0.5, "slot 1 was not pinned at the start")
	assert_true(runner.is_sound(), runner.violation_summary())


func _drive(runner: SimRunner, slot: int, intent_x: float, intent_y: float, ticks: int) -> void:
	for _i in ticks:
		var move := PlayerCommand.create(runner.state.tick, intent_x, intent_y)
		var hold := PlayerCommand.idle(runner.state.tick)
		if slot == 0:
			runner.push(move, hold)
		else:
			runner.push(hold, move)


func _radial(fighter: FighterState) -> float:
	var dist := SimMath.length(fighter.x, fighter.y)
	if dist <= SimMath.EPSILON:
		return 0.0
	return (fighter.vx * fighter.x + fighter.vy * fighter.y) / dist


func test_walking_out_of_a_closed_arena_does_not_ring_out() -> void:
	var closed := _walk_south(StandardDuelRules.pit())
	assert_eq(closed.count(DuelEventTypes.RING_OUT), 0, "the closed edge emits no ring-out")
	assert_true(closed.is_sound(), closed.violation_summary())
	var walker := closed.state.fighter(0)
	var push := closed.rules.combatant(0).fighter.push_radius
	var limit := closed.rules.platform_radius - push
	assert_true(walker.is_alive() and not walker.is_falling, "the walker is still in the round")
	assert_true(SimMath.length(walker.x, walker.y) <= limit + 1e-4, "the centre stays inside the support radius")
	assert_true(walker.y < -(limit - 0.2), "the walk reached the wall")
	var open := _walk_south(DuelFixture.rules())
	assert_true(open.count(DuelEventTypes.RING_OUT) > 0, "the same walk on version 58 still rings out")


func _walk_south(rules: DuelRules) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.mirror(rules), 3)
	runner.skip_intro()
	var push := rules.combatant(0).fighter.push_radius
	var limit := rules.platform_radius - push
	DuelFixture.place(runner.state.fighter(0), 0.0, -(limit - 0.4), DuelSide.NORTH_FACING)
	DuelFixture.place(runner.state.fighter(1), 0.0, 2.0, DuelSide.SOUTH_FACING)
	for _i in 80:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, -1.0), PlayerCommand.idle(runner.state.tick))
	return runner


func test_a_sustained_push_into_a_closed_edge_stays_inside() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(DuelFixture.mirror(rules), 4)
	runner.skip_intro()
	var push := rules.combatant(0).fighter.push_radius
	var limit := rules.platform_radius - push
	DuelFixture.place(runner.state.fighter(0), limit - 0.4, 0.2, 0.0)
	DuelFixture.place(runner.state.fighter(1), limit - 0.4, -0.2, 0.0)
	for i in 150:
		var dash := i % 15 == 0
		var outward := PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, dash)
		runner.push(outward, outward)
	assert_eq(runner.count(DuelEventTypes.RING_OUT), 0, "a long shove into the wall is not a ring-out")
	assert_true(runner.is_sound(), runner.violation_summary())
	for slot in 2:
		var fighter := runner.state.fighter(slot)
		assert_true(SimMath.length(fighter.x, fighter.y) <= limit + 1.0e-4, "slot %d stays inside the support radius" % slot)
	DuelFixture.kill(runner.state.fighter(1))
	runner.idle(1)
	var body := runner.state.fighter(1)
	DuelFixture.place(body, limit - 0.05, 0.0, 0.0)
	body.vx = 8.0
	runner.idle(40)
	assert_eq(runner.count(DuelEventTypes.POST_ROUND_CORPSE_FALL), 0, "the body does not fall off a closed edge")
	assert_false(body.fallen.over_edge, "and it is not marked over the edge")
	assert_true(SimMath.length(body.x, body.y) <= limit + 1.0e-4, "its centre stays on the floor")
	var gap := DuelGeometry.distance(runner.state.fighter(0), body)
	assert_true(gap >= push * 2.0 - 0.05, "the pair is not left piled on one point (gap %.3f)" % gap)


func test_separation_on_a_closed_edge_cannot_leave_a_centre_outside() -> void:
	var rules := StandardDuelRules.pit()
	var a := _fighter()
	var b := _fighter()
	b.slot = 1
	var push := rules.combatant(0).fighter.push_radius
	var limit := rules.platform_radius - push
	DuelFixture.place(a, limit - 0.05, 0.0, 0.0)
	DuelFixture.place(b, limit + 0.2, 0.0, PI)
	ArenaConstraints.resolve(a, b, rules)
	assert_true(SimMath.length(a.x, a.y) <= limit + 1e-6, "the inner body stays inside")
	assert_true(SimMath.length(b.x, b.y) <= limit + 1e-6, "the body separation pushed out is pulled back")


func test_the_input_buffer_stays_short() -> void:
	assert_true(_rules.combatant(0).weapon.buffer_ticks <= WeaponDefinition.BUFFER_TICKS_LIMIT, "authored buffer is within the limit")
	var over := DuelFixture.rules()
	over.combatant(0).weapon.buffer_ticks = WeaponDefinition.BUFFER_TICKS_LIMIT + 1
	assert_false(over.combatant(0).weapon.is_valid(), "a longer buffer is rejected as invalid rules")


func test_coast_brakes_to_rest() -> void:
	var fighter := _fighter()
	DuelFixture.steady_speed(fighter, 0.0, 1.0, _rules.combatant(0).fighter, 60)
	for _i in 30:
		MovementSystem.coast(fighter, _rules.combatant(0).fighter)
	assert_eq(fighter.speed(), 0.0, "coasting body comes to rest")
