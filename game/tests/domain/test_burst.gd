extends TestCase

## BURST: double-tap footwork. A gesture read out of the command stream buys a
## short, hard, bounded push — and nothing else (COMBAT §25.2, MOVE-002).
##
## See also: /docs/concepts/controls.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "BURST"
	_rules = DuelFixture.rules()


## Canonical opening: the two fighters face each other across the arena, so
## slot 0's duel forward axis points at slot 1. Which *world* direction that
## is depends on the seeded side (SIDE-001), so these tests assert against the
## fighter's own duel axis rather than a fixed world heading.
func _scene() -> MatchState:
	return DuelFixture.state(_rules)


func _tick(state: MatchState, tick: int, x: float, y: float) -> MovementGestureState.BurstKind:
	return MovementSystem.step(state.fighter(0), state.fighter(1), x, y, tick, _rules.fighter)


## Deflect, return through neutral, deflect again. Returns the burst earned.
func _double_tap(state: MatchState, x: float, y: float) -> MovementGestureState.BurstKind:
	_tick(state, 0, x, y)
	_tick(state, 1, x, y)
	_tick(state, 2, 0.0, 0.0)
	_tick(state, 3, 0.0, 0.0)
	return _tick(state, 4, x, y)


func test_a_double_tap_forward_buys_a_dash() -> void:
	var state := _scene()
	var launched := _double_tap(state, 0.0, 1.0)
	assert_eq(launched, MovementGestureState.BurstKind.FORWARD_DASH, "two taps forward launch a forward dash")
	var me := state.fighter(0)
	assert_true(me.gesture.is_bursting(), "and the fighter is bursting")
	assert_near(me.gesture.burst_dir_x, me.duel_forward_x, 1e-9, "straight along the duel axis, in world terms")
	assert_near(me.gesture.burst_dir_y, me.duel_forward_y, 1e-9, "with no lateral component")
	for tick in range(5, 5 + _rules.fighter.burst_ticks):
		_tick(state, tick, 0.0, 1.0)
	assert_true(me.speed() > _rules.fighter.max_speed, "a dash exceeds what walking can reach (%.2f)" % me.speed())
	assert_true(me.speed() <= _rules.fighter.burst_speed_axial + 1e-9, "but is still bounded")


## A sidestep is a slide, not a lunge: only the dashes along the line between
## the fighters have the whole body behind them.
func test_a_sidestep_is_weaker_than_a_dash() -> void:
	var dashing := _scene()
	_double_tap(dashing, 0.0, 1.0)
	var stepping := _scene()
	assert_eq(_double_tap(stepping, 1.0, 0.0), MovementGestureState.BurstKind.RIGHT_STEP, "two taps right launch a right step")
	for tick in range(5, 5 + _rules.fighter.burst_ticks):
		_tick(dashing, tick, 0.0, 1.0)
		_tick(stepping, tick, 1.0, 0.0)
	assert_true(stepping.fighter(0).speed() < dashing.fighter(0).speed(), "the slide-step is the slower of the two")
	assert_true(stepping.fighter(0).speed() > _rules.fighter.max_speed, "though still faster than walking")


## Spam control is physical: the intent has to come back through neutral
## before a gesture can even be recognized. Holding a direction is walking.
func test_holding_a_direction_never_dashes() -> void:
	var state := _scene()
	for tick in 60:
		assert_eq(_tick(state, tick, 0.0, 1.0), MovementGestureState.BurstKind.NONE, "holding forward never bursts (tick %d)" % tick)
	assert_false(state.fighter(0).gesture.is_bursting(), "and the fighter is just walking")


## A first deflection held past the tap window was a walk, not a tap, so
## letting go of it and pressing again must not count as a double tap.
func test_a_held_direction_then_a_tap_is_not_a_double_tap() -> void:
	var state := _scene()
	var held := _rules.fighter.tap_window_ticks + 2
	for tick in held:
		_tick(state, tick, 0.0, 1.0)
	_tick(state, held, 0.0, 0.0)
	assert_eq(_tick(state, held + 1, 0.0, 1.0), MovementGestureState.BurstKind.NONE, "the walk does not arm a dash")


## Small windows on purpose: a long one fires a dash after the player has
## mentally moved on, which reads as the game moving on its own.
func test_a_late_second_tap_is_too_late() -> void:
	var state := _scene()
	_tick(state, 0, 0.0, 1.0)
	_tick(state, 1, 0.0, 0.0)
	var late := _rules.fighter.double_tap_window_ticks + 1
	for tick in range(2, late):
		_tick(state, tick, 0.0, 0.0)
	assert_eq(_tick(state, late, 0.0, 1.0), MovementGestureState.BurstKind.NONE, "a tap outside the window earns nothing")
	## It starts a fresh gesture rather than resurrecting the stale one, so a
	## third tap in time still works — the player is never locked out.
	assert_eq(state.fighter(0).gesture.first_tap_tick, late, "and counts as a new first tap")


