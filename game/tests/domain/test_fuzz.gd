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
				_emit(stream, rng, 0.0, 0.0, _rules.combatant(0).fighter.double_tap_window_ticks + rng.next_int(1, 6), held)
				_emit(stream, rng, sx, sy, rng.next_int(1, 3), held)
			5:
				## A hold: long enough to be a walk rather than a tap.
				_emit(stream, rng, sx, sy, rng.next_int(10, 40), held)
			6:
				## A diagonal, which has to resolve to exactly one sector,
				## and a thumb hovering in the dead band, which must latch
				## nothing at all.
				_emit(stream, rng, rng.next_range(-1.0, 1.0), rng.next_range(-1.0, 1.0), rng.next_int(1, 6), held)
				var hover := 0.5 * (_rules.combatant(0).fighter.burst_neutral_deflection + _rules.combatant(0).fighter.burst_enter_deflection)
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


## Ticks before `before` on which `slot` started a burst, as the simulation
## reported them.
func _burst_ticks(runner: SimRunner, slot: int, before: int = 1 << 30) -> PackedInt32Array:
	var ticks := PackedInt32Array()
	for event in DuelFixture.of_type(runner.events, DuelEventTypes.BURST_STARTED):
		if event.actor == slot and event.tick < before:
			ticks.append(event.tick)
	return ticks


## The tick the first round ended, or past the end of the run.
func _first_round_end(runner: SimRunner) -> int:
	var ended := DuelFixture.of_type(runner.events, DuelEventTypes.ROUND_ENDED)
	return ended[0].tick if not ended.is_empty() else runner.state.tick + 1


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
	if index < 0 or stream.deflection(index) < _rules.combatant(0).fighter.burst_enter_deflection:
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
					stream.deflection(index) >= _rules.combatant(0).fighter.burst_enter_deflection,
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
	var earliest := maxi(0, index - _rules.combatant(0).fighter.double_tap_window_ticks)
	for i in range(earliest, index):
		if stream.deflection(i) <= _rules.combatant(0).fighter.burst_rest_deflection:
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
						tick - previous >= _rules.combatant(0).fighter.burst_ticks,
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
		var touching := 2.0 * _rules.combatant(0).fighter.push_radius
		## The arena is open: a centre past the platform edge is a ring-out, so
		## a living fighter still standing has its centre on the platform.
		var limit := _rules.platform_radius
		for slot in 2:
			var me := runner.state.fighter(slot)
			assert_finite(me.speed(), "seed %d slot %d has a finite speed" % [seed_value, slot])
			assert_true(me.speed() <= _rules.combatant(0).fighter.burst_speed_axial + 1e-6, "and never exceeds the burst ceiling")
			assert_true(SimMath.length(me.x, me.y) <= limit + 1e-6 or me.is_falling or not me.is_alive(), "and stayed on the platform or fell/died (%.3f m from centre)" % SimMath.length(me.x, me.y))
		assert_true(
			DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1)) >= touching - 1e-6,
			"seed %d: and the bodies never merged" % seed_value
		)


