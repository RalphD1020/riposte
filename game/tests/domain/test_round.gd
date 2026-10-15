extends TestCase

## ROUND: round and match lifecycle (PLAN Phase 8): intro, kill, timeout,
## draws, best of five, deterministic resets.
##
## See also: /docs/concepts/simulation.md

## How far short of the victim the killer stands in the cut-at-the-edge scene
## (m): the blade starts 4.6 cm clear of the torso and the kill lands near a
## third of the way through the tick (body hits resolve at substep ends).
const CUT_STANDOFF := 1.30


func _init() -> void:
	suite_name = "ROUND"


func _runner(rules: DuelRules = null) -> SimRunner:
	return SimRunner.create(rules if rules != null else DuelFixture.rules(), 7)


## Kill `loser` (or both with -1) and wait out the post-round and result periods.
func _decide_round(runner: SimRunner, loser: int) -> void:
	runner.skip_intro()
	for slot in 2:
		if loser == -1 or slot == loser:
			DuelFixture.kill(runner.state.fighter(slot))
	runner.idle(1 + runner.simulation.rules.post_round_free_ticks + runner.simulation.rules.result_ticks)


func test_intro_lasts_its_ticks_then_the_round_starts() -> void:
	var runner := _runner()
	runner.idle(runner.simulation.rules.intro_ticks - 1)
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_INTRO, "still in the intro")
	assert_eq(runner.events.size(), 0, "nothing happens during the intro")
	runner.idle(1)
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_ACTIVE, "round begins")
	assert_eq(runner.first(DuelEventTypes.ROUND_STARTED).number(DuelEventKeys.ROUND), 1.0, "round 1 started")


func test_commands_during_the_intro_are_ignored() -> void:
	var runner := _runner()
	var x := runner.state.fighter(0).x
	for i in 10:
		runner.simulation.step(runner.state, PlayerCommand.create(i, 1.0, 0.0, true, false), PlayerCommand.idle(i))
	assert_eq(runner.state.fighter(0).x, x, "no movement during the intro")
	assert_eq(runner.state.fighter(0).weapon.phase, CombatPhase.Id.NEUTRAL, "no attack during the intro")


func test_a_kill_ends_the_round_and_scores() -> void:
	var runner := _runner()
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	## Stand the target just inside reach along whichever way `a` is actually
	## looking: spawns are cardinal and the sides are seeded (SIDE-001), so a
	## fixed world offset would sometimes put them off the attack line.
	b.x = a.x + SimMath.cosine(a.facing) * 1.1
	b.y = a.y + SimMath.sine(a.facing) * 1.1
	b.health = 1.0
	runner.simulation.step(runner.state, PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	runner.idle(40)
	assert_eq(runner.count(DuelEventTypes.BODY_HIT), 1, "the tap landed")
	assert_eq(runner.count(DuelEventTypes.FIGHTER_KILLED), 1, "and killed")
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "fighter 0 won the round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_KILL), "by kill")
	assert_eq(runner.state.scores, PackedInt32Array([1, 0]), "score 1–0")


func test_timeout_awards_the_healthier_fighter() -> void:
	var rules := DuelFixture.rules()
	rules.round_time_limit_ticks = 5
	var runner := _runner(rules)
	runner.skip_intro()
	runner.state.fighter(1).health = 90.0
	runner.idle(5)
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_true(ended != null, "time limit ends the round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_TIMEOUT), "by timeout")
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "healthier fighter wins")


func test_double_kill_is_a_drawn_round() -> void:
	var runner := _runner()
	_decide_round(runner, -1)
	var ended := runner.first(DuelEventTypes.ROUND_ENDED)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), MatchPhase.DRAW, "drawn round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_DOUBLE_KILL), "double kill")
	assert_eq(runner.state.scores, PackedInt32Array([0, 0]), "nobody scores")


