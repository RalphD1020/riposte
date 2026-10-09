class_name GuardPoseField
extends RefCounted

## The continuous HEMA guard the body reads from the authoritative sword angle.
## Riposte has one blade, swung freely, so the simulation has no discrete "left
## guard" / "right guard" state — only a relative angle. Presentation interprets
## that angle as a point on a continuous field running
##   LEFT_WIND_BACK — LEFT_READY — LONGPOINT — RIGHT_READY — RIGHT_WIND_BACK
## so a cut wound back off one shoulder reads as a loaded Mittelhut, and a point
## held forward reads as Longpoint. The field never decides anything: it only
## tells the body how to carry the blade the simulation already placed, so a
## stance is a reading of physics, never a cause of it (PRES-001).
##
## The thrust corridor around centre has hysteresis: a sword hovering near
## straight-ahead must swing clearly off-centre before the body commits to a
## side, and must come clearly off-centre again before it lets go of Longpoint.
## A side change therefore always passes through Longpoint — the body never
## snaps across centre, and a blade wavering around 0° never flickers between
## the two readings.
##
## See also: /docs/concepts/presentation.md

enum State { LEFT_WIND_BACK, LEFT_READY, LONGPOINT, RIGHT_READY, RIGHT_WIND_BACK }
## The broad kinetic band, independent of side: how loaded the carriage is. The
## kinetic chain reads this (not the side) to scale the body's follow in guard.
enum Band { THRUST, READY, WIND }

## Enter Longpoint only well inside centre; leave it only well outside. The gap
## between the two is the hysteresis that keeps a near-straight blade stable.
const THRUST_ENTER := deg_to_rad(12.0)
const THRUST_LEAVE := deg_to_rad(18.0)
## Beyond this the carriage is a wound-back cut, not a ready guard.
const WIND_ANGLE := deg_to_rad(75.0)

var state: State = State.LONGPOINT


## Advance the reading for this frame from the relative sword angle (radians,
## 0 = point forward, positive = one side, negative = the other). Returns the
## new state. Hysteresis lives entirely in the Longpoint boundary.
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
		State.LEFT_WIND_BACK, State.RIGHT_WIND_BACK:
			return Band.WIND
		_:
			return Band.READY


static func _side_state(theta: float, mag: float) -> State:
	if mag >= WIND_ANGLE:
		return State.RIGHT_WIND_BACK if theta > 0.0 else State.LEFT_WIND_BACK
	return State.RIGHT_READY if theta > 0.0 else State.LEFT_READY
