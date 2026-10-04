class_name DuelEvent
extends RefCounted

## One thing that happened on a tick. `actor` / `target` are fighter slots or
## -1. `data` holds only numbers, bools, and short strings keyed by
## DuelEventKeys, so events serialize for replays and analytics without
## engine types.
##
## See also: /docs/concepts/simulation.md

const NONE := -1

var type: StringName = &""
var tick: int = 0
var actor: int = NONE
var target: int = NONE
var data: Dictionary = {}


static func create(
	type_value: StringName,
	tick_value: int,
	actor_slot: int = NONE,
	target_slot: int = NONE,
	payload: Dictionary = {}
) -> DuelEvent:
	var event := DuelEvent.new()
	event.type = type_value
	event.tick = tick_value
	event.actor = actor_slot
	event.target = target_slot
	event.data = payload
	return event


func number(key: String, fallback: float = 0.0) -> float:
	return float(data.get(key, fallback))


func text(key: String) -> String:
	return str(data.get(key, ""))


func to_dictionary() -> Dictionary:
	return {
		"type": String(type),
		"tick": tick,
		"actor": actor,
		"target": target,
		"data": data.duplicate(),
	}
