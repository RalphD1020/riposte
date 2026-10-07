class_name MovementSystem
extends RefCounted

## Footwork (COMBAT §23–§25, §36). Acceleration-limited movement toward the
## input's desired velocity: forward is fastest, backward slowest, and
## commitment cuts the *acceleration* available to reach that velocity — never
## the velocity already possessed (PHYS-003). Updates stability from how
## violently the body is changing motion.
##
## Intent arrives in duel axes — `+y` closes on the opponent, `+x` orbits
## right — and is rotated into world space here (COMBAT §25.1). A duel is
## fought along the line between two people, so that is the axis the controls
## have to mean; world-axis footwork would make the same key press advance,
## retreat, or sidestep depending on where the pair happened to drift.
##
## Implements: /spec/invariants.md#phys-003
## Implements: /spec/invariants.md#move-001
## See also: /docs/concepts/combat.md


## Advance one fighter's footwork. Returns the burst this tick launched, or
## `BurstKind.NONE`, so the caller can report it without this system knowing
## about events. `capability` scales every motor force (PHYS-003).
## If `scratch` is provided, writes motor exertion (F·v work + utilization).

static func step(
	fighter: FighterState, opponent: FighterState, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition, capability: float = 1.0, scratch: FighterTickScratch = null
) -> MovementGestureState.BurstKind:
	var dt := SimulationTimebase.TICK_SECONDS
	var forward := DuelGeometry.duel_basis(fighter, opponent, fighter.duel_forward_x, fighter.duel_forward_y)
	fighter.duel_forward_x = forward[0]
	fighter.duel_forward_y = forward[1]
	var launched := _recognize(fighter, intent_x, intent_y, tick, definition)
	var world := DuelGeometry.to_world(intent_x, intent_y, forward[0], forward[1])
	var ix := world[0]
	var iy := world[1]
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
	## The target is what the fighter is asking for; commitment is spent below,
	## on how fast they are allowed to approach it (PHYS-003).
	var target_vx := ix * top_speed
	var target_vy := iy * top_speed
	var accel := 0.0
	var gesture := fighter.gesture
	if gesture.is_bursting():
		## A burst is an extra drive along the heading it committed to, not a
		## rail. The heading never bends — a forward dash must not curve after
		## an opponent who circles away — but the fighter keeps their feet, so
		## they can lean out of a dash while it carries them.
		##
		## This matters beyond feel. A burst that replaced intent outright
		## would punish whoever changes their mind most often, which made a
		## faster-reacting CPU measurably *worse* than a slower one. Reacting
		## faster must never cost you anything.
		var burst_speed := definition.burst_speed(gesture.burst_kind) * CommitmentModel.translation_multiplier(fighter, definition)
		target_vx += gesture.burst_dir_x * burst_speed
		target_vy += gesture.burst_dir_y * burst_speed
		var asking := SimMath.length(target_vx, target_vy)
		if asking > burst_speed:
			target_vx *= burst_speed / asking
			target_vy *= burst_speed / asking
		accel = definition.burst_accel() * capability
		gesture.burst_ticks_remaining -= 1
		if gesture.burst_ticks_remaining <= 0:
			gesture.end_burst()
	var delta_vx := target_vx - fighter.vx
	var delta_vy := target_vy - fighter.vy
	var delta := SimMath.length(delta_vx, delta_vy)
	if accel <= 0.0:
		var braking := (
			target_vx * fighter.vx + target_vy * fighter.vy < 0.0
			or SimMath.length(target_vx, target_vy) < fighter.speed()
		)
		accel = (definition.brake_accel() if braking else definition.move_accel()) * capability
	## Commitment is spent on acceleration here too (PHYS-003): a burst during
	## a committed swing is as sluggish as any other repositioning, so a dash
	## is never a way out of a swing you already paid for.
	var max_delta := accel * CommitmentModel.move_authority(fighter, definition) * dt
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
	fighter.ax = (fighter.vx - old_vx) / dt
	fighter.ay = (fighter.vy - old_vy) / dt
	if scratch != null:
		_record_movement_exertion(scratch, definition, old_vx, old_vy, fighter.vx, fighter.vy, fighter.ax, fighter.ay, accel, capability, dt)
		scratch.burst_active = fighter.gesture.is_bursting()
	_update_stability(fighter, definition)
	return launched


