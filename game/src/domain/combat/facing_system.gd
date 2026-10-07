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


static func step(fighter: FighterState, target_x: float, target_y: float, tracking: float, definition: FighterDefinition, capability: float = 1.0, scratch: FighterTickScratch = null) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var desired := SimMath.arctan2(target_y - fighter.y, target_x - fighter.x)
	var error := SimMath.wrap_angle(desired - fighter.facing)
	var max_rate := definition.turn_speed_max * tracking
	var desired_rate := clampf(definition.track_gain * error, -max_rate, max_rate)
	var angular_accel := definition.turn_accel() * tracking * capability
	var old_rate := fighter.turn_rate
	fighter.turn_rate = SimMath.approach(fighter.turn_rate, desired_rate, angular_accel * dt)
	fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
	if scratch != null:
		var inertia := definition.moment_of_inertia()
		var actual_alpha := (fighter.turn_rate - old_rate) / dt
		var applied_torque := inertia * actual_alpha
		var mid_omega := (old_rate + fighter.turn_rate) * 0.5
		var power := applied_torque * mid_omega
		scratch.turn_positive_work += maxf(power * dt, 0.0)
		scratch.turn_braking_work += maxf(-power * dt, 0.0)
		var base_max := definition.turn_accel() * dt
		scratch.turn_utilization = SimMath.clamp01(absf(fighter.turn_rate - old_rate) / base_max) if base_max > SimMath.EPSILON else 0.0