## A mutual kill is only a draw when nothing separates the two blows. Give one
## blade a later arrival and the round must go the other way — and it must do
## so from either slot, or the arena itself is biased.
func test_a_trade_goes_to_whoever_fell_second() -> void:
	for fell_first in 2:
		var runner := _runner()
		runner.skip_intro()
		for slot in 2:
			DuelFixture.kill(runner.state.fighter(slot))
		runner.state.fighter(1 - fell_first).lethal_fraction = 0.5
		runner.idle(1 + runner.simulation.rules.post_round_free_ticks + runner.simulation.rules.result_ticks)
		var ended := runner.first(DuelEventTypes.ROUND_ENDED)
		assert_eq(int(ended.number(DuelEventKeys.WINNER)), 1 - fell_first, "the blade that landed first takes the round")
		assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_TRADE_FIRST_CONTACT), "as a trade, not a draw")
		assert_eq(runner.state.scores[1 - fell_first], 1, "and it scores")


## COMBAT-014 fixture: `slot` leaves the round by a lethal blow at `killed`
## and/or a lost footing at `fell` (negative = not that way), then the round is
## evaluated on the next tick.
func _terminal(runner: SimRunner, slot: int, killed: float, fell: float) -> void:
	var fighter := runner.state.fighter(slot)
	if killed >= 0.0:
		DuelFixture.kill(fighter)
		fighter.lethal_fraction = killed
	if fell >= 0.0:
		fighter.lose_support(fell)


func _ended(runner: SimRunner) -> DuelEvent:
	runner.idle(1)
	return runner.first(DuelEventTypes.ROUND_ENDED)


## COMBAT-014 through the real solver: a cut lands on a fighter drifting over
## the edge, `gap` metres inside it, in the same tick. The blade's geometry is
## identical for every gap (the scene only translates), so the kill instant is
## fixed and only the crossing instant moves. The blade starts clear of the
## torso, so the kill is a crossing the sweep finds mid-tick, not an overlap it
## inherited. Returns the runner one tick in.
func _cut_at_the_edge(gap: float) -> SimRunner:
	var runner := _runner()
	runner.skip_intro()
	var rules := runner.simulation.rules
	var edge := rules.platform_radius - gap
	var killer := runner.state.fighter(0)
	var victim := runner.state.fighter(1)
	ContactFixture.arm(killer, edge - CUT_STANDOFF, 0.0, 0.0, deg_to_rad(-20.0), 18.0, CombatPhase.Id.ACTIVE_THREAT, 0.0, rules.combatant(0).weapon)
	DuelFixture.place(victim, edge, 0.0, PI)
	DuelFixture.weapon_clear_of(victim, killer.x, killer.y)
	assert_true(ContactGauge.body(rules, killer, victim) > 0.0, "fixture: the cut starts clear of the torso (%.4f m)" % ContactGauge.body(rules, killer, victim))
	victim.vx = 3.0
	victim.health = 0.5
	runner.idle(1)
	return runner


## A fighter both cut down and over the edge in one tick left the round by
## whichever happened first — the solver's own times of impact and crossing,
## read once by `terminal_kind`, never the order the events were appended.
func test_a_kill_and_a_fall_on_one_fighter_are_ordered_by_the_solver() -> void:
	var killed_first := _cut_at_the_edge(0.04)
	var victim := killed_first.state.fighter(1)
	assert_true(not victim.is_alive() and victim.is_falling, "fixture: cut down and over the edge in one tick")
	assert_true(killed_first.is_sound(), "fixture: a legal state (%s)" % killed_first.violation_summary())
	assert_true(victim.lethal_fraction < victim.support_lost_fraction, "fixture: the blade arrived first (%.3f < %.3f)" % [victim.lethal_fraction, victim.support_lost_fraction])
	assert_eq(victim.terminal_kind(), FighterState.Terminal.KILLED, "so they were killed")
	var ended := _ended(killed_first)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "the survivor takes the round")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_KILL), "by the kill")
	var fell_first := _cut_at_the_edge(0.005)
	var faller := fell_first.state.fighter(1)
	assert_true(not faller.is_alive() and faller.is_falling, "fixture: the same cut, nearer the edge")
	assert_near(faller.lethal_fraction, victim.lethal_fraction, 1e-9, "perturbation: only the crossing moved, not the cut")
	assert_true(faller.support_lost_fraction < faller.lethal_fraction, "fixture: the edge came first (%.3f < %.3f)" % [faller.support_lost_fraction, faller.lethal_fraction])
	assert_eq(faller.terminal_kind(), FighterState.Terminal.RING_OUT, "so they rang out")
	assert_eq(_ended(fell_first).text(DuelEventKeys.REASON), String(MatchPhase.REASON_RING_OUT), "and the round says so")


