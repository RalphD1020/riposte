class_name WeaponDropRequest
extends RefCounted

## A fighter losing their sword: after a killing blow the dead hand goes slack,
## and over the edge the hands let go a beat after the ledge. The sword then
## becomes a presentation-only physics body that tumbles to the floor (or off
## it). The simulation has already decided the round; the dropped sword is
## never read back, never collides with anything authoritative, and cannot
## change a hit, a ring-out, the winner, or the replay hash (PRES-001).
##
## The request carries the blade's own motion about the hands, from the
## authoritative blade angle and spin. The body's motion is added at release
## from the presented root — still for a collapse in place, the fall trajectory
## for a ring-out — so the sword leaves the hand moving with the body that held
## it, and the exit momentum is never counted twice.
##
## See also: /docs/concepts/presentation.md

## The dead hand goes slack as the collapse begins (wall-clock seconds).
const DEATH_DELAY := 0.12
## Over the edge the hands let go between these, chosen from the event key.
const RING_OUT_DELAY_MIN := 0.15
const RING_OUT_DELAY_MAX := 0.35
const RING_OUT_DELAY_STEPS := 5

var slot: int = 0
## Wall-clock seconds from the event until the hands let go.
var delay: float = 0.0
## The blade's own velocity at its centre (world, m/s), from its spin.
var linear_velocity: Vector3 = Vector3.ZERO
## The blade's spin (world, rad/s): sim CCW about up is world +Y.
var angular_velocity: Vector3 = Vector3.ZERO
var key: int = 0


static func create(p_slot: int, p_delay: float, p_linear: Vector3, p_angular: Vector3, p_key: int) -> WeaponDropRequest:
	var request := WeaponDropRequest.new()
	request.slot = p_slot
	request.delay = maxf(p_delay, 0.0)
	request.linear_velocity = p_linear
	request.angular_velocity = p_angular
	request.key = p_key
	return request


## The blade, mid-spin, as the hands release it: from a fighter's snapshot row.
static func from_blade(p_slot: int, p_delay: float, row: PresentationFighter, p_key: int) -> WeaponDropRequest:
	var omega := row.blade_speed * row.swing_dir
	var radius := (row.hilt_radius + row.tip_radius) * 0.5
	return create(p_slot, p_delay, blade_velocity(row.blade_angle, omega, radius), Vector3(0.0, omega, 0.0), p_key)


## Velocity of a point `radius` along a blade at absolute angle `angle`
## turning at `omega` (sim CCW), in world space. Pure.
static func blade_velocity(angle: float, omega: float, radius: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, -cos(angle)) * omega * radius


## When the hands let go after a ring-out: a deterministic beat in the window.
static func ring_out_delay(p_key: int) -> float:
	var step := absi(p_key) % RING_OUT_DELAY_STEPS
	return lerpf(RING_OUT_DELAY_MIN, RING_OUT_DELAY_MAX, float(step) / float(RING_OUT_DELAY_STEPS - 1))
