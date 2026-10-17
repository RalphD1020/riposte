class_name ConditionState
extends RefCounted

## A fighter's physical condition for one tick (CONDITION-001, STAMINA-004):
## how much of their healthy voluntary force, speed and tracking damage and
## fatigue have left them, and which stamina gates are open. Computed once per
## fighter at the start of every tick by `ConditionModel` and stored in that
## fighter's `FighterTickScratch`; every system that drives a motor reads
## these fields and nothing calls the model again.
##
## Damage and fatigue do not change the laws of physics; they change how much
## voluntary force (and, for damage, speed and tracking) the fighter can
## produce within them. So the scales multiply actuator *output* only — never
## momentum, mass, inertia, geometry, friction, restitution, input buffering,
## perception or reaction — and every command still takes effect on the tick
## it arrives.
##
## Derived each tick from health and start-of-tick stamina, never stored in
## `FighterState`, never hashed.
##
## Implements: /spec/invariants.md#condition-001
## Implements: /spec/invariants.md#stamina-004
## See also: /docs/concepts/combat.md

## h = health / max_health in [0, 1], and its complement.
var health_fraction: float = 1.0
var damage_fraction: float = 0.0
## Start-of-tick stamina s in [0, 1], and the force term it leaves.
var stamina: float = 1.0
var fatigue_scale: float = 1.0
## Damage's own force term, before fatigue. The weapon's guard return and
## its neutral hold read this. Swing, wind-up, brake and the stagger hold
## read `force_scale`, which is this term times `fatigue_scale`.
var damage_force_scale: float = 1.0
## Multiplies every voluntary force and torque: locomotion, braking, burst,
## heading turn torque, and the weapon's swing, brake, wind-back and stagger
## hold. The damage term times the fatigue term. A weaker brake removes less
## speed in a tick; it does not change a speed ceiling.
var force_scale: float = 1.0
## Multiplies every voluntary target-speed limit: top footwork speed, burst
## speeds, the swing's target speeds and the wind-back speed. Damage only.
var speed_scale: float = 1.0
## Multiplies the heading-rate cap (`turn_speed_max`) — how fast the fighter
## can track a target. Turn torque is already reduced by `force_scale`.
## Damage only.
var tracking_scale: float = 1.0
## Stamina gates, read from start-of-tick stamina: whether a dash may start,
## and whether a held charge may earn wind-back credit.
var can_dash: bool = true
var can_charge: bool = true


## The healthy, rested identity: every scale exactly 1, every gate open.
static func healthy() -> ConditionState:
	return ConditionState.new()


func copy_from(other: ConditionState) -> void:
	health_fraction = other.health_fraction
	damage_fraction = other.damage_fraction
	stamina = other.stamina
	fatigue_scale = other.fatigue_scale
	damage_force_scale = other.damage_force_scale
	force_scale = other.force_scale
	speed_scale = other.speed_scale
	tracking_scale = other.tracking_scale
	can_dash = other.can_dash
	can_charge = other.can_charge
