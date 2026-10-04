class_name FacingSystem
extends RefCounted

## Facing with angular inertia (COMBAT §9–§10). Each fighter turns toward a
## target point, but turn rate and turn acceleration are bounded and scaled by
## tracking capability, so a committed fighter can be out-angled.
##
## See also: /docs/concepts/combat.md


static func step(fighter: FighterState, target_x: float, target_y: float, tracking: float, definition: FighterDefinition) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var desired := SimMath.arctan2(target_y - fighter.y, target_x - fighter.x)
	var error := SimMath.wrap_angle(desired - fighter.facing)
	var max_rate := definition.turn_speed_max * tracking
	var desired_rate := clampf(definition.track_gain * error, -max_rate, max_rate)
	fighter.turn_rate = SimMath.approach(fighter.turn_rate, desired_rate, definition.turn_accel * tracking * dt)
	fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
