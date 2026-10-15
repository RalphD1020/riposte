class_name WeaponAttackPath
extends RefCounted

## The weapon's orbit (WEAPON-PATH-003, WEAPON-ORBIT-002): the old
## constant-radius hand circle, stretched forward near the centre so a fencer
## can actually hold the sword there. For every weapon angle θ, where the
## two-handed carriage — the grip centre — rides in the fighter's combat frame
## (forward along the combat heading, left a quarter turn counter-clockwise of
## it), and how fast it moves per radian of θ.
##
## That is all it says. θ itself is the blade's horizontal angle from the combat
## heading, by definition; the track never turns the blade, so the sword at θ
## is the carriage `C(θ)` plus a rigid blade at θ. One bounded angle, one
## single-valued pose: a right-origin cut (−135° → +45° at full charge) and a
## left-origin one (+135° → −45°) traverse the same track in opposite
## directions, overlapping through the centre.
##
## Authored as a few calibration samples on one side, named for the postures
## they read as — Long Guard on the centreline, Ready, the Gather toward the
## shoulder, the full Load — which are regions of the one θ, not separate
## paths; baked once into a compact lookup:
##
## - Shape-preserving: forward never rises and lateral never falls away from
##   the centre, and the cubic Hermite uses Fritsch–Carlson tangents, so the
##   carriage never overshoots its knots, loops or backtracks. The tip's
##   figure-of-eight silhouette comes from the blade turning through θ, not
##   from the carriage.
## - Mirrored by construction: forward is even in θ (with zero slope at the
##   centre), lateral is odd, so the combat geometry carries no side advantage.
## - Sampled every `step` over |θ| ∈ [0, limit]; runtime is an index and a
##   lerp. Deterministic: built with SimMath only, once per rules instance. The
##   normalized |θ| / step is a lookup index, never state.
##
## `fixed_pivot()` is the body-centred circle the duel used before the track:
## the blade pivots on the fighter's centre and there is no carriage.
##
## Implements: /spec/invariants.md#weapon-path-003
## See also: /docs/concepts/combat.md

const DEFAULT_STEP := deg_to_rad(0.5)

var _fixed: bool = true
var _step: float = DEFAULT_STEP
var _limit: float = 0.0
## Carriage per |θ| sample: forward, lateral toward the blade's side, and
## their slopes per radian of |θ|.
var _forward := PackedFloat64Array()
var _lateral := PackedFloat64Array()
var _forward_slope := PackedFloat64Array()
var _lateral_slope := PackedFloat64Array()


## The body-centred circle: the blade pivots on the fighter's centre.
static func fixed_pivot() -> WeaponAttackPath:
	return WeaponAttackPath.new()


## Why these knots cannot make a track, or "" when they can. At each |θ| in
## `knots` (radians, ascending from 0) the carriage sits `forward[i]` ahead
## and `lateral[i]` toward the blade's side (metres).
static func knot_problem(knots: PackedFloat64Array, forward: PackedFloat64Array, lateral: PackedFloat64Array, step: float = DEFAULT_STEP) -> String:
	var count := knots.size()
	if count < 2:
		return "fewer than two knots"
	if forward.size() != count or lateral.size() != count:
		return "knot, forward and lateral counts differ"
	if not (step > 0.0):
		return "the sample step is not positive"
	if knots[0] != 0.0:
		return "the first knot is not the centre (θ = 0)"
	if lateral[0] != 0.0:
		return "the centre is off the centreline (lateral %.4f), which breaks the mirror" % lateral[0]
	for index in count:
		if not (is_finite(knots[index]) and is_finite(forward[index]) and is_finite(lateral[index])):
			return "knot %d is not finite" % index
	for index in range(1, count):
		if knots[index] <= knots[index - 1]:
			return "knots %d and %d are not ascending" % [index - 1, index]
		if forward[index] > forward[index - 1]:
			return "forward rises between knots %d and %d" % [index - 1, index]
		if lateral[index] < lateral[index - 1]:
			return "lateral falls between knots %d and %d" % [index - 1, index]
	return ""