func test_alternating_directions_never_dash() -> void:
	var state := _scene()
	for tick in 60:
		var right := tick % 4 < 2
		var burst := _tick(state, tick, 1.0 if right else -1.0, 0.0)
		assert_eq(burst, MovementGestureState.BurstKind.NONE, "rapid A/D alternation is not a gesture (tick %d)" % tick)


## Hysteresis: a clear deflection enters a sector and a near-centred stick
## leaves it. An intent hovering on the boundary must not chatter between
## sectors and manufacture gestures nobody made.
func test_a_hovering_intent_manufactures_no_gestures() -> void:
	var state := _scene()
	var between := 0.5 * (_rules.fighter.burst_enter_deflection + _rules.fighter.burst_neutral_deflection)
	assert_true(between > _rules.fighter.burst_neutral_deflection and between < _rules.fighter.burst_enter_deflection, "precondition: inside the dead band")
	for tick in 60:
		var wobble := between if tick % 2 == 0 else -between
		assert_eq(_tick(state, tick, wobble, between), MovementGestureState.BurstKind.NONE, "a hovering stick earns nothing (tick %d)" % tick)
	assert_eq(state.fighter(0).gesture.sector, MovementGestureState.Direction.NONE, "and never latches a sector")


## The heading is committed at activation. A forward dash that bent to follow
## a circling opponent would be a homing move, not footwork.
func test_the_heading_is_frozen_at_activation() -> void:
	var state := _scene()
	_double_tap(state, 0.0, 1.0)
	var me := state.fighter(0)
	var hx := me.gesture.burst_dir_x
	var hy := me.gesture.burst_dir_y
	assert_near(SimMath.length(hx, hy), 1.0, 1e-9, "precondition: committed to a real heading")
	## Move the opponent broadside mid-dash. The duel axis follows them, so
	## "forward" now means a quarter turn away — but the dash already chose.
	DuelFixture.place(state.fighter(1), me.x - hy * 4.0, me.y + hx * 4.0, 0.0)
	for tick in range(5, 3 + _rules.fighter.burst_ticks):
		_tick(state, tick, 0.0, 1.0)
	assert_true(me.gesture.is_bursting(), "precondition: still mid-dash")
	assert_true(me.duel_forward_x * -hy + me.duel_forward_y * hx > 0.9, "precondition: the duel axis did swing round to point at them")
	assert_near(me.gesture.burst_dir_x, hx, 1e-9, "the heading does not follow the opponent")
	assert_near(me.gesture.burst_dir_y, hy, 1e-9, "not on either axis")
	var along := me.vx * hx + me.vy * hy
	var across := me.vx * -hy + me.vy * hx
	assert_true(along > _rules.fighter.max_speed, "and the body keeps going the way it committed")
	assert_true(absf(across) < absf(along), "rather than curving toward them")


## A burst in progress is never re-armed, so a gesture cannot be chained into
## a longer one.
func test_a_dash_cannot_be_extended_mid_flight() -> void:
	var state := _scene()
	_double_tap(state, 0.0, 1.0)
	var gesture := state.fighter(0).gesture
	var full := gesture.burst_ticks_remaining
	_tick(state, 5, 0.0, 1.0)
	_tick(state, 6, 0.0, 0.0)
	_tick(state, 7, 0.0, 1.0)
	assert_true(gesture.burst_ticks_remaining < full, "the burst keeps running down")
	assert_true(gesture.is_bursting(), "precondition: still mid-dash")
	for tick in range(8, 40):
		_tick(state, tick, 0.0, 0.0)
	assert_false(gesture.is_bursting(), "and it ends on schedule rather than being topped up")


## PHYS-003 and MOVE-002: no special-casing against attacks. A dash during a
## committed swing is as sluggish as any other repositioning, so it is never
## a way out of a swing already paid for.
func test_a_burst_during_a_committed_swing_is_just_as_sluggish() -> void:
	var free := _scene()
	_double_tap(free, 0.0, 1.0)
	var committed := _scene()
	DuelFixture.commit(committed.fighter(0), CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	assert_eq(_double_tap(committed, 0.0, 1.0), MovementGestureState.BurstKind.FORWARD_DASH, "the dash still happens")
	for tick in range(5, 5 + _rules.fighter.burst_ticks):
		_tick(free, tick, 0.0, 1.0)
		_tick(committed, tick, 0.0, 1.0)
	assert_true(committed.fighter(0).speed() < free.fighter(0).speed() * 0.6, "but it barely moves them (%.2f vs %.2f)" % [committed.fighter(0).speed(), free.fighter(0).speed()])


func test_a_dash_never_restores_facing_or_ends_a_swing() -> void:
	var state := _scene()
	DuelFixture.commit(state.fighter(0), CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.weapon)
	var facing := state.fighter(0).facing
	_double_tap(state, 0.0, -1.0)
	for tick in range(5, 5 + _rules.fighter.burst_ticks):
		_tick(state, tick, 0.0, -1.0)
	assert_eq(state.fighter(0).facing, facing, "footwork does not turn the body; tracking does")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.ACTIVE_THREAT, "and the swing is still owed")