## SIM symmetry. The whole opening is mirrored — positions, velocities,
## headings, weapon angles and rates, the latched side, and the commands —
## and that mirror has to hold for the stream. A between-round reset plants
## every fighter on their right; the mirror of that authored rest is the left
## side, so the mirror sim is re-seated there before the next round.
func test_a_mirrored_opening_stays_mirrored() -> void:
	for seed_value in PackedInt32Array([23, 29, 31]):
		var left := _generate(seed_value, 701)
		var right := _generate(seed_value, 809)
		var flipped_left := left.mirrored()
		var flipped_right := right.mirrored()
		var straight := SimRunner.create(_rules, seed_value)
		var mirrored := SimRunner.create(_rules, seed_value)
		for slot in 2:
			mirrored.state.fighter(slot).weapon.reset(_rules.combatant(0).weapon.guard_angle)
		straight.skip_intro()
		mirrored.skip_intro()
		_previous_gap = 0.0
		_stream_max_gap = 0.0
		if not _assert_mirror(straight, mirrored, seed_value):
			break
		var ticks := mini(left.size(), right.size())
		for i in ticks:
			if straight.state.is_finished():
				assert_true(mirrored.state.is_finished(), "seed %d: the mirror finishes on the same tick" % seed_value)
				break
			var tick := straight.state.tick
			assert_eq(mirrored.state.tick, tick, "seed %d: the mirror is on the same tick" % seed_value)
			straight.push(left.at(i, tick), right.at(i, tick))
			mirrored.push(flipped_left.at(i, tick), flipped_right.at(i, tick))
			_reseat_mirrored_rest(mirrored.state)
			if not _assert_mirror(straight, mirrored, seed_value):
				break
		assert_true(straight.is_sound() and mirrored.is_sound(), "seed %d held every invariant on both sides" % seed_value)
		## Part two of the oracle (the long horizon): over the whole fixed run the
		## largest and the final mirror error stay bounded. Not a consumable
		## allowance — a steady bias that never steps would still be caught here.
		assert_true(_stream_max_gap <= _MIRROR_CEILING, "seed %d: the largest mirror error over the run is bounded (%s)" % [seed_value, String.num_scientific(_stream_max_gap)])
		assert_true(_previous_gap <= _MIRROR_CEILING, "seed %d: and so is the final one (%s)" % [seed_value, String.num_scientific(_previous_gap)])


## The oracle tells a side from chaos: the same mirrored stream, with a
## micro-radian nudge to one side's weapon angle on one tick — far below the
## ceiling, and far above anything chaos grows in a tick — is caught on that
## tick, while the untouched stream up to it passes.
func test_the_mirror_oracle_catches_a_sudden_side() -> void:
	var seed_value := 23
	var left := _generate(seed_value, 701)
	var right := _generate(seed_value, 809)
	var flipped_left := left.mirrored()
	var flipped_right := right.mirrored()
	var straight := SimRunner.create(_rules, seed_value)
	var mirrored := SimRunner.create(_rules, seed_value)
	for slot in 2:
		mirrored.state.fighter(slot).weapon.reset(_rules.combatant(0).weapon.guard_angle)
	straight.skip_intro()
	mirrored.skip_intro()
	_previous_gap = 0.0
	var nudge_at := 120
	var clean := true
	var caught := ""
	for i in nudge_at + 1:
		var tick := straight.state.tick
		straight.push(left.at(i, tick), right.at(i, tick))
		mirrored.push(flipped_left.at(i, tick), flipped_right.at(i, tick))
		if i == nudge_at:
			mirrored.state.fighter(0).weapon.angle += 1.0e-7
			caught = _mirror_verdict(straight, mirrored)
		elif _mirror_verdict(straight, mirrored) != "":
			clean = false
	assert_true(clean, "fixture: the untouched stream is the mirror up to the nudge")
	assert_true(caught.contains("stepped"), "the nudge is caught as a side (%s)" % caught)


## Reflection through π is the symmetry. It is not a second SHA-256: negating
## +0 flips the sign bit, and `atan2` reduced on +x is not bit-identical to the
## same angle reduced on −x. SimMath promises trig within 1e-9. A favored side
## is a gap past that, on the whole stream, not a hash that stops at the first ulp.
##
## Mirror the physical result, not the solver's internal decomposition. The
## hard oracle is everything that is physics: positions and velocities, θ / θ̇,
## φ / φ̇, the contact geometry and its identity, and each contact's residual
## normal velocity after the solve — by the growth oracle below (relative once
## a quantity exceeds one). How a coupled, near-redundant two-row solve *splits* an impulse
## between its rows is numerically sensitive even when the motion it produces
## is identical, so the per-row `Jn` / `Jt` and the warm-start record are a
## diagnostic: printed when they disagree by more than 1e-7 relative, never a
## failure on their own. A real asymmetry moves the motion, and the motion is
## asserted.
##
## Two kinds of gap, told apart by how they grow. SimMath's 1e-9 trig error is
## the seed; a duel is chaotic, so through held multi-point contacts that seed
## compounds a few times per tick (measured: 1e-13 → 2e-9 over ~70 ticks of a
## four-row lock). A favoured side does not compound — it appears: the gap
## steps from the ulp floor to its own size in one tick. So the oracle is
## (1) no tick may grow the float gap more than `_MIRROR_STEP` times over the
## larger of the last tick's gap and `_MIRROR_FLOOR`, and (2) the gap never
## exceeds `_MIRROR_CEILING` (a micrometre on a metre, a microradian on a
## radian — far below anything a player or a hit could tell apart). Every
## discrete field — phases, counters, contact identity — must match exactly.
const _MIRROR_FLOOR := 1.0e-12
const _MIRROR_STEP := 1.0e3
const _MIRROR_CEILING := 1.0e-6

