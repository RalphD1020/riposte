extends TestCase

## FALLEN: a killed body is a body (Phase 15, FallenBodyState,
## FallenBodySystem) — thrown along the killing impulse, lying after its
## collapse, pushed and turned by the same contact impulse as everything else,
## sliding against ground friction instead of braking, and carried over the
## edge without touching how the round ended.
##
## See also: /docs/concepts/simulation.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "FALLEN"
	_rules = DuelFixture.rules()


## A round decided by killing fighter 1 at once (its body lies immediately),
## then the winner and the body placed: the body's centre at the origin lying
## along `yaw`, the winner `gap` metres off its surface along −Y and `offset`
## metres across.
func _pushed_scene(yaw: float, offset: float, gap: float = 0.05, mirror: float = 1.0) -> SimRunner:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	DuelFixture.kill(runner.state.fighter(1))
	runner.idle(1)
	var winner := runner.state.fighter(0)
	var body := runner.state.fighter(1)
	DuelFixture.place(body, 0.0, 0.0, 0.0)
	body.fallen.yaw = SimMath.wrap_angle(PI - yaw) if mirror < 0.0 else yaw
	body.fallen.spin = 0.0
	var reach := _rules.combatant(0).fighter.push_radius + _rules.combatant(0).fighter.lying_radius + gap
	DuelFixture.place(winner, offset * mirror, -reach, PI * 0.5)
	return runner


## Walk the winner straight at the body for `ticks`, returning the deepest
## overlap seen between the winner's push circle and the body's capsule (m).
func _walk(runner: SimRunner, ticks: int) -> float:
	var worst := 0.0
	for _i in ticks:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		worst = maxf(worst, -_gap(runner.state))
	return worst


func _gap(state: MatchState) -> float:
	var body := state.fighter(1)
	var winner := state.fighter(0)
	var h := _rules.combatant(0).fighter.lying_half_length
	var ux := SimMath.cosine(body.fallen.yaw)
	var uy := SimMath.sine(body.fallen.yaw)
	var t := SimMath.closest_param_on_segment(body.x - ux * h, body.y - uy * h, body.x + ux * h, body.y + uy * h, winner.x, winner.y)
	var along := (2.0 * t - 1.0) * h
	return SimMath.length(winner.x - body.x - ux * along, winner.y - body.y - uy * along) - _rules.combatant(0).fighter.push_radius - _rules.combatant(0).fighter.lying_radius


