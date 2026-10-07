extends TestCase

## FUZZ: generated command streams, checked against properties rather than
## expected values.
##
## The suites around this one script a scenario and assert what should happen
## in it. That proves the cases someone thought of. This one generates input a
## person might plausibly produce — jittery taps, held keys, rolled thumbs,
## attacks landing on top of footwork — and asserts the laws that must hold
## for *every* stream.
##
## The oracles here are written from the rules, not from the recognizer: each
## one re-reads the generated intent history and checks a necessary condition
## of the burst it observed. None of them reimplements the state machine,
## which is the point — a reimplementation would agree with a bug.
##
## Implements: /spec/invariants.md#move-002
## Implements: /spec/invariants.md#combat-006
## See also: /docs/reference/testing.md

## Long enough for gestures, holds, and expiries to interleave many times
## without making the suite a stress test.
const STREAM_TICKS := 600

var _rules: DuelRules


func _init() -> void:
	suite_name = "FUZZ"
	_rules = DuelFixture.rules()


# ── Stream generation ──────────────────────────────────────────────────────


## One generated intent stream, as the quantized axes a command would carry.
## Kept alongside the attack edges so a single record describes the whole tick.
class Stream:
	extends RefCounted

	var x: PackedFloat64Array = PackedFloat64Array()
	var y: PackedFloat64Array = PackedFloat64Array()
	var pressed: PackedInt32Array = PackedInt32Array()
	var released: PackedInt32Array = PackedInt32Array()

	func size() -> int:
		return x.size()

	func at(index: int, tick: int) -> PlayerCommand:
		return PlayerCommand.create(tick, x[index], y[index], pressed[index] == 1, released[index] == 1)

	## Magnitude of the intent held on `index`, in the same quantized form the
	## simulation reads.
	func deflection(index: int) -> float:
		var quantized := PlayerCommand.create(0, x[index], y[index])
		return SimMath.length(quantized.axis_x(), quantized.axis_y())

	## Mirror every lateral intent. Forward and back are untouched, so a
	## mirrored stream asks for exactly the same gestures in the opposite
	## lateral direction — which must earn exactly the same bursts.
	func mirrored() -> Stream:
		var flipped := Stream.new()
		for i in size():
			flipped.x.append(-x[i])
		flipped.y = y.duplicate()
		flipped.pressed = pressed.duplicate()
		flipped.released = released.duplicate()
		return flipped


## Build a stream out of plausible player behaviour rather than white noise:
## uniform random axes almost never produce a double tap, so a fuzzer made of
## them would exercise the one path nobody worries about.
func _generate(seed_value: int, stream_id: int) -> Stream:
	var rng := SeededRng.create(seed_value, stream_id)
	var stream := Stream.new()
	var held := false
	while stream.size() < STREAM_TICKS:
		var move := rng.next_int(0, 8)
		var sector := rng.next_int(0, 3)
		var sx := PackedFloat64Array([0.0, 0.0, 1.0, -1.0])[sector]
		var sy := PackedFloat64Array([1.0, -1.0, 0.0, 0.0])[sector]
		match move:
			0:
				_emit(stream, rng, 0.0, 0.0, rng.next_int(1, 20), held)
			1:
				## A single tap, inside the window. On its own it earns
				## nothing; it is what a stray press looks like.
				_emit(stream, rng, sx, sy, rng.next_int(1, 4), held)
			2, 3:
				## A deliberate double tap, which is the gesture the whole
				## mechanic exists for. Weighted heavily on purpose: a fuzzer
				## made of uniform noise essentially never produces one, and
				## would then be exercising only the paths nobody worries
				## about.
				_emit(stream, rng, sx, sy, rng.next_int(1, 3), held)
				_emit(stream, rng, 0.0, 0.0, rng.next_int(1, 4), held)
				_emit(stream, rng, sx, sy, rng.next_int(1, 3), held)
			4:
				## The same shape but too slow to count.
				_emit(stream, rng, sx, sy, rng.next_int(1, 3), held)
				_emit(stream, rng, 0.0, 0.0, _rules.fighter.double_tap_window_ticks + rng.next_int(1, 6), held)
				_emit(stream, rng, sx, sy, rng.next_int(1, 3), held)
			5:
				## A hold: long enough to be a walk rather than a tap.
				_emit(stream, rng, sx, sy, rng.next_int(10, 40), held)
			6:
				## A diagonal, which has to resolve to exactly one sector,
				## and a thumb hovering in the dead band, which must latch
				## nothing at all.
				_emit(stream, rng, rng.next_range(-1.0, 1.0), rng.next_range(-1.0, 1.0), rng.next_int(1, 6), held)
				var hover := 0.5 * (_rules.fighter.burst_neutral_deflection + _rules.fighter.burst_enter_deflection)
				_emit(stream, rng, sx * hover, sy * hover, rng.next_int(1, 8), held)
			_:
				## A roll around the stick: continuous steering that crosses
				## sectors without ever coming to rest.
				for _step in rng.next_int(4, 16):
					var angle := rng.next_range(-PI, PI)
					_emit(stream, rng, cos(angle), sin(angle), 1, held)
		held = stream.pressed[stream.size() - 1] == 1 or (held and stream.released[stream.size() - 1] != 1)
	return stream


