class_name FixedTickDriver
extends RefCounted

## Wall-clock scheduler for the 60 Hz simulation ("fix your timestep").
## `consume(delta)` says how many ticks to step this frame (at most
## MAX_CATCH_UP_TICKS; leftover time persists). `alpha()` is the fraction of
## the next tick already elapsed, used for display interpolation, so the
## presentation and simulation share one clock.
##
## `hold(seconds)` is hitstop: wall-clock time stops feeding ticks while
## impact presentation plays. It never changes tick-indexed results, and
## headless runs and replays ignore it (HITSTOP-001).
##
## Implements: /spec/invariants.md#hitstop-001
## See also: /docs/concepts/presentation.md

const MAX_CATCH_UP_TICKS := 4

var tick_seconds: float = SimulationTimebase.TICK_SECONDS
var paused: bool = false
var _accumulator: float = 0.0
var _hold: float = 0.0


func consume(delta_seconds: float) -> int:
	if paused:
		return 0
	var remaining := maxf(delta_seconds, 0.0)
	if _hold > 0.0:
		var used := minf(_hold, remaining)
		_hold -= used
		remaining -= used
	_accumulator += remaining
	var steps := 0
	while _accumulator >= tick_seconds and steps < MAX_CATCH_UP_TICKS:
		_accumulator -= tick_seconds
		steps += 1
	return steps


## Hitstop: the longest pending hold wins; holds never stack.
func hold(seconds: float) -> void:
	_hold = maxf(_hold, seconds)


func is_holding() -> bool:
	return _hold > 0.0


func alpha() -> float:
	return clampf(_accumulator / tick_seconds, 0.0, 1.0)


## Resume without catching up a backgrounded tab.
func clear_backlog() -> void:
	_accumulator = 0.0
	_hold = 0.0
