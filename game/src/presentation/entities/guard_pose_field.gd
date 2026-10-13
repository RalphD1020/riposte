class_name GuardPoseField
extends RefCounted

## The discrete HEMA reading of the authoritative sword angle, for whatever
## needs a named band (the kinetic chain's effort, debug, tests). Riposte has
## one blade, swung freely, so the simulation has no "left guard" / "right
## guard" state — only a relative angle. Presentation reads that angle as a
## point on a continuous field across the 270° arc:
##
##   RIGHT_LOAD — RIGHT_READY — LONGPOINT — LEFT_READY — LEFT_LOAD
##   -135°…-80°   -80°…-18°     ±12–18°    18°…80°     80°…135°
##
## Negative angles are the fighter's right (the canonical guard is −45°).
## READY is the Riposte mid guard: two hands forward, the point threatening the
## opponent's opening on that side — HEMA-informed (Langort, Pflug, Ochs), not
## a claim to any one historical guard. LOAD is a cut wound back off the
## shoulder (Mittelhut/Zornhut-inspired: Meyer's Mittelhut carries the sword
## near horizontal at the waist, point back). LONGPOINT is the centreline and
## the thrust corridor. Where the hands actually go is the authoritative orbit
## `C(θ)`, lifted by `CombatPresentationField`; this reading never decides
## anything (PRES-001).
##
## The Longpoint corridor has hysteresis: a sword hovering near straight-ahead
## must swing clearly off-centre before the reading commits to a side, and come
## clearly back before it lets go of Longpoint. A side change therefore always
## passes through Longpoint, and a blade wavering around 0° never flickers.
##
## See also: /docs/concepts/presentation.md

enum State { RIGHT_LOAD, RIGHT_READY, LONGPOINT, LEFT_READY, LEFT_LOAD }
## The broad kinetic band, independent of side: how loaded the carriage is. The
## kinetic chain reads this (not the side) to scale the body's follow in guard.
enum Band { THRUST, READY, LOAD }

## Enter Longpoint only well inside centre; leave it only well outside. The gap
## between the two is the hysteresis that keeps a near-straight blade stable.
const THRUST_ENTER := deg_to_rad(12.0)
const THRUST_LEAVE := deg_to_rad(18.0)
## Beyond this the carriage is a loaded cut, not a ready guard.
const LOAD_ANGLE := deg_to_rad(80.0)

var state: State = State.LONGPOINT


## Advance the reading for this frame from the relative sword angle (radians,
## 0 = point forward, negative = the fighter's right). Returns the new state.
## Hysteresis lives entirely in the Longpoint boundary.
func update(theta: float) -> State:
	var mag := absf(theta)
	if state == State.LONGPOINT:
		if mag > THRUST_LEAVE:
			state = _side_state(theta, mag)
	elif mag < THRUST_ENTER:
		state = State.LONGPOINT
	else:
		state = _side_state(theta, mag)
	return state


func band() -> Band:
	match state:
		State.LONGPOINT:
			return Band.THRUST
		State.RIGHT_LOAD, State.LEFT_LOAD:
			return Band.LOAD
		_:
			return Band.READY


## Which side the reading holds: −1 right, +1 left, 0 in Longpoint. A load
## belongs to this shoulder, so a blade wavering about centre never swaps it.
func side() -> float:
	match state:
		State.RIGHT_LOAD, State.RIGHT_READY:
			return -1.0
		State.LEFT_LOAD, State.LEFT_READY:
			return 1.0
		_:
			return 0.0


static func _side_state(theta: float, mag: float) -> State:
	if mag >= LOAD_ANGLE:
		return State.RIGHT_LOAD if theta < 0.0 else State.LEFT_LOAD
	return State.RIGHT_READY if theta < 0.0 else State.LEFT_READY