## Append `ticks` of one intent, sprinkling attack edges through it. Attacks
## deliberately land on top of footwork: a press arriving on the same tick as
## a second tap is exactly the collision a player produces when they dash into
## a swing.
func _emit(stream: Stream, rng: SeededRng, x: float, y: float, ticks: int, held: bool) -> void:
	var holding := held
	for _i in ticks:
		var press := not holding and rng.next_float() < 0.1
		var release := holding and rng.next_float() < 0.2
		stream.x.append(x)
		stream.y.append(y)
		stream.pressed.append(1 if press else 0)
		stream.released.append(1 if release else 0)
		if press:
			holding = true
		elif release:
			holding = false


## Play two streams against each other and keep the tick each burst began on.
func _play(seed_value: int, left: Stream, right: Stream) -> SimRunner:
	var runner := SimRunner.create(_rules, seed_value)
	runner.skip_intro()
	var ticks := mini(left.size(), right.size())
	for i in ticks:
		if runner.state.is_finished():
			break
		var tick := runner.state.tick
		runner.push(left.at(i, tick), right.at(i, tick))
	return runner


## Ticks on which `slot` started a burst, as the simulation reported them.
func _burst_ticks(runner: SimRunner, slot: int) -> PackedInt32Array:
	var ticks := PackedInt32Array()
	for event in DuelFixture.of_type(runner.events, DuelEventTypes.BURST_STARTED):
		if event.actor == slot:
			ticks.append(event.tick)
	return ticks


func _burst_kinds(runner: SimRunner, slot: int) -> PackedInt32Array:
	var kinds := PackedInt32Array()
	for event in DuelFixture.of_type(runner.events, DuelEventTypes.BURST_STARTED):
		if event.actor == slot:
			kinds.append(int(event.number(DuelEventKeys.BURST)))
	return kinds


## Which burst a clear deflection is asking for, read straight off the stream.
## A deflection short of the entry threshold is asking for nothing — that gap
## is the hysteresis the recognizer relies on, so the oracle has to respect it
## too or it would claim gestures the player never made.
func _asked_for(stream: Stream, index: int) -> MovementGestureState.BurstKind:
	if index < 0 or stream.deflection(index) < _rules.fighter.burst_enter_deflection:
		return MovementGestureState.BurstKind.NONE
	var command := PlayerCommand.create(0, stream.x[index], stream.y[index])
	var ax := command.axis_x()
	var ay := command.axis_y()
	if absf(ay) >= absf(ax):
		return MovementGestureState.BurstKind.FORWARD_DASH if ay > 0.0 else MovementGestureState.BurstKind.BACK_DASH
	return MovementGestureState.BurstKind.RIGHT_STEP if ax > 0.0 else MovementGestureState.BurstKind.LEFT_STEP


# ── Gesture properties ────────────────────────────────────────────────────


## The headline property: a burst is a thing the player *asked for*. Every one
## of them must sit on a tick where the stick was clearly deflected, and must
## have a genuine rest behind it inside the window — because a double tap is
## two deliberate presses, not a stick that happened to pass through a sector.
func test_no_burst_is_manufactured_without_a_deliberate_gesture() -> void:
	var checked := 0
	for seed_value in PackedInt32Array([1, 2, 3, 5, 8]):
		var left := _generate(seed_value, 101)
		var right := _generate(seed_value, 211)
		var runner := _play(seed_value, left, right)
		var first := runner.state.tick - mini(left.size(), right.size())
		for slot in 2:
			var stream := left if slot == 0 else right
			for tick in _burst_ticks(runner, slot):
				var index := tick - first
				assert_true(
					stream.deflection(index) >= _rules.fighter.burst_enter_deflection,
					"seed %d slot %d burst on tick %d came from a clear deflection" % [seed_value, slot, tick]
				)
				assert_true(
					_rested_within_window(stream, index),
					"seed %d slot %d burst on tick %d had a real rest behind it" % [seed_value, slot, tick]
				)
				checked += 1
	assert_true(checked > 20, "precondition: the fuzzer actually produced bursts (%d)" % checked)


