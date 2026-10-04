class_name MovementSystem
extends RefCounted

## Footwork (COMBAT §23–§25, §36). Acceleration-limited movement toward the
## input's desired velocity: forward is fastest, backward slowest, and
## commitment cuts both speed and acceleration. Updates stability from how
## violently the body is changing motion.
##
## See also: /docs/concepts/combat.md


static func step(fighter: FighterState, input_x: float, input_y: float, definition: FighterDefinition) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var ix := input_x
	var iy := input_y
	var magnitude := SimMath.length(ix, iy)
	if magnitude > 1.0:
		ix /= magnitude
		iy /= magnitude
		magnitude = 1.0
	var direction_multiplier := 1.0
	if magnitude > 0.0:
		var alignment := (ix * SimMath.cosine(fighter.facing) + iy * SimMath.sine(fighter.facing)) / magnitude
		if alignment >= 0.0:
			direction_multiplier = SimMath.mix(definition.speed_lateral, definition.speed_forward, alignment)
		else:
			direction_multiplier = SimMath.mix(definition.speed_lateral, definition.speed_backward, -alignment)
	var top_speed := definition.max_speed * direction_multiplier * CommitmentModel.translation_multiplier(fighter, definition)
	var target_vx := ix * top_speed
	var target_vy := iy * top_speed
	var delta_vx := target_vx - fighter.vx
	var delta_vy := target_vy - fighter.vy
	var delta := SimMath.length(delta_vx, delta_vy)
	var braking := (
		target_vx * fighter.vx + target_vy * fighter.vy < 0.0
		or SimMath.length(target_vx, target_vy) < fighter.speed()
	)
	var accel := definition.brake_accel if braking else definition.move_accel
	var max_delta := accel * CommitmentModel.accel_multiplier(fighter, definition) * dt
	var old_vx := fighter.vx
	var old_vy := fighter.vy
	if delta <= max_delta:
		fighter.vx = target_vx
		fighter.vy = target_vy
	else:
		fighter.vx += delta_vx / delta * max_delta
		fighter.vy += delta_vy / delta * max_delta
	fighter.x += fighter.vx * dt
	fighter.y += fighter.vy * dt
	_update_stability(fighter, definition, old_vx, old_vy, dt)


## Planted bodies transfer force best (COMBAT §36): violent acceleration and
## fast turning lower B toward its floor; staggered fighters sit at the floor.
static func _update_stability(fighter: FighterState, definition: FighterDefinition, old_vx: float, old_vy: float, dt: float) -> void:
	var accel := SimMath.length(fighter.vx - old_vx, fighter.vy - old_vy) / dt
	var accel_norm := SimMath.clamp01(accel / definition.brake_accel)
	var turn_norm := SimMath.clamp01(absf(fighter.turn_rate) / definition.turn_speed_max)
	var target := clampf(
		1.0 - definition.stability_accel_weight * accel_norm - definition.stability_turn_weight * turn_norm,
		definition.stability_floor,
		1.0
	)
	if fighter.weapon.phase == CombatPhase.Id.STAGGER:
		target = definition.stability_floor
	fighter.stability = SimMath.approach(fighter.stability, target, definition.stability_rate * dt)


## Brake a body with no input (used while a round result is shown).
static func coast(fighter: FighterState, definition: FighterDefinition) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var current := fighter.speed()
	if current > SimMath.EPSILON:
		var scale := maxf(current - definition.brake_accel * dt, 0.0) / current
		fighter.vx *= scale
		fighter.vy *= scale
	fighter.x += fighter.vx * dt
	fighter.y += fighter.vy * dt
	fighter.turn_rate = SimMath.approach(fighter.turn_rate, 0.0, definition.turn_accel * dt)
	fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
