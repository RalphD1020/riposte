class_name SimulationTimebase
extends RefCounted

## Canonical simulation clock: 60 deterministic ticks per second. Combat never
## reads render-frame delta; every command names its tick.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md

const TICK_RATE := 60
const TICK_SECONDS := 1.0 / 60.0


static func ticks_to_seconds(ticks: int) -> float:
	return float(ticks) * TICK_SECONDS


## Whole seconds remaining shown as M:SS for HUD/debug text.
static func format_clock(ticks: int) -> String:
	var total_seconds := ceili(float(maxi(ticks, 0)) / float(TICK_RATE))
	var minutes := floori(float(total_seconds) / 60.0)
	return "%d:%02d" % [minutes, total_seconds - minutes * 60]
