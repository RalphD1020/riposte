class_name GuardRegion
extends RefCounted

## Diagnostic classification of where the blade is relative to the canonical
## guard. HUD, telemetry, training overlays, and the debug overlay use this to
## *describe* the blade; nothing may use it to *decide* anything.
##
## Physics drives the classification, never the reverse. The authoritative
## quantities are continuous — `angle`, `WeaponDefinition.readiness`, and
## earned wind-back — and `|angle| == guard_angle` is effectively measure-zero
## once a collision has disturbed the blade, so a discrete region is the wrong
## shape for a rule. Lint forbids this class under `src/domain/combat` and
## `src/domain/match`.
##
## See also: /docs/concepts/combat.md

enum Id {
	## |angle| < guard_angle: quick to reach threat, low motor authority.
	UNDER_PREPARED,
	## |angle| ~= guard_angle: the canonical ±45° guard, within epsilon.
	BASELINE,
	## |angle| > guard_angle: wound back past baseline, up to the guard limit.
	OUTWARD,
}

## How close to the canonical guard still counts as BASELINE, in radians.
## Purely a labelling tolerance; the simulation never snaps to it.
const BASELINE_EPSILON := 0.0087266462599716


static func of(angle: float, guard_angle: float) -> Id:
	var offset := absf(angle) - guard_angle
	if absf(offset) <= BASELINE_EPSILON:
		return Id.BASELINE
	return Id.UNDER_PREPARED if offset < 0.0 else Id.OUTWARD


static func label(region: Id) -> String:
	match region:
		Id.UNDER_PREPARED:
			return "UNDER_PREPARED"
		Id.BASELINE:
			return "BASELINE"
		Id.OUTWARD:
			return "OUTWARD"
	return "UNKNOWN"
