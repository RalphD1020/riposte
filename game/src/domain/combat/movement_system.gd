class_name MovementSystem
extends RefCounted

## Footwork (COMBAT §23–§25, §36). Acceleration-limited movement toward the
## input's desired velocity: forward is fastest, backward slowest, and
## commitment cuts the *acceleration* available to reach that velocity — never
## the velocity already possessed (PHYS-003). Updates stability from how
## violently the body is changing motion.
##
## Intent arrives in the fighter's own combat frame (MOVEMENT-FRAME-001) —
## `+y` along the CombatHeading φ, `+x` to its right — and is rotated into
## world space here. φ is the centre of the weapon domain and the line the
## fighter is committed to, so footwork and sword share one frame: the target
## bearing τ only pulls φ round through the bounded heading motor, and a
## committed fighter keeps driving down its own line while the heading catches
## up. Footwork never homes on the opponent by itself.
##
## Implements: /spec/invariants.md#phys-003
## Implements: /spec/invariants.md#move-001
## Implements: /spec/invariants.md#movement-frame-001
## See also: /docs/concepts/combat.md


## Advance one fighter's footwork. Returns the burst this tick launched, or
## `BurstKind.NONE`, so the caller can report it without this system knowing
## about events. `condition` is the fighter's frozen condition this tick
## (CONDITION-001): its force scale reduces every footwork force, its speed
## scale every voluntary target speed; null is the healthy identity. Existing
## velocity is never rescaled (PHYS-003).

## Speeds this close (m/s) are one speed to the brake-or-drive choice: far
## below anything a body or a camera could show, far above rounding.
const SPEED_TIE := 1.0e-9


static func step(
	fighter: FighterState, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition, condition: ConditionState = null, dash_modifier: bool = false
) -> MovementGestureState.BurstKind:
	return step_in_frame(fighter, SimMath.heading_cosine(fighter.facing), SimMath.heading_sine(fighter.facing), intent_x, intent_y, tick, definition, condition, dash_modifier)


## `step` with the frame given: the duel reads every fighter's heading at the
## start of the tick, before any heading turns, so update order never decides
## which way a body was asked to go (FRICTION-ORDER-001).
static func step_in_frame(
	fighter: FighterState, forward_x: float, forward_y: float, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition, condition: ConditionState = null, dash_modifier: bool = false
) -> MovementGestureState.BurstKind:
	var dt := SimulationTimebase.TICK_SECONDS
	var force_scale := condition.force_scale if condition != null else 1.0
	var speed_scale := condition.speed_scale if condition != null else 1.0
	var forward := PackedFloat64Array([forward_x, forward_y])
	fighter.duel_forward_x = forward_x
	fighter.duel_forward_y = forward_y
	var launched := _recognize(fighter, intent_x, intent_y, tick, definition, dash_modifier, condition.can_dash if condition != null else true)
	var world := DuelGeometry.to_world(intent_x, intent_y, forward[0], forward[1])
	var ix := world[0]
	var iy := world[1]
	var magnitude := SimMath.length(ix, iy)
	if magnitude > 1.0:
		ix /= magnitude
		iy /= magnitude
		magnitude = 1.0
	var top_speed := definition.max_speed * speed_scale * stride_multiplier(intent_x, intent_y, definition) * CommitmentModel.translation_multiplier(fighter, definition)
	## The target is what the fighter is asking for; commitment is spent below,
	## on how fast they are allowed to approach it (PHYS-003).
	var target_vx := ix * top_speed
	var target_vy := iy * top_speed
	var accel := 0.0
	var gesture := fighter.gesture
	if gesture.is_bursting():
		var burst_speed := definition.burst_speed(gesture.burst_kind) * speed_scale * CommitmentModel.translation_multiplier(fighter, definition)
		if gesture.burst_kind == MovementGestureState.BurstKind.FORWARD_DASH:
			## Committed ballistic motion (MOVE-002). The burst velocity IS
			## the target — intent is not added. Zero steering authority: the
			## heading is world-space frozen at activation and cannot be altered.
			## Velocity is reached through finite burst_force acceleration,
			## never instantaneously assigned.
			target_vx = gesture.burst_dir_x * burst_speed
			target_vy = gesture.burst_dir_y * burst_speed
		else:
			## Back dash and lateral steps keep the additive model: the burst
			## heading supplements the fighter's own footwork intent.
			target_vx += gesture.burst_dir_x * burst_speed
			target_vy += gesture.burst_dir_y * burst_speed
			var asking := SimMath.length(target_vx, target_vy)
			if asking > burst_speed:
				target_vx *= burst_speed / asking
				target_vy *= burst_speed / asking
		accel = definition.burst_accel() * force_scale
		gesture.burst_ticks_remaining -= 1
		if gesture.burst_ticks_remaining <= 0:
			gesture.end_burst_into_recovery(definition.dash_recovery_ticks)
	elif gesture.is_recovering():
		## Recovery mode (MOVE-002): no burst speed. Normal locomotion
		## resumes but authority recovers progressively over the recovery
		## window. No special penalty — a miss naturally leaves the fighter
		## more exposed because nothing interrupted the committed motion.
		gesture.recovery_ticks_remaining -= 1
		if gesture.recovery_ticks_remaining <= 0:
			gesture._end_recovery()
	var delta_vx := target_vx - fighter.vx
	var delta_vy := target_vy - fighter.vy
	var delta := SimMath.length(delta_vx, delta_vy)
	if accel <= 0.0:
		## Braking is asking to go slower than one is going, or against the way
		## one is going. Both are read to within `SPEED_TIE`: turning at full
		## speed asks for the same speed, and a body at rest may carry a
		## velocity residue of a few ulps, which the two sides of a mirror
		## reach only to the last bit — neither is motion, so neither may
		## coin-flip the choice between two forces.
		var target_speed := SimMath.length(target_vx, target_vy)
		var braking := (
			target_vx * fighter.vx + target_vy * fighter.vy < -SPEED_TIE * target_speed
			or target_speed < fighter.speed() - SPEED_TIE
		)
		accel = (definition.brake_accel() if braking else definition.move_accel()) * force_scale
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
	_update_stability(fighter, definition)
	return launched