## An exact tie between a fighter's own blow and lost footing reads as the
## kill: the blade arrived no later than the edge did (COMBAT-014). Staged by
## fixture, because an exact coincidence of two different physical instants
## cannot be built from geometry without a symmetric construction.
func test_an_exact_kill_and_fall_tie_reads_as_the_kill() -> void:
	var runner := _runner()
	runner.skip_intro()
	_terminal(runner, 1, 0.5, 0.5)
	assert_eq(runner.state.fighter(1).lethal_fraction, runner.state.fighter(1).support_lost_fraction, "fixture: the same instant")
	assert_eq(runner.state.fighter(1).terminal_kind(), FighterState.Terminal.KILLED, "the kill wins the tie")
	assert_eq(_ended(runner).text(DuelEventKeys.REASON), String(MatchPhase.REASON_KILL), "and names the round")


## A body push carries a fighter over the edge after the contact, not at it:
## the lost footing is stamped where their centre actually crossed in the
## carried remainder, so a kill later in the same tick is never out-ordered by
## the push's own time of impact (COMBAT-014).
func test_a_pushed_fighter_loses_the_edge_where_they_cross_not_at_the_contact() -> void:
	var crossings: Array[float] = []
	for gap: float in [0.005, 0.02]:
		var runner := _runner()
		runner.skip_intro()
		var rules := runner.simulation.rules
		var edge := rules.platform_radius - gap
		var pusher := runner.state.fighter(0)
		var target := runner.state.fighter(1)
		DuelFixture.place(pusher, edge - rules.combatant(0).fighter.push_radius * 2.0 - 0.07, 0.0, 0.0)
		DuelFixture.place(target, edge, 0.0, PI)
		DuelFixture.weapon_clear_of(pusher, target.x, target.y)
		DuelFixture.weapon_clear_of(target, pusher.x, pusher.y)
		pusher.vx = 8.0
		runner.idle(1)
		var push := runner.first(DuelEventTypes.BODY_PUSH)
		assert_true(push != null and target.is_falling, "fixture: the push carried them over (gap %.3f)" % gap)
		assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT) + runner.count(DuelEventTypes.BODY_HIT), 0, "fixture: bodies alone — no sword met anything (gap %.3f)" % gap)
		var contact := push.number(DuelEventKeys.TOI)
		assert_true(target.support_lost_fraction > contact, "they crossed after the contact (%.3f > %.3f)" % [target.support_lost_fraction, contact])
		assert_near(runner.first(DuelEventTypes.RING_OUT).number(DuelEventKeys.TOI), target.support_lost_fraction, 1e-12, "the ring-out reports the same instant")
		crossings.append(target.support_lost_fraction)
	assert_true(crossings[1] > crossings[0], "perturbation: farther from the edge crosses later in the tick")
	var impact := FighterPose.new()
	var carried := FighterState.new()
	impact.x = 2.0
	carried.x = 4.0
	assert_near(DuelSimulation.remainder_crossing(impact, carried, 0.6, 3.0), 0.8, 1e-12, "halfway through the remainder is halfway between the contact and the tick's end")
	impact.x = 3.5
	assert_eq(DuelSimulation.remainder_crossing(impact, carried, 0.6, 3.0), 0.6, "a body already past the edge at the contact crossed at the contact")


