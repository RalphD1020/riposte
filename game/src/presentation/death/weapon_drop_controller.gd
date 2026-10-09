class_name WeaponDropController
extends RefCounted

## Holds each requested sword drop until its hands let go, then releases it —
## once per fighter per round. Pure bookkeeping on wall-clock time: no nodes and
## no physics, so when and how often a sword drops is fully testable, while the
## tumble itself stays a device-QA concern.
##
## See also: /docs/concepts/presentation.md

## slot → WeaponDropRequest still waiting for its delay.
var _pending: Dictionary = {}
## slot → seconds left before release.
var _remaining: Dictionary = {}
var _released: Dictionary = {}


## Queue a drop. A fighter who already dropped (or is about to) this round is
## not asked twice: the second request is the same sword.
func request(drop: WeaponDropRequest) -> void:
	if _released.has(drop.slot) or _pending.has(drop.slot):
		return
	_pending[drop.slot] = drop
	_remaining[drop.slot] = drop.delay


## Advance wall-clock time; returns the drops whose hands let go this frame.
func advance(delta: float) -> Array[WeaponDropRequest]:
	var due: Array[WeaponDropRequest] = []
	for slot: int in _pending.keys():
		_remaining[slot] = float(_remaining[slot]) - delta
		if float(_remaining[slot]) <= 0.0:
			due.append(_pending[slot])
			_released[slot] = true
	for drop in due:
		_pending.erase(drop.slot)
		_remaining.erase(drop.slot)
	return due


func has_released(slot: int) -> bool:
	return _released.has(slot)


func reset() -> void:
	_pending.clear()
	_remaining.clear()
	_released.clear()