## Record the movement motor's actual physical exertion into the tick scratch.
## Dynamic work = F_applied · v_mid × dt. Utilization = how much of the raw
## motor capacity (before capability scaling) was demanded. Computed from the
## motor's own output — never reconstructed from Δv by an external observer.
static func _record_movement_exertion(scratch: FighterTickScratch, definition: FighterDefinition, old_vx: float, old_vy: float, new_vx: float, new_vy: float, ax: float, ay: float, accel: float, capability: float, dt: float) -> void:
	var accel_magnitude := SimMath.length(ax, ay)
	if accel_magnitude < SimMath.EPSILON:
		return
	var applied_force := definition.mass * accel_magnitude
	var mid_vx := (old_vx + new_vx) * 0.5
	var mid_vy := (old_vy + new_vy) * 0.5
	var force_dir_x := ax / accel_magnitude
	var force_dir_y := ay / accel_magnitude
	var power := applied_force * (force_dir_x * mid_vx + force_dir_y * mid_vy)
	scratch.movement_positive_work += maxf(power * dt, 0.0)
	scratch.movement_braking_work += maxf(-power * dt, 0.0)
	var raw_motor := accel / capability * dt if capability > SimMath.EPSILON else 0.0
	scratch.movement_utilization = SimMath.clamp01(accel_magnitude * dt / raw_motor) if raw_motor > SimMath.EPSILON else 0.0


## Read the command stream for a double tap and arm the burst it earns.
##
## A burst already running is never re-armed: the heading is frozen at
## activation so a forward dash cannot bend after an opponent who circles away
## mid-dash.
static func _recognize(
	fighter: FighterState, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition
) -> MovementGestureState.BurstKind:
	var gesture := fighter.gesture
	var launched := DirectionalTapRecognizer.observe(gesture, intent_x, intent_y, tick, definition)
	if launched == MovementGestureState.BurstKind.NONE or gesture.is_bursting():
		return MovementGestureState.BurstKind.NONE
	var heading := DirectionalTapRecognizer.heading(fighter, launched)
	gesture.mode = MovementGestureState.Mode.BURST
	gesture.burst_kind = launched
	gesture.burst_ticks_remaining = definition.burst_ticks
	gesture.burst_dir_x = heading[0]
	gesture.burst_dir_y = heading[1]
	return launched


## Planted bodies transfer force best (COMBAT §36): violent acceleration and
## fast turning lower B toward its floor; staggered fighters sit at the floor.
static func _update_stability(fighter: FighterState, definition: FighterDefinition) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var accel_norm := SimMath.clamp01(fighter.acceleration() / definition.brake_accel())
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
##
## A coasting fighter has no footwork authority, so any gesture in progress is
## dropped rather than left frozen to resume later.
static func coast(fighter: FighterState, definition: FighterDefinition) -> void:
	fighter.gesture.reset()
	var dt := SimulationTimebase.TICK_SECONDS
	var old_vx := fighter.vx
	var old_vy := fighter.vy
	var current := fighter.speed()
	if current > SimMath.EPSILON:
		var scale := maxf(current - definition.brake_accel() * dt, 0.0) / current
		fighter.vx *= scale
		fighter.vy *= scale
	fighter.ax = (fighter.vx - old_vx) / dt
	fighter.ay = (fighter.vy - old_vy) / dt
	fighter.x += fighter.vx * dt
	fighter.y += fighter.vy * dt
	fighter.turn_rate = SimMath.approach(fighter.turn_rate, 0.0, definition.turn_accel() * dt)
	fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