## The largest relative float gap the last `_mirror_diff` saw, and the
## previous tick's on the stream being checked (reset per stream).
var _gap: float = 0.0
var _previous_gap: float = 0.0
## The largest gap seen on the current stream (the long-horizon bound).
var _stream_max_gap: float = 0.0


func _assert_mirror(straight: SimRunner, mirrored: SimRunner, seed_value: int) -> bool:
	var verdict := _mirror_verdict(straight, mirrored)
	_stream_max_gap = maxf(_stream_max_gap, _gap)
	if verdict != "":
		assert_eq(verdict, "", "seed %d tick %d is the mirror of the opening" % [seed_value, straight.state.tick])
		return false
	_reflect(mirrored.state)
	var rows := _impulse_diff(straight.state, mirrored.state)
	_reflect(mirrored.state)
	if not rows.is_empty():
		print("      ~ FUZZ diagnostic, seed %d tick %d: row impulses split differently, motion mirrored\n%s" % [seed_value, straight.state.tick, rows])
	return true


## "" when `mirrored` is still `straight`'s reflection by the oracle above;
## else what broke it. Advances the stream's gap history.
func _mirror_verdict(straight: SimRunner, mirrored: SimRunner) -> String:
	_reflect(mirrored.state)
	_gap = 0.0
	var mismatch := _mirror_diff(straight.state, mirrored.state)
	_reflect(mirrored.state)
	var allowed := maxf(_previous_gap, _MIRROR_FLOOR) * _MIRROR_STEP
	var previous := _previous_gap
	_previous_gap = _gap
	if not mismatch.is_empty():
		return mismatch
	if _gap > allowed:
		return "the gap stepped from %s to %s in one tick — a side, not chaos" % [String.num_scientific(previous), String.num_scientific(_gap)]
	return ""