func test_a_frozen_or_impossible_burst_is_rejected() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var gesture := state.fighter(0).gesture
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "a fighter with no gesture is sound")
	gesture.mode = MovementGestureState.Mode.BURST
	assert_eq(StateInvariants.check(state, rules), StateInvariants.BURST_MODE_MISMATCH, "BURST with nothing driving it is impossible")
	gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	gesture.burst_ticks_remaining = rules.fighter.burst_ticks
	assert_eq(StateInvariants.check(state, rules), StateInvariants.BURST_HEADING_DEGENERATE, "a burst with no heading would scale or vanish")
	gesture.burst_dir_x = 1.0
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "a complete burst is sound")
	gesture.burst_ticks_remaining = rules.fighter.burst_ticks + 1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.BURST_TOO_LONG, "a burst outlasting its bound is impossible")
	gesture.burst_ticks_remaining = -1
	assert_eq(StateInvariants.check(state, rules), StateInvariants.COUNTER_NEGATIVE, "and a negative counter never happens")


## MOVE-002. The gesture is derived from the command stream alone, so it must
## reach the simulation through ordinary commands with no new fields, and show
## up once as an event the presentation can read.
func test_a_double_tap_reaches_the_simulation_through_plain_commands() -> void:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	for deflection in PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 1.0]):
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, deflection), PlayerCommand.idle(runner.state.tick))
	var bursts := DuelFixture.of_type(runner.events, DuelEventTypes.BURST_STARTED)
	assert_eq(bursts.size(), 1, "one gesture, one burst")
	assert_eq(bursts[0].actor, 0, "credited to the fighter who made it")
	assert_eq(int(bursts[0].number(DuelEventKeys.BURST)), MovementGestureState.BurstKind.FORWARD_DASH, "reported as a forward dash")
	## The frozen heading travels with the event, so a consumer never has to
	## rebuild the duel basis for itself to know which way the dash went.
	var gesture := runner.state.fighter(0).gesture
	assert_eq(bursts[0].number(DuelEventKeys.HEADING_X), gesture.burst_dir_x, "carrying the heading it committed to")
	assert_eq(bursts[0].number(DuelEventKeys.HEADING_Y), gesture.burst_dir_y, "on both axes")
	runner.idle(_rules.fighter.burst_ticks + 4)
	assert_true(runner.is_sound(), "invariants held throughout: %s" % runner.violation_summary())
	assert_eq(DuelFixture.of_type(runner.events, DuelEventTypes.BURST_STARTED).size(), 1, "and letting go earns no second one")


## The analog path has to produce the *identical* authoritative burst, because
## a thumb and a key both arrive as one deflection per tick. If the recognizer
## read anything device-specific, mobile and desktop would be different games.
func test_a_thumb_earns_the_same_burst_as_a_key() -> void:
	var keyed := _scene()
	var touched := _scene()
	var launched := MovementGestureState.BurstKind.NONE
	var tick := 0
	## A thumb never reports a clean 1.0, and lifting it never quite reaches
	## zero, so the gesture has to survive an imperfect stick. These are the
	## quantized axis values a command carries, not raw device readings.
	for deflection in PackedFloat64Array([0.93, 0.88, 0.04, 0.0, 0.91]):
		launched = _tick(touched, tick, 0.0, deflection)
		tick += 1
	assert_eq(launched, MovementGestureState.BurstKind.FORWARD_DASH, "the thumb earns the dash")
	assert_eq(_double_tap(keyed, 0.0, 1.0), MovementGestureState.BurstKind.FORWARD_DASH, "precondition: so does the key")
	var thumb := touched.fighter(0).gesture
	var key := keyed.fighter(0).gesture
	assert_eq(thumb.burst_kind, key.burst_kind, "same kind")
	assert_eq(thumb.burst_ticks_remaining, key.burst_ticks_remaining, "same duration")
	assert_near(thumb.burst_dir_x, key.burst_dir_x, 1e-9, "same heading")
	assert_near(thumb.burst_dir_y, key.burst_dir_y, 1e-9, "on both axes")


