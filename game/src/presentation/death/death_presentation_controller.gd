class_name DeathPresentationController
extends RefCounted

## Routes each killing blow to the first backend able to carry it out, once per
## fighter per round. The death is authoritative and already decided; this only
## chooses how it looks, so the backend list (primitive today, a ragdoll ahead
## of it later) can change without touching the simulation.
##
## A death request that arrives twice for the same fighter starts once — the
## second is the same death, not a new one. `reset` clears that for the next
## round, when both fighters are alive again.
##
## See also: /docs/concepts/presentation.md

var _backends: Array[DeathPresentationBackend] = []
var _started: Dictionary = {}


## Backends in preference order; the last should always be available.
func _init(backends: Array[DeathPresentationBackend]) -> void:
	_backends = backends


func present(request: DeathPresentationRequest) -> void:
	if _started.has(request.slot):
		return
	for backend in _backends:
		if backend.is_available(request):
			_started[request.slot] = true
			backend.start(request)
			return


func has_started(slot: int) -> bool:
	return _started.has(slot)


func reset() -> void:
	_started.clear()
