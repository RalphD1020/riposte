class_name FallenBodyState
extends RefCounted

## A killed fighter's body, once the round is decided (Phase 15). Authoritative,
## hashed, reset per round.
##
## A body is still a body: it has its fighter's real mass, but no motor and no
## bracing, so it slides on the floor against Coulomb ground friction instead of
## braking like a standing fighter, and it turns about its centre of mass when
## something strikes it off-centre. While it collapses (`settle_left` ticks,
## per cause: a cut drops it at once, a run-through holds it on the blade
## first) it is still the standing push circle; once down it lies as a capsule
## along `yaw` through the fighter's own position, which is its centre of mass,
## so lying down never moves anything.
##
## The result of the round is already final: a body that is pushed, rolled or
## carried over the edge changes nothing about who won.
##
## See also: /docs/concepts/simulation.md

## The body has been killed this round (it is a body, not a fighter).
var active: bool = false
## Direction (radians, CCW from +X) the body lies along — the way the killing
## impulse threw it.
var yaw: float = 0.0
## Its turn rate about the vertical through its centre of mass (rad/s).
var spin: float = 0.0
## Ticks of collapse left before it lies.
var settle_left: int = 0
## Whether it went over the edge as a body (the post-round corpse fall).
var over_edge: bool = false


func reset() -> void:
	active = false
	yaw = 0.0
	spin = 0.0
	settle_left = 0
	over_edge = false


## The body begins: thrown along `direction`, lying after `settle_ticks`.
func begin(direction: float, settle_ticks: int) -> void:
	active = true
	yaw = SimMath.wrap_angle(direction)
	spin = 0.0
	settle_left = maxi(settle_ticks, 0)
	over_edge = false


## Down and lying — pushed as a capsule, no longer collapsing.
func is_lying() -> bool:
	return active and settle_left == 0
