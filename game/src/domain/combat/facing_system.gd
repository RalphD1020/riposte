class_name FacingSystem
extends RefCounted

## Facing with angular inertia (COMBAT §9–§10). The body is turned by bounded
## torque against its own moment of inertia — `α = τ_base × A_turn / I_body` —
## so a committed fighter can be out-angled.
##
## `turn_rate` is body angular velocity, and it is never clamped down when
## authority falls (PHYS-003). Reducing authority reduces the torque available
## both to accelerate *and* to arrest rotation, which is why a body already
## rotating into its swing must spend time killing that rotation before it can
## reverse. Overshoot and reversal delay are emergent; nothing snaps.
##
## Implements: /spec/invariants.md#phys-003
## See also: /docs/concepts/combat.md


## `condition` is the fighter's frozen condition this tick (CONDITION-001):
## its force scale reduces the turn torque, its tracking scale the heading-rate
## cap. Null is the healthy identity. `tracking` is the share of the turn
## torque commitment leaves; `rate_tracking` the share of the turn-rate cap
## (DIRECTIONAL-COMMIT-001), the same share when omitted.
static func step(fighter: FighterState, target_x: float, target_y: float, tracking: float, definition: FighterDefinition, condition: ConditionState = null, rate_tracking: float = -1.0) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var force_scale := condition.force_scale if condition != null else 1.0
	var tracking_scale := condition.tracking_scale if condition != null else 1.0
	var rate_share := rate_tracking if rate_tracking >= 0.0 else tracking
	var desired := SimMath.arctan2(target_y - fighter.y, target_x - fighter.x)
	var error := SimMath.wrap_angle(desired - fighter.facing)
	var max_rate := definition.turn_speed_max * tracking_scale * rate_share
	var desired_rate := clampf(definition.track_gain * error, -max_rate, max_rate)
	var angular_accel := definition.turn_accel() * tracking * force_scale
	fighter.turn_rate = SimMath.approach(fighter.turn_rate, desired_rate, angular_accel * dt)
	fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