## The stride's share of top speed for frame-local intent: forward fastest,
## backward slowest, lateral between. It reads the intent's direction in the
## combat frame and nothing else, so walking down the heading costs and earns
## exactly what it did before the frame turned (NO-RUNNING-BONUS).
static func stride_multiplier(intent_x: float, intent_y: float, definition: FighterDefinition) -> float:
	var magnitude := SimMath.length(intent_x, intent_y)
	if magnitude <= 0.0:
		return 1.0
	var alignment := intent_y / magnitude
	if alignment >= 0.0:
		return SimMath.mix(definition.speed_lateral, definition.speed_forward, alignment)
	return SimMath.mix(definition.speed_lateral, definition.speed_backward, -alignment)


## Read the command stream for a double tap or dash modifier and arm the burst.
##
## A dash only starts if the fighter can pay for it (STAMINA-004, read from
## start-of-tick stamina). A refused dash is dropped, never buffered: the tap
## is still consumed by the recognizer, so it cannot fire later on its own.
##
## A burst already running is never re-armed: the heading is frozen at
## activation so a forward dash cannot bend after an opponent who circles away
## mid-dash.
static func _recognize(
	fighter: FighterState, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition, dash_modifier: bool = false, can_dash: bool = true
) -> MovementGestureState.BurstKind:
	var gesture := fighter.gesture
	## Dash modifier (accessibility): Shift+direction produces the same burst
	## as a double-tap. Same force, startup, duration, physics — no
	## gameplay advantage. Requires a clear directional intent and no burst
	## already in progress.
	if dash_modifier and can_dash and not gesture.is_bursting() and not gesture.is_recovering():
		var modifier_kind := _dash_modifier_direction(intent_x, intent_y, definition)
		if modifier_kind != MovementGestureState.BurstKind.NONE:
			gesture.clear_pending()
			var dash_heading := DirectionalTapRecognizer.heading(fighter, modifier_kind)
			gesture.mode = MovementGestureState.Mode.BURST
			gesture.burst_kind = modifier_kind
			gesture.burst_ticks_remaining = definition.burst_ticks
			gesture.burst_dir_x = dash_heading[0]
			gesture.burst_dir_y = dash_heading[1]
			return modifier_kind
	var launched := DirectionalTapRecognizer.observe(gesture, intent_x, intent_y, tick, definition)
	if launched == MovementGestureState.BurstKind.NONE or not can_dash or gesture.is_bursting() or gesture.is_recovering():
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
	fighter.facing = SimMath.compose_angle(fighter.facing, fighter.turn_rate * dt)


## Map held directional intent to a burst kind when the dash modifier is held.
## Uses the same sector thresholds as the tap recognizer (COMBAT §25.2).
static func _dash_modifier_direction(intent_x: float, intent_y: float, definition: FighterDefinition) -> MovementGestureState.BurstKind:
	var magnitude := SimMath.length(intent_x, intent_y)
	if magnitude < definition.burst_enter_deflection:
		return MovementGestureState.BurstKind.NONE
	if absf(intent_y) >= absf(intent_x):
		return MovementGestureState.BurstKind.FORWARD_DASH if intent_y > 0.0 else MovementGestureState.BurstKind.BACK_DASH
	return MovementGestureState.BurstKind.RIGHT_STEP if intent_x > 0.0 else MovementGestureState.BurstKind.LEFT_STEP
