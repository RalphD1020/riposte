class_name HitstopRequest
extends RefCounted

## A typed instruction to freeze presentation time. The director decides
## duration from ImpactFeedback + kit hitstop bands; PresentationTimeController
## calls FixedTickDriver.hold(). Wall-clock only (HITSTOP-001).
##
## See also: /docs/architecture/presentation-feedback.md

## Hold duration in seconds.
var duration: float = 0.0


static func create(seconds: float) -> HitstopRequest:
	var req := HitstopRequest.new()
	req.duration = maxf(seconds, 0.0)
	return req