func _mirror_diff(straight: MatchState, reflected: MatchState) -> String:
	var lines: PackedStringArray = PackedStringArray()
	_diff_int(lines, "phase", straight.phase, reflected.phase)
	_diff_int(lines, "phase_ticks", straight.phase_ticks, reflected.phase_ticks)
	_diff_int(lines, "blade_phase", straight.blade_contact.phase, reflected.blade_contact.phase)
	_diff_int(lines, "blade_points", straight.blade_contact.point_count, reflected.blade_contact.point_count)
	_diff_float(lines, "blade_nx", straight.blade_contact.normal_x, reflected.blade_contact.normal_x)
	_diff_float(lines, "blade_ny", straight.blade_contact.normal_y, reflected.blade_contact.normal_y)
	var points := mini(straight.blade_contact.point_count, reflected.blade_contact.point_count)
	for point in points:
		var s := straight.blade_contact
		var r := reflected.blade_contact
		_diff_float(lines, "blade_px%d" % point, s.point_x[point], r.point_x[point])
		_diff_float(lines, "blade_py%d" % point, s.point_y[point], r.point_y[point])
		_diff_float(lines, "blade_pnx%d" % point, s.point_nx[point], r.point_nx[point])
		_diff_float(lines, "blade_pny%d" % point, s.point_ny[point], r.point_ny[point])
		_diff_float(lines, "blade_fa%d" % point, s.fraction_a[point], r.fraction_a[point])
		_diff_float(lines, "blade_fb%d" % point, s.fraction_b[point], r.fraction_b[point])
		_diff_int(lines, "blade_id%d" % point, s.contact_id[point], r.contact_id[point])
		_diff_int(lines, "blade_age%d" % point, s.age[point], r.age[point])
		_diff_float(lines, "blade_vn%d" % point, _residual(straight, point), _residual(reflected, point))
	for row in SwordContactSet.CAPACITY:
		_diff_int(lines, "hold_active%d" % row, straight.blade_contact.hold_active[row], reflected.blade_contact.hold_active[row])
		_diff_float(lines, "hold_fa%d" % row, straight.blade_contact.hold_fraction_a[row], reflected.blade_contact.hold_fraction_a[row])
		_diff_float(lines, "hold_fb%d" % row, straight.blade_contact.hold_fraction_b[row], reflected.blade_contact.hold_fraction_b[row])
	for slot in 2:
		_diff_int(lines, "body_hold%d" % slot, int(straight.weapon_body_contacts[slot].hold_active), int(reflected.weapon_body_contacts[slot].hold_active))
	_diff_float(lines, "body_nx", straight.body_contact.last_constraint_normal_x, reflected.body_contact.last_constraint_normal_x)
	_diff_float(lines, "body_ny", straight.body_contact.last_constraint_normal_y, reflected.body_contact.last_constraint_normal_y)
	for slot in 2:
		var a := straight.fighter(slot)
		var b := reflected.fighter(slot)
		var prefix := "s%d." % slot
		_diff_float(lines, prefix + "x", a.x, b.x)
		_diff_float(lines, prefix + "y", a.y, b.y)
		_diff_float(lines, prefix + "vx", a.vx, b.vx)
		_diff_float(lines, prefix + "vy", a.vy, b.vy)
		_diff_float(lines, prefix + "ax", a.ax, b.ax)
		_diff_float(lines, prefix + "ay", a.ay, b.ay)
		_diff_float(lines, prefix + "facing", a.facing, b.facing)
		_diff_float(lines, prefix + "turn", a.turn_rate, b.turn_rate)
		_diff_float(lines, prefix + "health", a.health, b.health)
		_diff_float(lines, prefix + "stability", a.stability, b.stability)
		_diff_float(lines, prefix + "lethal", a.lethal_fraction, b.lethal_fraction)
		_diff_float(lines, prefix + "support", a.support_lost_fraction, b.support_lost_fraction)
		_diff_float(lines, prefix + "fwd_x", a.duel_forward_x, b.duel_forward_x)
		_diff_float(lines, prefix + "fwd_y", a.duel_forward_y, b.duel_forward_y)
		_diff_float(lines, prefix + "burst_x", a.gesture.burst_dir_x, b.gesture.burst_dir_x)
		_diff_float(lines, prefix + "burst_y", a.gesture.burst_dir_y, b.gesture.burst_dir_y)
		_diff_float(lines, prefix + "theta", a.weapon.angle, b.weapon.angle)
		_diff_float(lines, prefix + "omega", a.weapon.speed, b.weapon.speed)
		_diff_float(lines, prefix + "charge", a.weapon.charge, b.weapon.charge)
		_diff_float(lines, prefix + "hold", a.weapon.hold_start_angle, b.weapon.hold_start_angle)
		_diff_float(lines, prefix + "windback", a.weapon.earned_windback, b.weapon.earned_windback)
		_diff_float(lines, prefix + "side", a.weapon.stable_side, b.weapon.stable_side)
		_diff_float(lines, prefix + "swing_dir", a.weapon.swing_dir, b.weapon.swing_dir)
		_diff_float(lines, prefix + "ready", a.weapon.launch_preparation, b.weapon.launch_preparation)
		_diff_float(lines, prefix + "swing_start", a.weapon.swing_start, b.weapon.swing_start)
		_diff_float(lines, prefix + "swing_end", a.weapon.swing_end, b.weapon.swing_end)
		_diff_float(lines, prefix + "swing_charge", a.weapon.swing_charge, b.weapon.swing_charge)
		_diff_float(lines, prefix + "commit", a.weapon.commitment, b.weapon.commitment)
		_diff_float(lines, prefix + "motor_torque", a.weapon.motor_torque, b.weapon.motor_torque)
		_diff_float(lines, prefix + "rec_commit", a.weapon.recovery_commitment, b.weapon.recovery_commitment)
		_diff_int(lines, prefix + "stagger", a.stagger_left, b.stagger_left)
		_diff_int(lines, prefix + "sector", a.gesture.sector, b.gesture.sector)
		_diff_int(lines, prefix + "sector_ticks", a.gesture.sector_ticks, b.gesture.sector_ticks)
		_diff_int(lines, prefix + "last_dir", a.gesture.last_direction, b.gesture.last_direction)
		_diff_int(lines, prefix + "tap", a.gesture.first_tap_tick, b.gesture.first_tap_tick)
		_diff_int(lines, prefix + "await", int(a.gesture.awaiting_second_tap), int(b.gesture.awaiting_second_tap))
		_diff_int(lines, prefix + "neutral", int(a.gesture.returned_to_neutral), int(b.gesture.returned_to_neutral))
		_diff_int(lines, prefix + "held", int(a.attack_held), int(b.attack_held))
		_diff_int(lines, prefix + "buf_rel", int(a.buffered_release), int(b.buffered_release))
		_diff_int(lines, prefix + "falling", int(a.is_falling), int(b.is_falling))
		_diff_int(lines, prefix + "fallen", int(a.fallen.active), int(b.fallen.active))
		_diff_int(lines, prefix + "settle", a.fallen.settle_left, b.fallen.settle_left)
		_diff_int(lines, prefix + "over_edge", int(a.fallen.over_edge), int(b.fallen.over_edge))
		_diff_float(lines, prefix + "fallen_yaw", 0.0, SimMath.wrap_angle(a.fallen.yaw - b.fallen.yaw))
		_diff_float(lines, prefix + "fallen_spin", a.fallen.spin, b.fallen.spin)
		_diff_int(lines, prefix + "attack_contacted", int(a.weapon.attack_contacted), int(b.weapon.attack_contacted))
		_diff_int(lines, prefix + "grip_struck", int(a.weapon.grip_struck), int(b.weapon.grip_struck))
		_diff_int(lines, prefix + "mode", a.gesture.mode, b.gesture.mode)
		_diff_int(lines, prefix + "burst", a.gesture.burst_kind, b.gesture.burst_kind)
		_diff_int(lines, prefix + "burst_left", a.gesture.burst_ticks_remaining, b.gesture.burst_ticks_remaining)
		_diff_int(lines, prefix + "rec_left", a.gesture.recovery_ticks_remaining, b.gesture.recovery_ticks_remaining)
		_diff_int(lines, prefix + "press", a.press_tick, b.press_tick)
		_diff_int(lines, prefix + "buf_press", a.buffered_press_tick, b.buffered_press_tick)
		_diff_int(lines, prefix + "wphase", a.weapon.phase, b.weapon.phase)
		_diff_int(lines, prefix + "wphase_ticks", a.weapon.phase_ticks, b.weapon.phase_ticks)
		_diff_int(lines, prefix + "rec_ticks", a.weapon.recovery_ticks, b.weapon.recovery_ticks)
		_diff_int(lines, prefix + "rec_left_w", a.weapon.recovery_left, b.weapon.recovery_left)
	return "\n".join(lines)


