class_name SimMath
extends RefCounted

## Deterministic scalar math for the authoritative simulation.
##
## Only IEEE-754 correctly rounded operations (+ - * / sqrt) are used, each as
## a separate GDScript operation, so results are bit-identical on every
## platform. Engine sin/cos/atan2/pow call platform libm, and C++ helpers such
## as lerp may be contracted into FMA on ARM; the simulation never calls them.
## Accuracy is better than 1e-9 rad, which is far below gameplay resolution.
##
## Implements: /spec/invariants.md#sim-math-001
## See also: /docs/concepts/simulation.md

const HALF_PI := PI * 0.5
const SQRT_3 := 1.7320508075688772
const TAN_PI_12 := 0.2679491924311227
const PI_6 := PI / 6.0
const EPSILON := 1e-12

const _SIN_3 := -1.0 / 6.0
const _SIN_5 := 1.0 / 120.0
const _SIN_7 := -1.0 / 5040.0
const _SIN_9 := 1.0 / 362880.0
const _SIN_11 := -1.0 / 39916800.0
const _SIN_13 := 1.0 / 6227020800.0


## Angle wrapped into (-PI, PI].
static func wrap_angle(angle: float) -> float:
	var wrapped := angle
	if wrapped > PI or wrapped <= -PI:
		wrapped = wrapped - TAU * floorf((wrapped + PI) / TAU)
		if wrapped <= -PI:
			wrapped += TAU
		elif wrapped > PI:
			wrapped -= TAU
	return wrapped


static func sine(angle: float) -> float:
	var x := wrap_angle(angle)
	if x > HALF_PI:
		x = PI - x
	elif x < -HALF_PI:
		x = -PI - x
	var x2 := x * x
	return x * (1.0 + x2 * (_SIN_3 + x2 * (_SIN_5 + x2 * (_SIN_7 + x2 * (_SIN_9 + x2 * (_SIN_11 + x2 * _SIN_13))))))


static func cosine(angle: float) -> float:
	return sine(angle + HALF_PI)


## Arc tangent in (-PI/2, PI/2), reduced to |u| <= tan(PI/12) before a short series.
static func arctan(value: float) -> float:
	var negative := value < 0.0
	var v := -value if negative else value
	var inverted := v > 1.0
	if inverted:
		v = 1.0 / v
	var offset := 0.0
	if v > TAN_PI_12:
		v = (v * SQRT_3 - 1.0) / (SQRT_3 + v)
		offset = PI_6
	var v2 := v * v
	var result := v * (1.0 + v2 * (-1.0 / 3.0 + v2 * (0.2 + v2 * (-1.0 / 7.0 + v2 * (1.0 / 9.0 + v2 * (-1.0 / 11.0 + v2 * (1.0 / 13.0)))))))
	result += offset
	if inverted:
		result = HALF_PI - result
	return -result if negative else result


## Angle of the vector (x, y) in (-PI, PI]. Zero vector yields 0.
static func arctan2(y: float, x: float) -> float:
	if x > 0.0:
		return arctan(y / x)
	if x < 0.0:
		return arctan(y / x) + (PI if y >= 0.0 else -PI)
	if y > 0.0:
		return HALF_PI
	if y < 0.0:
		return -HALF_PI
	return 0.0


static func length(x: float, y: float) -> float:
	return sqrt(x * x + y * y)


static func clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)


## Linear blend a + (b - a) * t, evaluated as separate operations.
static func mix(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## Step `current` toward `target` by at most `max_delta` without overshoot.
static func approach(current: float, target: float, max_delta: float) -> float:
	if current < target:
		return minf(current + max_delta, target)
	return maxf(current - max_delta, target)


## Shortest-path angle blend from `from_angle` toward `to_angle`.
static func mix_angle(from_angle: float, to_angle: float, t: float) -> float:
	return wrap_angle(from_angle + wrap_angle(to_angle - from_angle) * t)


## value^1.25 for value >= 0, as value * value^(1/4).
static func pow_1_25(value: float) -> float:
	if value <= 0.0:
		return 0.0
	return value * sqrt(sqrt(value))


## Piecewise-linear lookup. `xs` ascending; values outside the table clamp.
static func piecewise(xs: PackedFloat64Array, ys: PackedFloat64Array, x: float) -> float:
	var count := xs.size()
	if count == 0:
		return 0.0
	if x <= xs[0]:
		return ys[0]
	for i in range(1, count):
		if x <= xs[i]:
			var span := xs[i] - xs[i - 1]
			var t := 0.0 if span <= 0.0 else (x - xs[i - 1]) / span
			return mix(ys[i - 1], ys[i], t)
	return ys[count - 1]


## Parameter t in [0, 1] of the point on segment a→b closest to p.
static func closest_param_on_segment(ax: float, ay: float, bx: float, by: float, px: float, py: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var length_sq := dx * dx + dy * dy
	if length_sq <= EPSILON:
		return 0.0
	return clamp01(((px - ax) * dx + (py - ay) * dy) / length_sq)


## Closest points between segments p1→q1 and p2→q2 (Ericson, RTCD 5.1.9).
## Writes the result into `out` to keep the collision hot path allocation-free.
static func closest_segments(
	p1x: float, p1y: float, q1x: float, q1y: float,
	p2x: float, p2y: float, q2x: float, q2y: float,
	out: SegmentContact
) -> void:
	var d1x := q1x - p1x
	var d1y := q1y - p1y
	var d2x := q2x - p2x
	var d2y := q2y - p2y
	var rx := p1x - p2x
	var ry := p1y - p2y
	var a := d1x * d1x + d1y * d1y
	var e := d2x * d2x + d2y * d2y
	var f := d2x * rx + d2y * ry
	var s := 0.0
	var t := 0.0
	if a <= EPSILON and e <= EPSILON:
		s = 0.0
		t = 0.0
	elif a <= EPSILON:
		t = clamp01(f / e)
	else:
		var c := d1x * rx + d1y * ry
		if e <= EPSILON:
			s = clamp01(-c / a)
		else:
			var b := d1x * d2x + d1y * d2y
			var denom := a * e - b * b
			s = clamp01((b * f - c * e) / denom) if denom > EPSILON else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clamp01(-c / a)
			elif t > 1.0:
				t = 1.0
				s = clamp01((b - c) / a)
	out.s = s
	out.t = t
	out.ax = p1x + d1x * s
	out.ay = p1y + d1y * s
	out.bx = p2x + d2x * t
	out.by = p2y + d2y * t
	out.distance = length(out.ax - out.bx, out.ay - out.by)
