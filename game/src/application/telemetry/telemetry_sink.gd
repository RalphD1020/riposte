class_name TelemetrySink
extends RefCounted

## Analytics seam (PLAN Phase 11.4): simulation → events → sink. The default
## sink keeps a bounded in-memory log and sends nothing anywhere; vendor,
## network, and replay sinks replace it without touching the simulation.
##
## See also: /docs/concepts/telemetry.md

const PRODUCT_LIMIT := 256

var product_events: Array[Dictionary] = []
var duel_event_count: int = 0


func record_product(event_name: StringName, properties: Dictionary = {}) -> void:
	product_events.append({"name": String(event_name), "properties": properties})
	if product_events.size() > PRODUCT_LIMIT:
		product_events.remove_at(0)


func record_duel_events(events: Array[DuelEvent]) -> void:
	duel_event_count += events.size()


func count_product(event_name: StringName) -> int:
	var total := 0
	for entry in product_events:
		if entry["name"] == String(event_name):
			total += 1
	return total
