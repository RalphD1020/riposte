class_name ConditionState
extends RefCounted

## A fighter's physical condition for one tick (CONDITION-001): how much of
## their healthy voluntary force, speed and tracking damage has left them.
## Computed once per fighter at the start of every tick by `ConditionModel`
## and stored in that fighter's `FighterTickScratch`; every system that drives
## a motor reads these fields and nothing calls the model again.
##
## Damage does not change the laws of physics; it changes how much voluntary
## force, speed and tracking the fighter can produce within them. So the
## scales multiply actuator *output* only — never momentum, mass, inertia,
## geometry, friction, restitution, input buffering, perception or reaction —
## and every command still takes effect on the tick it arrives.
##
## Derived each tick from health, never stored in `FighterState`, never
## hashed.
##
## Implements: /spec/invariants.md#condition-001
## See also: /docs/concepts/combat.md

## h = health / max_health in [0, 1], and its complement.
var health_fraction: float = 1.0
var damage_fraction: float = 0.0
## Multiplies every voluntary force and torque: locomotion, braking, burst,
## heading turn torque, and the weapon's swing, brake, wind-back and hold.
var force_scale: float = 1.0
## Multiplies every voluntary target-speed limit: top footwork speed, burst
## speeds, the swing's target speeds and the wind-back speed.
var speed_scale: float = 1.0
## Multiplies the heading-rate cap (`turn_speed_max`) — how fast the fighter
## can track a target. Turn torque is already reduced by `force_scale`.
var tracking_scale: float = 1.0


## The healthy identity: every scale exactly 1.
static func healthy() -> ConditionState:
	return ConditionState.new()


func copy_from(other: ConditionState) -> void:
	health_fraction = other.health_fraction
	damage_fraction = other.damage_fraction
	force_scale = other.force_scale
	speed_scale = other.speed_scale
	tracking_scale = other.tracking_scale