## A fighter who went over the edge before their opponent fell is out first,
## from either slot; and the reverse — a dead fighter never wins because the
## opponent lost the edge later in the same tick.
func test_a_same_tick_kill_and_ring_out_go_to_whoever_left_later() -> void:
	for faller in 2:
		var runner := _runner()
		runner.skip_intro()
		_terminal(runner, faller, -1.0, 0.2)
		_terminal(runner, 1 - faller, 0.6, -1.0)
		assert_true(runner.state.fighter(faller).is_alive(), "fixture: the faller is alive")
		var ended := _ended(runner)
		assert_eq(int(ended.number(DuelEventKeys.WINNER)), 1 - faller, "fell at 0.2, before the 0.6 kill: the faller is out first")
		assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_RING_OUT), "the loser's way out names the round")
		var late := _runner()
		late.skip_intro()
		_terminal(late, faller, -1.0, 0.8)
		_terminal(late, 1 - faller, 0.4, -1.0)
		var late_end := _ended(late)
		assert_eq(int(late_end.number(DuelEventKeys.WINNER)), faller, "killed at 0.4, before the 0.8 fall: the dead fighter loses")
		assert_eq(late_end.text(DuelEventKeys.REASON), String(MatchPhase.REASON_TRADE_FIRST_CONTACT), "as a decided trade")


func test_two_ring_outs_go_to_the_later_fall_and_a_tie_is_a_draw() -> void:
	var runner := _runner()
	runner.skip_intro()
	_terminal(runner, 0, -1.0, 0.5)
	_terminal(runner, 1, -1.0, 0.25)
	var ended := _ended(runner)
	assert_eq(int(ended.number(DuelEventKeys.WINNER)), 0, "the fighter who kept the edge longer wins")
	assert_eq(ended.text(DuelEventKeys.REASON), String(MatchPhase.REASON_RING_OUT), "by ring-out")
	var tie := _runner()
	tie.skip_intro()
	_terminal(tie, 0, -1.0, 0.5)
	_terminal(tie, 1, -1.0, 0.5)
	var tied := _ended(tie)
	assert_eq(int(tied.number(DuelEventKeys.WINNER)), MatchPhase.DRAW, "an exact tie has nothing to separate it")
	assert_eq(tied.text(DuelEventKeys.REASON), String(MatchPhase.REASON_RING_OUT), "and stays a ring-out")


## The one rule that says a set is decided, read the moment the deciding
## round's score is in — the same answer the match end uses after its beat.
func test_the_set_is_decided_by_one_rule() -> void:
	var rules := DuelFixture.rules()
	assert_eq(rules.rounds_to_win, 3, "fixture: first to three")
	assert_eq(MatchOutcome.set_winner(PackedInt32Array([2, 1]), 3, rules), MatchPhase.NO_WINNER, "two rounds is not a set")
	assert_eq(MatchOutcome.set_winner(PackedInt32Array([3, 1]), 4, rules), 0, "three is")
	assert_eq(MatchOutcome.set_winner(PackedInt32Array([2, 3]), 5, rules), 1, "from either slot")
	assert_eq(MatchOutcome.reason(PackedInt32Array([2, 3]), rules), MatchPhase.REASON_SCORE, "by score")
	assert_eq(MatchOutcome.set_winner(PackedInt32Array([2, 2]), rules.max_rounds, rules), MatchPhase.DRAW, "a level round limit is a draw")
	assert_eq(MatchOutcome.set_winner(PackedInt32Array([2, 1]), rules.max_rounds, rules), 0, "a led one goes to the leader")
	assert_eq(MatchOutcome.reason(PackedInt32Array([2, 1]), rules), MatchPhase.REASON_ROUND_LIMIT, "by the round limit")
	var runner := _runner()
	for _round in 2:
		_decide_round(runner, 1)
	runner.skip_intro()
	DuelFixture.kill(runner.state.fighter(1))
	runner.idle(1)
	assert_eq(runner.state.phase, MatchPhase.Id.POST_ROUND_FREE, "fixture: the third round just ended")
	assert_eq(SnapshotProjector.project(runner.state, runner.simulation.rules).set_winner, 0, "the snapshot names the winner at once")
	assert_eq(runner.state.match_winner, MatchPhase.NO_WINNER, "before the match itself ends")
	runner.idle(runner.simulation.rules.post_round_free_ticks + runner.simulation.rules.result_ticks)
	assert_eq(runner.state.match_winner, 0, "and the match end agrees")


## Decide the round on time with fighter 0 ahead on health, so the loser is
## alive and still sending commands — the gate has something real to refuse.
func _decide_on_time(runner: SimRunner) -> void:
	runner.skip_intro()
	runner.state.fighter(1).health -= 10.0
	runner.state.round_ticks = runner.simulation.rules.round_time_limit_ticks - 1
	runner.idle(1)