## True when the intent came to rest at some point inside the double-tap
## window ending at `index`. Read off the generated stream, independently of
## anything the recognizer remembers.
func _rested_within_window(stream: Stream, index: int) -> bool:
	var earliest := maxi(0, index - _rules.fighter.double_tap_window_ticks)
	for i in range(earliest, index):
		if stream.deflection(i) <= _rules.fighter.burst_rest_deflection:
			return true
	return false


## A held key repeats at the OS level and a thumb never sits perfectly still,
## so "the stick is deflected" must never be enough on its own. Two bursts can
## also never overlap: one gesture, one burst.
func test_bursts_never_repeat_from_a_held_intent() -> void:
	for seed_value in PackedInt32Array([4, 6, 7, 11]):
		var left := _generate(seed_value, 307)
		var right := _generate(seed_value, 401)
		var runner := _play(seed_value, left, right)
		var first := runner.state.tick - mini(left.size(), right.size())
		for slot in 2:
			var stream := left if slot == 0 else right
			var ticks := _burst_ticks(runner, slot)
			var kinds := _burst_kinds(runner, slot)
			var previous := -1
			for i in ticks.size():
				var tick := ticks[i]
				if previous >= 0:
					assert_true(
						tick - previous >= _rules.fighter.burst_ticks,
						"seed %d slot %d: bursts cannot overlap (%d then %d)" % [seed_value, slot, previous, tick]
					)
				previous = tick
				## The tick before a burst must not already have been asking
				## for that same burst, or the gesture was one continuous push
				## and the second tap was never a second press at all.
				var index := tick - first
				assert_true(
					int(_asked_for(stream, index - 1)) != kinds[i],
					"seed %d slot %d burst on tick %d is a rising edge, not a hold" % [seed_value, slot, tick]
				)


## No stream, however hostile, may drive the duel outside its physical bounds.
## This is the totality claim of COMBAT-006 read against generated input
## rather than scripted input.
func test_generated_streams_keep_the_duel_physical() -> void:
	for seed_value in PackedInt32Array([13, 17, 19]):
		var runner := _play(seed_value, _generate(seed_value, 503), _generate(seed_value, 601))
		assert_true(runner.is_sound(), "seed %d held every invariant: %s" % [seed_value, runner.violation_summary()])
		var touching := 2.0 * _rules.fighter.body_radius
		var limit := _rules.arena_radius - _rules.fighter.body_radius
		for slot in 2:
			var me := runner.state.fighter(slot)
			assert_finite(me.speed(), "seed %d slot %d has a finite speed" % [seed_value, slot])
			assert_true(me.speed() <= _rules.fighter.burst_speed_axial + 1e-6, "and never exceeds the burst ceiling")
			assert_true(SimMath.length(me.x, me.y) <= limit + 1e-6, "and stayed inside the arena")
		assert_true(
			DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1)) >= touching - 1e-6,
			"seed %d: and the bodies never merged" % seed_value
		)


## Neither lateral direction may be cheaper than the other. Mirroring the
## stream asks for the same gestures the other way round, so the gesture
## machine has to answer identically — a bias here would make one orbit
## direction mechanically better than the other.
func test_neither_lateral_direction_is_favoured() -> void:
	for seed_value in PackedInt32Array([23, 29, 31]):
		var stream := _generate(seed_value, 701)
		var idle := Stream.new()
		for _i in stream.size():
			idle.x.append(0.0)
			idle.y.append(0.0)
			idle.pressed.append(0)
			idle.released.append(0)
		var straight := _play(seed_value, stream, idle)
		var mirrored := _play(seed_value, stream.mirrored(), idle)
		var original := _burst_ticks(straight, 0)
		assert_true(original.size() > 0, "precondition: seed %d produced bursts" % seed_value)
		assert_eq(_burst_ticks(mirrored, 0), original, "seed %d earns the same bursts mirrored" % seed_value)