## A track through carriage knots (see `knot_problem`). Returns null for knots
## that cannot make one, so a bad content table fails closed at rules
## validation — never a silently substituted track.
static func from_carriage_knots(knots: PackedFloat64Array, forward: PackedFloat64Array, lateral: PackedFloat64Array, step: float = DEFAULT_STEP) -> WeaponAttackPath:
	if knot_problem(knots, forward, lateral, step) != "":
		return null
	var count := knots.size()
	var forward_tangents := _monotone_tangents(knots, forward)
	var lateral_tangents := _monotone_tangents(knots, lateral)
	## Forward is even in θ: its slope at the centre must vanish for C1.
	forward_tangents[0] = 0.0
	var path := WeaponAttackPath.new()
	path._fixed = false
	path._step = step
	path._limit = knots[count - 1]
	var samples := floori(path._limit / step) + 1
	for sample in samples:
		var at := minf(float(sample) * step, path._limit)
		var segment := _segment_of(knots, at)
		path._forward.append(_hermite(knots, forward, forward_tangents, segment, at))
		path._lateral.append(_hermite(knots, lateral, lateral_tangents, segment, at))
		path._forward_slope.append(_hermite_slope(knots, forward, forward_tangents, segment, at))
		path._lateral_slope.append(_hermite_slope(knots, lateral, lateral_tangents, segment, at))
	return path


## True when the blade pivots on the fighter's centre, for every θ.
func is_fixed() -> bool:
	return _fixed


## The last authored |θ|; past it the carriage holds while the blade turns.
func limit() -> float:
	return _limit


## Write the carriage's combat-frame position (`carriage_forward`,
## `carriage_left`) and its derivatives per radian of θ at `angle` into `out`.
## Zero on the fixed pivot, which has no carriage.
func sample_into(angle: float, out: BladePose) -> void:
	if _fixed:
		out.carriage_forward = 0.0
		out.carriage_left = 0.0
		out.d_carriage_forward = 0.0
		out.d_carriage_left = 0.0
		return
	var side := 1.0 if angle >= 0.0 else -1.0
	var at := minf(absf(angle), _limit)
	var index := mini(floori(at / _step), _forward.size() - 1)
	var next := mini(index + 1, _forward.size() - 1)
	## The last interval ends at the limit, so it may be shorter than a step.
	var span := minf(float(next) * _step, _limit) - float(index) * _step
	var t := 0.0 if span <= 0.0 else clampf((at - float(index) * _step) / span, 0.0, 1.0)
	## Between samples the carriage is the cubic Hermite through their values
	## and slopes, and its slope is that cubic's own derivative: the velocity a
	## contact is solved with is the motion the sweep carries (BLADE-COLLISION-
	## PARITY-001), and inside an authored segment the cubic is the authored
	## curve exactly.
	var forward := _hermite_sample(_forward, _forward_slope, index, next, span, t)
	var lateral := _hermite_sample(_lateral, _lateral_slope, index, next, span, t)
	var forward_slope := _hermite_sample_slope(_forward, _forward_slope, index, next, span, t)
	var lateral_slope := _hermite_sample_slope(_lateral, _lateral_slope, index, next, span, t)
	if absf(angle) > _limit:
		forward_slope = 0.0
		lateral_slope = 0.0
	## C(θ) = (f(|θ|), side·l(|θ|)); dC/dθ = (side·f′, l′).
	out.carriage_forward = forward
	out.carriage_left = side * lateral
	out.d_carriage_forward = side * forward_slope
	out.d_carriage_left = lateral_slope


