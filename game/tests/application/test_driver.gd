extends TestCase

## DRIVER: fixed-timestep scheduling, capped catch-up, hitstop holds.
##
## Implements: /spec/invariants.md#hitstop-001
## See also: /docs/concepts/presentation.md

const TICK := 1.0 / 60.0


func _init() -> void:
	suite_name = "DRIVER"


func test_accumulates_whole_ticks_and_reports_alpha() -> void:
	var driver := FixedTickDriver.new()
	assert_eq(driver.consume(TICK * 2.5), 2, "two whole ticks")
	assert_near(driver.alpha(), 0.5, 1e-9, "half a tick pending")


func test_catch_up_is_capped_and_backlog_persists() -> void:
	var driver := FixedTickDriver.new()
	assert_eq(driver.consume(TICK * 10.0), FixedTickDriver.MAX_CATCH_UP_TICKS, "capped per frame")
	assert_eq(driver.consume(0.0), FixedTickDriver.MAX_CATCH_UP_TICKS, "backlog keeps draining")
	assert_eq(driver.consume(0.0), 2, "until it is gone")
	assert_eq(driver.consume(0.0), 0, "then nothing")


func test_hitstop_freezes_ticks_without_losing_time_after() -> void:
	var driver := FixedTickDriver.new()
	driver.hold(0.05)
	assert_true(driver.is_holding(), "holding")
	assert_eq(driver.consume(0.04), 0, "no ticks during the freeze")
	assert_eq(driver.alpha(), 0.0, "the pose stays frozen")
	assert_eq(driver.consume(0.01 + TICK * 1.5), 1, "time resumes once the freeze ends")
	assert_false(driver.is_holding(), "freeze over")


func test_the_longest_hold_wins() -> void:
	var driver := FixedTickDriver.new()
	driver.hold(0.06)
	driver.hold(0.02)
	driver.consume(0.03)
	assert_true(driver.is_holding(), "a shorter hold never truncates a longer one")


func test_pause_and_clear_backlog() -> void:
	var driver := FixedTickDriver.new()
	driver.paused = true
	assert_eq(driver.consume(1.0), 0, "paused drivers step nothing")
	driver.paused = false
	driver.consume(TICK * 0.75)
	driver.hold(1.0)
	driver.clear_backlog()
	assert_eq(driver.alpha(), 0.0, "backlog dropped")
	assert_false(driver.is_holding(), "hold dropped")
	assert_eq(driver.consume(-1.0), 0, "negative delta is ignored")