## MOVE-002 end to end: the gesture is a function of the command stream, so a
## generated stream has to reproduce bit for bit. If any part of the
## recognizer read the clock, the device, or the frame rate, this is where it
## would show.
func test_a_generated_duel_reproduces_exactly() -> void:
	var left := _generate(37, 809)
	var right := _generate(37, 907)
	var first := _play(37, left, right)
	var second := _play(37, left, right)
	assert_true(first.count(DuelEventTypes.BURST_STARTED) > 0, "precondition: the stream contains bursts")
	assert_true(first.count(DuelEventTypes.ATTACK_RELEASED) > 0, "and attacks")
	assert_eq(StateHasher.hash_state(second.state), StateHasher.hash_state(first.state), "two runs, one duel")
	first.seal()
	assert_eq(ReplayVerifier.verify(first.record, DuelFixture.rules()), ReplayVerifier.VERIFIED, "and the recorded stream verifies")


# ── Graceful handling ─────────────────────────────────────────────────────


## The graceful-handling matrix. Input and external problems are *absorbed* —
## clamped, ignored, or cancelled into a short recovery — because they come
## from outside the simulation and are not its fault. Impossible authoritative
## state is the opposite: it means the simulation itself is wrong, and there
## is no sound way to carry on from it (COMBAT-006).
func test_input_problems_are_absorbed_and_broken_state_is_not() -> void:
	var runner := SimRunner.create(_rules, 43)
	runner.skip_intro()
	## Out of range, non-finite, and self-contradictory input, all at once.
	var hostile := PlayerCommand.new()
	hostile.tick = runner.state.tick
	hostile.move_x = 999999
	hostile.move_y = -999999
	hostile.attack_pressed = true
	hostile.attack_released = true
	hostile.attack_cancel = true
	runner.push(hostile, PlayerCommand.create(runner.state.tick, NAN, INF))
	runner.idle(20)
	assert_true(runner.is_sound(), "hostile input is clamped, not obeyed: %s" % runner.violation_summary())
	assert_false(runner.state.is_finished(), "and the match carries on")
	for slot in 2:
		assert_finite(runner.state.fighter(slot).speed(), "slot %d is still physical" % slot)

	## A duplicate edge is idempotent: pressing a button that is already held
	## is not a second attack.
	var doubled := SimRunner.create(_rules, 43)
	doubled.skip_intro()
	var tick := doubled.state.tick
	doubled.push(PlayerCommand.create(tick, 0.0, 0.0, true), PlayerCommand.idle(tick))
	var started := doubled.count(DuelEventTypes.ATTACK_STARTED)
	doubled.push(PlayerCommand.create(doubled.state.tick, 0.0, 0.0, true), PlayerCommand.idle(doubled.state.tick))
	assert_eq(doubled.count(DuelEventTypes.ATTACK_STARTED), started, "a stale press is ignored")

	## Cancellation drops a charge without swinging — the correct answer to a
	## lost window or a lifted thumb, and never an accidental attack.
	var canceled := SimRunner.create(_rules, 43)
	canceled.skip_intro()
	canceled.push(PlayerCommand.create(canceled.state.tick, 0.0, 0.0, true), PlayerCommand.idle(canceled.state.tick))
	canceled.idle(_rules.weapon.tap_threshold_ticks + 4)
	assert_eq(canceled.state.fighter(0).weapon.phase, CombatPhase.Id.CHARGING, "precondition: a charge is under way")
	canceled.push(PlayerCommand.create(canceled.state.tick, 0.0, 0.0, false, false, true), PlayerCommand.idle(canceled.state.tick))
	assert_eq(canceled.count(DuelEventTypes.ATTACK_CANCELED), 1, "the charge is cancelled")
	assert_eq(canceled.count(DuelEventTypes.ATTACK_RELEASED), 0, "with no swing")

	## And the other half of the matrix: a genuinely impossible state is not
	## absorbed. It ends the match as a no-contest rather than being repaired.
	var broken := SimRunner.create(_rules, 43)
	broken.skip_intro()
	broken.state.fighter(0).vx = INF
	broken.push(PlayerCommand.idle(broken.state.tick), PlayerCommand.idle(broken.state.tick))
	assert_eq(broken.count(DuelEventTypes.SIMULATION_FAULT), 1, "impossible state fails closed")
	assert_eq(broken.state.end_reason, MatchPhase.REASON_NO_CONTEST, "as a no-contest")
