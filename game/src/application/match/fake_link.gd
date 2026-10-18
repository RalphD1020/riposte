class_name FakeLink
extends RefCounted

## Deterministic delivery for friend-match notes. Delay, drop, and reorder
## are explicit. This is not a Steam socket.
##
## See also: /docs/concepts/simulation.md

var time: int = 0
var delay: int = 0
var drop_remaining: int = 0
var _queue: Array[Dictionary] = []


func send(note: MatchNote) -> void:
	if note == null:
		return
	if drop_remaining > 0:
		drop_remaining -= 1
		return
	_queue.append({"at": time + delay, "note": note})


func advance(steps: int = 1) -> void:
	time += steps


## Notes whose delay has elapsed, in send order.
func take() -> Array[MatchNote]:
	var ready: Array[MatchNote] = []
	var rest: Array[Dictionary] = []
	for item in _queue:
		if int(item["at"]) <= time:
			ready.append(item["note"])
		else:
			rest.append(item)
	_queue = rest
	return ready


## Deliver the newest waiting note first. The authority still applies commands
## by sequence, so this is a reorder, not a license to skip one.
func take_reversed() -> Array[MatchNote]:
	var ready := take()
	ready.reverse()
	return ready
