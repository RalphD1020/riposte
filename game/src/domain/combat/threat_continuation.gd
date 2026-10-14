class_name ThreatContinuation
extends RefCounted

## The one named future a threat prediction assumes (THREAT-001, CPU-008):
## how the predicted attacker's body moves, and whether the target's sword is
## swept. Everything else is fixed by the predictor itself — the attacker's
## own motors, its heading tracking the target, the target carried at its
## current velocity, its heading tracking automatically when swept, never its
## future input. Two estimates that are compared with each other MUST be given
## the same continuation for everything outside the candidate action being
## evaluated, so a comparison never silently mixes two imagined futures.
##
## See also: /docs/concepts/cpu.md

## How the attacker's body is predicted to move:
## CLOSING — the unopposed close at full locomotion force toward the target;
## PLANTED — no new footwork, the body carries its current velocity;
## ROUTE — closing at full force along a stated direction (an intended path).
const CLOSING := 0
const PLANTED := 1
const ROUTE := 2

var motion: int = CLOSING
var route_x: float = 0.0
var route_y: float = 0.0
## Sweep every collidable feature of both swords, the target's under its own
## known law (a cut met by steel first is not a threat).
var steel: bool = false


## The unopposed close, no swords swept: the classic threat time (THREAT-001).
static func closing() -> ThreatContinuation:
	return ThreatContinuation.new()


## The body carries its current velocity: no new footwork.
static func planted(sweep_steel: bool = false) -> ThreatContinuation:
	var out := ThreatContinuation.new()
	out.motion = PLANTED
	out.steel = sweep_steel
	return out


## Closing along a world direction, the swords swept — a candidate route.
static func route(x: float, y: float) -> ThreatContinuation:
	var out := ThreatContinuation.new()
	out.motion = ROUTE
	out.route_x = x
	out.route_y = y
	out.steel = true
	return out