static func _hermite_sample(values: PackedFloat64Array, slopes: PackedFloat64Array, index: int, next: int, span: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (
		(2.0 * t3 - 3.0 * t2 + 1.0) * values[index]
		+ (t3 - 2.0 * t2 + t) * span * slopes[index]
		+ (-2.0 * t3 + 3.0 * t2) * values[next]
		+ (t3 - t2) * span * slopes[next]
	)


static func _hermite_sample_slope(values: PackedFloat64Array, slopes: PackedFloat64Array, index: int, next: int, span: float, t: float) -> float:
	if span <= 0.0:
		return slopes[index]
	var t2 := t * t
	return (
		(6.0 * t2 - 6.0 * t) * values[index] / span
		+ (3.0 * t2 - 4.0 * t + 1.0) * slopes[index]
		+ (-6.0 * t2 + 6.0 * t) * values[next] / span
		+ (3.0 * t2 - 2.0 * t) * slopes[next]
	)


## The carriage's combat-frame position at `angle`: forward and left. For
## tests, authoring checks and presentation; allocates.
func carriage_forward(angle: float) -> float:
	var pose := BladePose.new()
	sample_into(angle, pose)
	return pose.carriage_forward


func carriage_left(angle: float) -> float:
	var pose := BladePose.new()
	sample_into(angle, pose)
	return pose.carriage_left


## Fritsch–Carlson monotone tangents: a cubic Hermite through these never
## overshoots its knots.
static func _monotone_tangents(knots: PackedFloat64Array, values: PackedFloat64Array) -> PackedFloat64Array:
	var count := knots.size()
	var secants := PackedFloat64Array()
	for index in count - 1:
		secants.append((values[index + 1] - values[index]) / (knots[index + 1] - knots[index]))
	var tangents := PackedFloat64Array()
	tangents.resize(count)
	tangents[0] = secants[0]
	tangents[count - 1] = secants[count - 2]
	for index in range(1, count - 1):
		var before := secants[index - 1]
		var after := secants[index]
		tangents[index] = 0.0 if before * after <= 0.0 else (before + after) * 0.5
	for index in count - 1:
		var secant := secants[index]
		if absf(secant) <= SimMath.EPSILON:
			tangents[index] = 0.0
			tangents[index + 1] = 0.0
			continue
		var alpha := tangents[index] / secant
		var beta := tangents[index + 1] / secant
		var magnitude := SimMath.length(alpha, beta)
		if magnitude > 3.0:
			var tau := 3.0 / magnitude
			tangents[index] = tau * alpha * secant
			tangents[index + 1] = tau * beta * secant
	return tangents


static func _segment_of(knots: PackedFloat64Array, at: float) -> int:
	for index in range(1, knots.size()):
		if at <= knots[index]:
			return index - 1
	return knots.size() - 2


static func _hermite(knots: PackedFloat64Array, values: PackedFloat64Array, tangents: PackedFloat64Array, segment: int, at: float) -> float:
	var span := knots[segment + 1] - knots[segment]
	var t := (at - knots[segment]) / span
	var t2 := t * t
	var t3 := t2 * t
	return (
		(2.0 * t3 - 3.0 * t2 + 1.0) * values[segment]
		+ (t3 - 2.0 * t2 + t) * span * tangents[segment]
		+ (-2.0 * t3 + 3.0 * t2) * values[segment + 1]
		+ (t3 - t2) * span * tangents[segment + 1]
	)


static func _hermite_slope(knots: PackedFloat64Array, values: PackedFloat64Array, tangents: PackedFloat64Array, segment: int, at: float) -> float:
	var span := knots[segment + 1] - knots[segment]
	var t := (at - knots[segment]) / span
	var t2 := t * t
	return (
		(6.0 * t2 - 6.0 * t) * values[segment] / span
		+ (3.0 * t2 - 4.0 * t + 1.0) * tangents[segment]
		+ (-6.0 * t2 + 6.0 * t) * values[segment + 1] / span
		+ (3.0 * t2 - 2.0 * t) * tangents[segment + 1]
	)