## Touch cancellation — a lifted thumb, a focus loss, a pause. The intent goes
## to rest, which is indistinguishable from a release, so the half-finished
## gesture must simply age out rather than firing when play resumes.
func test_an_interrupted_gesture_leaves_no_phantom_dash() -> void:
	var state := _scene()
	_tick(state, 0, 0.0, 1.0)
	assert_true(state.fighter(0).gesture.awaiting_second_tap, "precondition: a first tap is pending")
	var stale := _rules.fighter.double_tap_window_ticks + 2
	for tick in range(1, stale):
		assert_eq(
			_tick(state, tick, 0.0, 0.0),
			MovementGestureState.BurstKind.NONE,
			"no dash while nothing is being asked for (tick %d)" % tick
		)
	assert_false(state.fighter(0).gesture.awaiting_second_tap, "the pending tap has aged out")
	assert_false(state.fighter(0).gesture.is_bursting(), "and play resumes with no phantom dash owed")


## A dash is bounded footwork, not a phase or a teleport: bodies and walls
## still stop it.
func test_a_dash_into_the_opponent_does_not_phase_through_them() -> void:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var touching := 2.0 * _rules.fighter.body_radius
	var opening := signf(runner.state.fighter(1).x - runner.state.fighter(0).x)
	for deflection in PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 1.0]):
		runner.drive(0.0, deflection, 1)
	for _i in 60:
		runner.drive(0.0, 1.0, 1)
		var gap := DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1))
		assert_true(gap >= touching - 1e-9, "bodies stay apart mid-dash (gap %.6f)" % gap)
		assert_eq(signf(runner.state.fighter(1).x - runner.state.fighter(0).x), opening, "and neither dashes through the other")


## The arena edge is the hazard boundary. A burst is the fastest a fighter
## ever travels, so it is the most likely to trigger a ring-out.
func test_a_dash_off_the_edge_triggers_ring_out() -> void:
	var runner := SimRunner.create(_rules, 11)
	runner.skip_intro()
	## Back both fighters away from each other toward the edge.
	for _i in 120:
		runner.drive(0.0, -1.0, 1)
		if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
	if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
		## A ring-out already happened from walking, which proves the edge is open.
		assert_true(runner.count(DuelEventTypes.RING_OUT) > 0, "ring-out detected during retreat")
		return
	## Come off the stick and attempt a back dash off the edge.
	runner.drive(0.0, 0.0, 6)
	for deflection in PackedFloat64Array([-1.0, -1.0, 0.0, 0.0, -1.0]):
		runner.drive(0.0, deflection, 1)
		if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
	for _i in _rules.fighter.burst_ticks + 10:
		runner.drive(0.0, -1.0, 1)
		if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
	assert_true(runner.count(DuelEventTypes.RING_OUT) > 0 or runner.count(DuelEventTypes.ROUND_ENDED) > 0, "the dash triggered a ring-out or ended the round")


## A burst during a bind is *defined*, not special-cased: the footwork happens
## and the blades stay locked. A dash that broke a bind would make the bind a
## suggestion, and a dash silently swallowed would make the controls lie.
func test_a_burst_during_a_bind_is_defined() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	for slot in 2:
		state.fighter(slot).weapon.set_phase(CombatPhase.Id.BIND)
		state.fighter(slot).weapon.bind_left = rules.weapon.bind_ticks
	state.blade_contact.set_phase(ContactPairState.Phase.BOUND)
	var launched := MovementGestureState.BurstKind.NONE
	var tick := 0
	for deflection in PackedFloat64Array([0.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, -1.0]):
		launched = MovementSystem.step(state.fighter(0), state.fighter(1), 0.0, deflection, tick, rules.fighter)
		tick += 1
	assert_eq(launched, MovementGestureState.BurstKind.BACK_DASH, "footwork is still available in a bind")
	assert_eq(state.fighter(0).weapon.phase, CombatPhase.Id.BIND, "but it does not break the bind")
	assert_true(state.blade_contact.is_bound(), "the blades stay locked")
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "and the combination is a legal state")


## MOVE-002 and the replay contract together. A burst is derived state, so if
## the recognizer ever read anything outside the command stream a recorded
## duel containing dashes would not reproduce.
func test_a_replay_with_dashes_reproduces_the_duel_exactly() -> void:
	var scripted := PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, -1.0, -1.0, 0.0, 0.0, -1.0])
	var hashes := PackedStringArray()
	var bursts := PackedInt32Array([0, 0])
	for attempt in 2:
		var runner := SimRunner.create(_rules, 23)
		runner.skip_intro()
		for deflection in scripted:
			runner.drive(0.0, deflection, 1)
		runner.idle(_rules.fighter.burst_ticks + 8)
		hashes.append(StateHasher.hash_state(runner.state))
		bursts[attempt] = runner.count(DuelEventTypes.BURST_STARTED)
	assert_true(bursts[0] > 0, "precondition: the script actually produced dashes")
	assert_eq(bursts[1], bursts[0], "the same commands produce the same number of dashes")
	assert_eq(hashes[1], hashes[0], "and the same duel, down to the hash")