## The one input gate (Phase 14): while a round is fought both fighters act;
## once it is decided only its winner does — alive, on the platform — through
## the post-round freedom and the whole result, until the next intro.
func test_only_the_winner_keeps_control_until_the_next_intro() -> void:
	var runner := _runner()
	var rules := runner.simulation.rules
	runner.skip_intro()
	assert_true(DuelSimulation.accepts_gameplay_input(runner.state, 0) and DuelSimulation.accepts_gameplay_input(runner.state, 1), "a fought round reads both fighters")
	var fresh := _runner()
	assert_false(DuelSimulation.accepts_gameplay_input(fresh.state, 0), "the intro reads no one")
	_decide_on_time(runner)
	var state := runner.state
	assert_eq(state.phase, MatchPhase.Id.POST_ROUND_FREE, "fixture: the round was decided on time")
	assert_eq(state.round_winner, 0, "fixture: fighter 0 won it")
	assert_true(state.fighter(1).is_alive(), "fixture: the loser is alive")
	var loser_x := state.fighter(1).x
	var loser_y := state.fighter(1).y
	var decided_ticks := rules.post_round_free_ticks + rules.result_ticks
	for i in decided_ticks - 1:
		assert_true(DuelSimulation.accepts_gameplay_input(state, 0), "tick %d of the decided round: the winner acts" % i)
		assert_false(DuelSimulation.accepts_gameplay_input(state, 1), "tick %d: the loser does not" % i)
		runner.push(PlayerCommand.idle(state.tick), PlayerCommand.create(state.tick, 1.0, 1.0, true, false))
	assert_eq(state.phase, MatchPhase.Id.ROUND_RESULT, "fixture: the last tick of the result is next")
	assert_true(SimMath.length(state.fighter(1).x - loser_x, state.fighter(1).y - loser_y) < 0.05, "the loser's commands moved nothing")
	assert_eq(state.fighter(1).weapon.phase, CombatPhase.Id.NEUTRAL, "and started no attack")
	## Perturb: the winner taps on the result's very last tick. The same step
	## resets the round, so the answer is read from the tick's own events.
	var released := runner.count(DuelEventTypes.ATTACK_RELEASED)
	runner.push(PlayerCommand.create(state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(state.tick))
	assert_eq(runner.count(DuelEventTypes.ATTACK_RELEASED), released + 1, "the winner still answers on the last tick of the result")
	assert_eq(state.phase, MatchPhase.Id.ROUND_INTRO, "and the next tick is the next intro")
	assert_false(DuelSimulation.accepts_gameplay_input(state, 0), "where control stops, exactly")


## Late in the decided round the winner can still dash, charge and swing, and
## walking off the edge keeps the result.
func test_the_winner_can_dash_charge_swing_and_walk_off_late() -> void:
	var runner := _runner()
	var rules := runner.simulation.rules
	_decide_on_time(runner)
	var state := runner.state
	runner.idle(rules.post_round_free_ticks + rules.result_ticks - 40)
	assert_eq(state.phase, MatchPhase.Id.ROUND_RESULT, "fixture: deep in the result")
	runner.push(PlayerCommand.create(state.tick, 0.0, 1.0, false, false, false, true), PlayerCommand.idle(state.tick))
	assert_true(state.fighter(0).gesture.is_bursting(), "a dash launches")
	runner.idle(20)
	runner.push(PlayerCommand.create(state.tick, 0.0, 0.0, true, false), PlayerCommand.idle(state.tick))
	runner.idle(rules.combatant(0).weapon.tap_threshold_ticks + 4)
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.CHARGING, "a held press charges")
	runner.push(PlayerCommand.create(state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(state.tick))
	runner.idle(1)
	assert_true(runner.count(DuelEventTypes.ATTACK_RELEASED) >= 1, "and the release swings")
	var walker := _runner()
	_decide_on_time(walker)
	var w := walker.state.fighter(0)
	var scores := walker.state.scores.duplicate()
	## Footwork is duel-relative: with the loser at the centre, backing away
	## from them walks the winner out over the rim.
	DuelFixture.place(walker.state.fighter(1), 0.0, 0.0, 0.0)
	DuelFixture.place(w, rules.platform_radius - 0.3, 0.0, PI)
	for _i in 90:
		if w.is_falling:
			break
		walker.push(PlayerCommand.create(walker.state.tick, 0.0, -1.0), PlayerCommand.idle(walker.state.tick))
	assert_true(w.is_falling, "fixture: the winner walked off the edge")
	assert_eq(walker.count(DuelEventTypes.POST_ROUND_FALL), 1, "a celebration fall")
	assert_eq(walker.state.scores, scores, "keeps the score")
	assert_eq(walker.state.round_winner, 0, "and the round")
	assert_false(DuelSimulation.accepts_gameplay_input(walker.state, 0), "and a falling winner has nothing left to control")


## The set's deciding round keeps the winner in control until the match ends.
func test_the_deciding_round_keeps_control_until_the_match_ends() -> void:
	var runner := _runner()
	for _round in 2:
		_decide_round(runner, 1)
	_decide_on_time(runner)
	var state := runner.state
	var rules := runner.simulation.rules
	assert_eq(SnapshotProjector.project(state, rules).set_winner, 0, "fixture: this round decides the set")
	runner.idle(rules.post_round_free_ticks + rules.result_ticks - 1)
	assert_false(state.is_finished(), "fixture: the match has one tick left")
	assert_true(DuelSimulation.accepts_gameplay_input(state, 0), "the winner still has control")
	runner.idle(1)
	assert_true(state.is_finished(), "then the match ends")
	assert_false(DuelSimulation.accepts_gameplay_input(state, 0), "and control with it")


func test_best_of_five_ends_at_three() -> void:
	var runner := _runner()
	for _round in 3:
		_decide_round(runner, 1)
	assert_true(runner.state.is_finished(), "match over")
	assert_eq(runner.state.match_winner, 0, "fighter 0 wins the match")
	assert_eq(runner.state.scores, PackedInt32Array([3, 0]), "3–0")
	assert_eq(runner.count(DuelEventTypes.MATCH_ENDED), 1, "one match end")


func test_round_limit_ends_a_tied_match_as_a_draw() -> void:
	var rules := DuelFixture.rules()
	rules.rounds_to_win = 2
	rules.max_rounds = 3
	var runner := _runner(rules)
	for _round in 3:
		_decide_round(runner, -1)
	assert_true(runner.state.is_finished(), "round limit ends the match")
	assert_eq(runner.state.match_winner, MatchPhase.DRAW, "tied match is a draw")
	assert_eq(runner.first(DuelEventTypes.MATCH_ENDED).text(DuelEventKeys.REASON), String(MatchPhase.REASON_ROUND_LIMIT), "round limit reason")


func test_next_round_resets_canonical_state() -> void:
	var runner := _runner()
	runner.skip_intro()
	var a := runner.state.fighter(0)
	a.x = 1.0
	a.weapon.angle = 1.0
	_decide_round(runner, 1)
	assert_eq(runner.state.round_number, 2, "second round")
	assert_eq(runner.state.phase, MatchPhase.Id.ROUND_INTRO, "back to the intro")
	assert_eq(a.x, 0.0, "back on the centre line")
	assert_eq(a.y, DuelSide.spawn_y(a.side, runner.simulation.rules.spawn_offset), "at its own end of the arena")
	assert_eq(a.health, runner.simulation.rules.combatant(0).fighter.max_health, "full health")
	assert_eq(a.weapon.angle, -runner.simulation.rules.combatant(0).weapon.guard_angle, "canonical guard")


func test_a_finished_match_is_inert() -> void:
	var runner := _runner()
	for _round in 3:
		_decide_round(runner, 0)
	var tick := runner.state.tick
	var after := runner.simulation.step(runner.state, PlayerCommand.idle(tick), PlayerCommand.idle(tick))
	assert_eq(after.size(), 0, "no events after the end")
	assert_eq(runner.state.tick, tick, "the clock stops")


func test_invalid_rules_fail_closed() -> void:
	assert_true(DuelSimulation.create(DuelRules.new()) == null, "neutral rules cannot start a duel")
	assert_true(DuelSimulation.create(null) == null, "missing rules cannot start a duel")
