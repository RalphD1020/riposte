class_name SlowMotionRequest
extends RefCounted

## Presentation-only slow motion over the terminal blow. Wall-clock only,
## exactly like hitstop: the clock owner consumes ticks more slowly and no
## tick-indexed result changes (HITSTOP-001).
##
## See also: /docs/architecture/presentation-feedback.md

var time_scale: float = 1.0
var seconds: float = 0.0


static func create(p_scale: float, p_seconds: float) -> SlowMotionRequest:
	var req := SlowMotionRequest.new()
	req.time_scale = clampf(p_scale, 0.05, 1.0)
	req.seconds = maxf(p_seconds, 0.0)
	return req