## The diagnostic band for a solve's internal decomposition: solved impulses
## are the output of a small linear solve, so the geometry's trig error reaches
## them through its conditioning (a two-point line contact beside a guard stop
## amplifies it a few hundred times).
const _MIRROR_IMPULSE_REL := 1.0e-7


## A contact's residual normal velocity after the tick (m/s, from blade b toward
## blade a; positive = still closing) — the physical outcome of its solve.
func _residual(state: MatchState, point: int) -> float:
	var a := state.fighter(0)
	var b := state.fighter(1)
	var contact := state.blade_contact
	var pose_a := WeaponKinematics.pose_of(a, _rules.combatant(0), BladePose.new())
	var pose_b := WeaponKinematics.pose_of(b, _rules.combatant(0), BladePose.new())
	return SwordContactSolver.closing_speed(a, b, pose_a, pose_b, contact.point_x[point], contact.point_y[point], contact.point_nx[point], contact.point_ny[point])


## The solver's row decomposition and warm-start record — diagnostic only.
func _impulse_diff(straight: MatchState, reflected: MatchState) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for point in mini(straight.blade_contact.point_count, reflected.blade_contact.point_count):
		_diff_impulse(lines, "blade_jn%d" % point, straight.blade_contact.normal_impulse[point], reflected.blade_contact.normal_impulse[point])
		_diff_impulse(lines, "blade_jt%d" % point, straight.blade_contact.tangent_impulse[point], reflected.blade_contact.tangent_impulse[point])
	for row in SwordContactSet.CAPACITY:
		_diff_impulse(lines, "hold_jn%d" % row, straight.blade_contact.hold_normal[row], reflected.blade_contact.hold_normal[row])
		_diff_impulse(lines, "hold_jt%d" % row, straight.blade_contact.hold_tangent[row], reflected.blade_contact.hold_tangent[row])
	for slot in 2:
		var held := straight.weapon_body_contacts[slot]
		var mirror := reflected.weapon_body_contacts[slot]
		_diff_impulse(lines, "body_hold_jn%d" % slot, held.hold_normal, mirror.hold_normal)
		_diff_impulse(lines, "body_hold_jt%d" % slot, held.hold_tangent, mirror.hold_tangent)
	_diff_impulse(lines, "body_jn", straight.body_contact.last_constraint_impulse, reflected.body_contact.last_constraint_impulse)
	return "\n".join(lines)