func test_a_kill_throws_the_body_along_the_killing_impulse() -> void:
	var runner := SimRunner.create(_rules, 7)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	b.x = a.x + SimMath.cosine(a.facing) * 1.1
	b.y = a.y + SimMath.sine(a.facing) * 1.1
	b.health = 1.0
	assert_false(b.fallen.active, "fixture: the living are not bodies")
	runner.simulation.step(runner.state, PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	var killed := false
	for _i in 40:
		if not b.is_alive():
			killed = true
			break
		runner.idle(1)
	assert_true(killed, "fixture: the tap killed")
	var hit := runner.first(DuelEventTypes.BODY_HIT)
	assert_true(b.fallen.active, "the dead fighter is a body")
	assert_eq(String(hit.text(DuelEventKeys.CONTACT_KIND)) if hit != null else "", "slash", "fixture: killed by a cut")
	assert_true(b.fallen.settle_left > 0 and b.fallen.settle_left <= _rules.combat.fallen_settle_ticks_cut, "collapsing for a cut's settle (%d ticks left)" % b.fallen.settle_left)
	var away := SimMath.arctan2(b.y - a.y, b.x - a.x)
	assert_true(SimMath.cosine(b.fallen.yaw - away) > 0.0, "thrown away from the blade that killed it (yaw %.2f, away %.2f)" % [b.fallen.yaw, away])
	runner.idle(_rules.combat.fallen_settle_ticks_cut + 1)
	assert_true(b.fallen.is_lying(), "and lying once the collapse is over")


## A walking winner pushes a lying body ahead of them: it moves along the push,
## a push through its middle does not turn it, and the two never sink into
## each other beyond the arena's rest margin.
func test_a_winner_pushes_a_lying_body() -> void:
	var runner := _pushed_scene(0.0, 0.0)
	var body := runner.state.fighter(1)
	assert_eq(runner.state.phase, MatchPhase.Id.POST_ROUND_FREE, "fixture: the round is decided")
	assert_true(body.fallen.is_lying(), "fixture: the body lies across the winner's path")
	var worst := _walk(runner, 60)
	assert_true(body.y > 0.1, "pushed ahead along the walk (%.3f m)" % body.y)
	assert_true(absf(body.fallen.spin) < 1.0e-6 and absf(body.fallen.yaw) < 1.0e-6, "a push through its middle does not turn it")
	assert_true(worst < 1.0e-6, "and the winner never sinks into it (%.6f m)" % worst)


## A push near one end turns the body about its centre of mass — the torque of
## the same contact impulse — and the mirrored scene turns it the other way.
func test_an_off_centre_push_turns_the_body_and_mirrors() -> void:
	var offset := _rules.combatant(0).fighter.lying_half_length * 0.7
	var straight := _pushed_scene(0.0, offset)
	var reflected := _pushed_scene(0.0, offset, 0.05, -1.0)
	_walk(straight, 40)
	_walk(reflected, 40)
	var a := straight.state.fighter(1)
	var b := reflected.state.fighter(1)
	assert_true(a.y > 0.05, "fixture: the body was pushed (%.3f m)" % a.y)
	assert_true(absf(SimMath.wrap_angle(a.fallen.yaw)) > 0.05, "pushed near one end, it turns (yaw %.3f rad)" % a.fallen.yaw)
	assert_near(b.x, -a.x, 1.0e-9, "the mirror moves it the mirrored way")
	assert_near(b.y, a.y, 1.0e-9, "as far")
	assert_near(SimMath.wrap_angle(b.fallen.yaw - (PI - a.fallen.yaw)), 0.0, 1.0e-9, "turned the mirrored way")
	assert_near(b.fallen.spin, -a.fallen.spin, 1.0e-9, "at the mirrored rate")


## A body has the fighter's real mass but no motor and no bracing: given the
## same speed, it slides much farther than a standing fighter brakes.
func test_a_body_is_easier_to_move_than_a_braced_fighter() -> void:
	var body := FighterState.new()
	body.health = 0.0
	body.fallen.begin(0.0, 0)
	var standing := FighterState.new()
	standing.health = _rules.combatant(0).fighter.max_health
	for fighter: FighterState in [body, standing]:
		fighter.vx = 2.0
	var events: Array[DuelEvent] = []
	for tick in 60:
		FallenBodySystem.step(body, _rules, tick, events)
		MovementSystem.coast(standing, _rules.combatant(0).fighter)
	assert_true(standing.x > 0.0, "fixture: the standing fighter slid a little before stopping (%.3f m)" % standing.x)
	assert_true(body.x > 2.0 * standing.x, "the body slides more than twice as far (%.3f vs %.3f m)" % [body.x, standing.x])
	var expected := 2.0 * 2.0 / (2.0 * _rules.combat.fallen_ground_friction * FallenBodySystem.GRAVITY)
	assert_near(body.x, expected, 0.05, "to where ground friction stops it (μ·g, %.3f m)" % expected)


## Pushed over the rim, a body's centre of mass crosses the edge once, swept:
## the corpse fall is a body going over, never a fighter losing their footing,
## so how the round ended — and the score — are untouched.
func test_a_body_carried_over_the_edge_keeps_the_result() -> void:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	DuelFixture.kill(runner.state.fighter(1))
	runner.idle(1)
	var state := runner.state
	var body := state.fighter(1)
	var scores := state.scores.duplicate()
	var reason := state.end_reason
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0)
	DuelFixture.place(body, _rules.platform_radius - 0.2, 0.0, 0.0)
	body.vx = 3.0
	assert_eq(body.terminal_kind(), FighterState.Terminal.KILLED, "fixture: a killed body")
	runner.idle(30)
	assert_true(body.fallen.over_edge, "it went over the edge")
	assert_eq(runner.count(DuelEventTypes.POST_ROUND_CORPSE_FALL), 1, "once")
	var fall := runner.first(DuelEventTypes.POST_ROUND_CORPSE_FALL)
	var toi := fall.number(DuelEventKeys.TOI)
	assert_true(toi >= 0.0 and toi <= 1.0, "at a swept instant of its tick (%.3f)" % toi)
	assert_false(body.is_falling, "a body going over is not a fighter losing their footing")
	assert_eq(body.terminal_kind(), FighterState.Terminal.KILLED, "so it still left the round killed")
	assert_eq(state.scores, scores, "the score is untouched")
	assert_eq(state.end_reason, reason, "and so is how the round ended")
	assert_eq(state.round_winner, 0, "and who won it")


## A body's state is carried, so it is hashed; and only the dead are bodies.
func test_a_body_is_hashed_and_only_the_dead_are_bodies() -> void:
	var runner := _pushed_scene(0.0, 0.0)
	var before := StateHasher.hash_state(runner.state)
	runner.state.fighter(1).fallen.spin = 0.25
	assert_true(StateHasher.hash_state(runner.state) != before, "a body's spin is in the hash")
	runner.state.fighter(1).fallen.spin = 0.0
	assert_eq(StateHasher.hash_state(runner.state), before, "and only it changed")
	var living := runner.state.fighter(0)
	assert_eq(StateInvariants.check_fighter(living, _rules), StateInvariants.OK, "fixture: the winner is sound")
	living.fallen.active = true
	assert_eq(StateInvariants.check_fighter(living, _rules), StateInvariants.FALLEN_ALIVE, "a living fighter is never a body")


func test_a_closed_edge_holds_a_body_instead_of_a_corpse_fall() -> void:
	var rules := StandardDuelRules.pit()
	var body := FighterState.new()
	body.slot = 0
	body.health = 0.0
	body.fallen.begin(0.0, 0)
	var half := rules.combatant(0).fighter.lying_half_length
	var limit := rules.platform_radius - half
	body.x = limit + 0.5
	body.vx = 3.0
	var events: Array[DuelEvent] = []
	FallenBodySystem.step(body, rules, 1, events)
	assert_eq(events.size(), 0, "a closed edge does not emit a corpse fall")
	assert_false(body.fallen.over_edge, "the body stays on the floor")
	assert_near(body.x, limit, 1e-6, "its centre is held inside its lying length")
	assert_true(body.x + half <= rules.platform_radius + 1.0e-6, "the far end of the body stays inside the disc")
	assert_near(body.vx, 0.0, 1e-6, "and its outward speed is gone")
