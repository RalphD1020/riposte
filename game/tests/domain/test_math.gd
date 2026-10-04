extends TestCase

## MATH: deterministic SimMath matches analytic values and the engine oracle.
##
## Implements: /spec/invariants.md#sim-math-001
## See also: /docs/concepts/simulation.md

const TOLERANCE := 1e-9


func _init() -> void:
	suite_name = "MATH"


func test_sine_and_cosine_hit_exact_landmarks() -> void:
	assert_near(SimMath.sine(0.0), 0.0, TOLERANCE, "sin 0")
	assert_near(SimMath.sine(PI / 6.0), 0.5, TOLERANCE, "sin 30°")
	assert_near(SimMath.sine(PI / 2.0), 1.0, TOLERANCE, "sin 90°")
	assert_near(SimMath.sine(-PI / 2.0), -1.0, TOLERANCE, "sin -90°")
	assert_near(SimMath.cosine(PI / 3.0), 0.5, TOLERANCE, "cos 60°")
	assert_near(SimMath.cosine(PI), -1.0, TOLERANCE, "cos 180°")


func test_trig_matches_engine_oracle_across_turns() -> void:
	var worst := 0.0
	for i in range(-720, 721):
		var angle := float(i) * PI / 180.0 * 1.7
		worst = maxf(worst, absf(SimMath.sine(angle) - sin(angle)))
		worst = maxf(worst, absf(SimMath.cosine(angle) - cos(angle)))
	assert_true(worst < TOLERANCE, "worst trig error %s below 1e-9" % str(worst))


func test_arctan2_covers_every_quadrant() -> void:
	assert_near(SimMath.arctan2(1.0, 1.0), PI / 4.0, TOLERANCE, "quadrant I")
	assert_near(SimMath.arctan2(1.0, -1.0), 3.0 * PI / 4.0, TOLERANCE, "quadrant II")
	assert_near(SimMath.arctan2(-1.0, -1.0), -3.0 * PI / 4.0, TOLERANCE, "quadrant III")
	assert_near(SimMath.arctan2(-1.0, 1.0), -PI / 4.0, TOLERANCE, "quadrant IV")
	assert_near(SimMath.arctan2(0.0, -1.0), PI, TOLERANCE, "negative X axis is +PI")
	assert_eq(SimMath.arctan2(0.0, 0.0), 0.0, "zero vector has angle 0")
	assert_near(SimMath.arctan2(2.0, 0.0), PI / 2.0, TOLERANCE, "positive Y axis")
	assert_near(SimMath.arctan2(-2.0, 0.0), -PI / 2.0, TOLERANCE, "negative Y axis")


func test_arctan2_matches_engine_oracle() -> void:
	var worst := 0.0
	for i in range(0, 360):
		var angle := float(i) * PI / 180.0
		var radius := 0.25 + float(i % 7)
		var x := radius * cos(angle)
		var y := radius * sin(angle)
		worst = maxf(worst, absf(SimMath.wrap_angle(SimMath.arctan2(y, x) - atan2(y, x))))
	assert_true(worst < TOLERANCE, "worst atan2 error %s below 1e-9" % str(worst))


func test_wrap_angle_lands_in_half_open_range() -> void:
	assert_near(SimMath.wrap_angle(3.0 * PI), PI, TOLERANCE, "3π wraps to π")
	assert_near(SimMath.wrap_angle(-PI), PI, TOLERANCE, "-π maps to +π")
	assert_near(SimMath.wrap_angle(TAU + 0.25), 0.25, TOLERANCE, "one turn removed")
	assert_near(SimMath.wrap_angle(-TAU - 0.25), -0.25, TOLERANCE, "negative turn removed")
	assert_eq(SimMath.wrap_angle(1.0), 1.0, "in-range angle unchanged")


func test_blends_and_approach() -> void:
	assert_eq(SimMath.mix(2.0, 6.0, 0.25), 3.0, "mix quarter")
	assert_eq(SimMath.approach(0.0, 1.0, 0.25), 0.25, "approach steps up")
	assert_eq(SimMath.approach(1.0, 0.0, 2.0), 0.0, "approach never overshoots down")
	assert_near(SimMath.mix_angle(PI - 0.1, -PI + 0.1, 0.5), PI, TOLERANCE, "angle blend takes the short way")
	assert_near(SimMath.pow_1_25(0.5), pow(0.5, 1.25), TOLERANCE, "C^1.25")
	assert_eq(SimMath.pow_1_25(-1.0), 0.0, "negative charge has zero commitment curve")


func test_piecewise_interpolates_and_clamps() -> void:
	var xs := PackedFloat64Array([0.0, 1.0, 2.0])
	var ys := PackedFloat64Array([0.0, 10.0, 0.0])
	assert_eq(SimMath.piecewise(xs, ys, -1.0), 0.0, "below table clamps")
	assert_eq(SimMath.piecewise(xs, ys, 0.5), 5.0, "first span")
	assert_eq(SimMath.piecewise(xs, ys, 1.5), 5.0, "second span")
	assert_eq(SimMath.piecewise(xs, ys, 9.0), 0.0, "above table clamps")
	assert_eq(SimMath.piecewise(PackedFloat64Array(), PackedFloat64Array(), 1.0), 0.0, "empty table")


func test_segment_queries() -> void:
	assert_eq(SimMath.closest_param_on_segment(0.0, 0.0, 2.0, 0.0, 1.0, 5.0), 0.5, "projection mid-segment")
	assert_eq(SimMath.closest_param_on_segment(0.0, 0.0, 2.0, 0.0, -3.0, 0.0), 0.0, "clamps to start")
	assert_eq(SimMath.closest_param_on_segment(1.0, 1.0, 1.0, 1.0, 4.0, 4.0), 0.0, "degenerate segment")
	var contact := SegmentContact.new()
	SimMath.closest_segments(-1.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 1.0, contact)
	assert_near(contact.distance, 0.0, TOLERANCE, "crossing segments touch")
	assert_near(contact.s, 0.5, TOLERANCE, "cross at middle of first")
	SimMath.closest_segments(0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 1.0, 2.0, contact)
	assert_near(contact.distance, 2.0, TOLERANCE, "parallel segments two apart")
	SimMath.closest_segments(0.0, 0.0, 1.0, 0.0, 3.0, 1.0, 3.0, 3.0, contact)
	assert_near(contact.distance, SimMath.length(2.0, 1.0), TOLERANCE, "endpoint to endpoint")
	SimMath.closest_segments(0.0, 0.0, 0.0, 0.0, 2.0, -1.0, 2.0, 1.0, contact)
	assert_near(contact.distance, 2.0, TOLERANCE, "point to segment")