func _diff_impulse(lines: PackedStringArray, name: String, left: float, right: float) -> void:
	if left == right or absf(left - right) <= _MIRROR_IMPULSE_REL * maxf(1.0, maxf(absf(left), absf(right))):
		return
	lines.append("%s %s vs %s" % [name, str(left), str(right)])


func _diff_float(lines: PackedStringArray, name: String, left: float, right: float) -> void:
	if left == right:
		return
	var relative := absf(left - right) / maxf(1.0, maxf(absf(left), absf(right)))
	_gap = maxf(_gap, relative)
	if relative > _MIRROR_CEILING:
		lines.append("%s %s vs %s" % [name, str(left), str(right)])


func _diff_int(lines: PackedStringArray, name: String, left: int, right: int) -> void:
	if left != right:
		lines.append("%s %d vs %d" % [name, left, right])


func _reseat_mirrored_rest(state: MatchState) -> void:
	if state.phase != MatchPhase.Id.ROUND_INTRO or state.phase_ticks != 0:
		return
	for slot in 2:
		state.fighter(slot).weapon.reset(_rules.combatant(0).weapon.guard_angle)


func _reflect(state: MatchState) -> void:
	var blade := state.blade_contact
	blade.normal_x = -blade.normal_x
	for point in blade.point_x.size():
		blade.point_x[point] = -blade.point_x[point]
	## The tangent (−n_y, n_x) reverses under reflection, so every signed
	## tangent impulse does too.
	for point in SwordContactSet.CAPACITY:
		blade.tangent_impulse[point] = -blade.tangent_impulse[point]
		blade.hold_tangent[point] = -blade.hold_tangent[point]
		blade.point_nx[point] = -blade.point_nx[point]
	for lifecycle in state.weapon_body_contacts:
		lifecycle.tangent_impulse = -lifecycle.tangent_impulse
		lifecycle.hold_tangent = -lifecycle.hold_tangent
	state.body_contact.last_constraint_normal_x = -state.body_contact.last_constraint_normal_x
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.x = -fighter.x
		fighter.vx = -fighter.vx
		fighter.ax = -fighter.ax
		fighter.turn_rate = -fighter.turn_rate
		fighter.facing = SimMath.wrap_angle(PI - fighter.facing)
		fighter.duel_forward_x = -fighter.duel_forward_x
		var weapon := fighter.weapon
		weapon.angle = -weapon.angle
		weapon.speed = -weapon.speed
		weapon.motor_torque = -weapon.motor_torque
		weapon.stable_side = -weapon.stable_side
		weapon.swing_dir = -weapon.swing_dir
		weapon.swing_start = -weapon.swing_start
		weapon.swing_end = -weapon.swing_end
		weapon.hold_start_angle = -weapon.hold_start_angle
		var gesture := fighter.gesture
		gesture.burst_dir_x = -gesture.burst_dir_x
		gesture.sector = _swap_direction(gesture.sector) as MovementGestureState.Direction
		gesture.last_direction = _swap_direction(gesture.last_direction) as MovementGestureState.Direction
		gesture.burst_kind = _swap_burst(gesture.burst_kind) as MovementGestureState.BurstKind
		if fighter.fallen.active:
			fighter.fallen.yaw = SimMath.wrap_angle(PI - fighter.fallen.yaw)
			fighter.fallen.spin = -fighter.fallen.spin


func _swap_direction(direction: int) -> int:
	if direction == MovementGestureState.Direction.RIGHT:
		return MovementGestureState.Direction.LEFT
	if direction == MovementGestureState.Direction.LEFT:
		return MovementGestureState.Direction.RIGHT
	return direction


func _swap_burst(kind: int) -> int:
	if kind == MovementGestureState.BurstKind.RIGHT_STEP:
		return MovementGestureState.BurstKind.LEFT_STEP
	if kind == MovementGestureState.BurstKind.LEFT_STEP:
		return MovementGestureState.BurstKind.RIGHT_STEP
	return kind


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
## A contact can whip a blade away faster than the motor could ever swing it
## (a dash into the opponent's hilt). That is physics, not corruption: a blade
## knocked to 2.5× the motor's limit is a legal state, stays inside the
## physically valid bound, replays bit for bit, and the motor has it back
## under its own limit within a second. A spin no contact could produce — or
## a non-finite one — is still a fault.
func test_a_violent_knock_away_is_legal_bounded_and_recovers() -> void:
	var actuated := _rules.combatant(0).weapon.swing_speed_full
	var bound := SimulationGuardrails.physical_weapon_speed_bound(_rules.combatant(0), _rules.combatant(1))
	var knocked := actuated * 2.5
	assert_true(knocked < bound, "fixture: 2.5× the motor's limit is a speed a contact can legally give (%.1f < %.1f rad/s)" % [knocked, bound])
	var hashes: Array[String] = []
	for _replay in 2:
		var runner := SimRunner.create(_rules, 13)
		runner.skip_intro()
		runner.state.fighter(0).weapon.speed = knocked
		var settled := -1
		for i in 120:
			runner.idle(1)
			if settled < 0 and absf(runner.state.fighter(0).weapon.speed) <= actuated:
				settled = i
		assert_true(runner.is_sound(), "the knocked blade is a legal state: %s" % runner.violation_summary())
		assert_true(settled >= 0 and settled <= 60, "the motor has it back under its own limit within a second (%d ticks)" % settled)
		hashes.append(str(StateHasher.hash_state(runner.state)))
	assert_eq(hashes[0], hashes[1], "and it replays bit for bit")
	var broken := DuelFixture.state(_rules).fighter(0)
	broken.weapon.speed = bound * SimulationGuardrails.CAPACITY_SAFETY_FACTOR * 1.01
	assert_false(SimulationGuardrails.validate_capacity(broken, _rules), "a spin no contact could produce is corruption")
	broken.weapon.speed = NAN
	assert_eq(StateInvariants.check_fighter(broken, _rules), StateInvariants.WEAPON_NOT_FINITE, "and a non-finite one is named for what it is")
	broken.weapon.speed = actuated
	assert_true(SimulationGuardrails.validate_capacity(broken, _rules), "while a motor-speed blade is fine")


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
	canceled.idle(_rules.combatant(0).weapon.tap_threshold_ticks + 4)
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
