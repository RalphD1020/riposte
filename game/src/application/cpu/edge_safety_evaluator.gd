class_name EdgeSafetyEvaluator
extends RefCounted

## Pure predictive containment for CPU movement candidates. Evaluates whether
## a candidate command (walk direction or burst) would carry the fighter past
## the platform edge over a dynamic prediction horizon.
##
## Uses the real motor laws: locomotion_force/mass, burst_force/mass,
## burst_speed, capability scaling from stamina/health. The rollout is a
## lightweight position/velocity integration — the same equations as
## MovementSystem.step, without mutating authoritative state.
##
## Knows nothing about CPU difficulty. The safety filter is identical for all
## profiles; difficulty changes tactical judgment, never the safety layer.
##
## See also: /docs/concepts/cpu.md


## Walking prediction horizon (ticks). A short walk prediction is enough
## because walk speed is low and the fighter can reverse at any time.
const WALK_HORIZON_TICKS := 10

## Extra braking ticks added to burst predictions. After the burst ends,
## the fighter coasts/brakes for this many ticks before the horizon closes.
const BRAKE_MARGIN_TICKS := 4


## Evaluate whether a walk in the given duel-axis direction would carry the
## fighter off the platform. `intent_x` and `intent_y` are in duel axes
## (same as CpuController._steer output). Returns an EdgeSafetyResult.
static func evaluate_walk(
	fighter: FighterState,
	intent_x: float, intent_y: float,
	rules: DuelRules,
	capability: float,
) -> EdgeSafetyResult:
	var def := rules.fighter
	var dt := SimulationTimebase.TICK_SECONDS
	var fx := fighter.duel_forward_x
	var fy := fighter.duel_forward_y
	var world := DuelGeometry.to_world(intent_x, intent_y, fx, fy)
	var ix := world[0]
	var iy := world[1]
	var mag := SimMath.length(ix, iy)
	if mag > 1.0:
		ix /= mag
		iy /= mag
		mag = 1.0
	var dir_mult := _direction_multiplier(ix, iy, mag, fighter.facing, def)
	var top_speed := def.max_speed * dir_mult
	var target_vx := ix * top_speed
	var target_vy := iy * top_speed
	var move_accel := def.move_accel() * capability
	var brake_accel := def.brake_accel() * capability
	return _rollout(
		fighter.x, fighter.y, fighter.vx, fighter.vy,
		target_vx, target_vy, move_accel, brake_accel,
		WALK_HORIZON_TICKS, WALK_HORIZON_TICKS, dt, rules.platform_radius,
	)


## Evaluate whether a burst in the given direction would carry the fighter
## off the platform. `burst_kind` is the BurstKind enum. Returns an
## EdgeSafetyResult.
static func evaluate_burst(
	fighter: FighterState,
	burst_kind: MovementGestureState.BurstKind,
	rules: DuelRules,
	capability: float,
) -> EdgeSafetyResult:
	var def := rules.fighter
	var dt := SimulationTimebase.TICK_SECONDS
	var heading := DirectionalTapRecognizer.heading(fighter, burst_kind)
	var burst_speed := def.burst_speed(burst_kind)
	var burst_accel := def.burst_accel() * capability
	var brake_accel := def.brake_accel() * capability
	var ticks := def.burst_ticks
	var target_vx := heading[0] * burst_speed
	var target_vy := heading[1] * burst_speed
	return _rollout(
		fighter.x, fighter.y, fighter.vx, fighter.vy,
		target_vx, target_vy, burst_accel, brake_accel,
		ticks + BRAKE_MARGIN_TICKS, ticks, dt, rules.platform_radius,
	)


## Forward-integrate position/velocity for `horizon` ticks. During the first
## `drive_ticks`, the motor drives toward `target_v`; after that it brakes.
## Mirrors MovementSystem.step physics (F=ma, velocity clamped by accel budget).
static func _rollout(
	px: float, py: float, vx: float, vy: float,
	target_vx: float, target_vy: float,
	drive_accel: float, brake_accel: float,
	horizon: int, drive_ticks: int,
	dt: float, platform_radius: float,
) -> EdgeSafetyResult:
	var result := EdgeSafetyResult.new()
	var worst_dist_sq := px * px + py * py
	var worst_vr := _radial_outward_speed(px, py, vx, vy)
	var worst_accel := brake_accel
	var radius_sq := platform_radius * platform_radius
	for tick in horizon:
		var tvx := target_vx if tick < drive_ticks else 0.0
		var tvy := target_vy if tick < drive_ticks else 0.0
		var accel := drive_accel if tick < drive_ticks else brake_accel
		var dvx := tvx - vx
		var dvy := tvy - vy
		var delta := SimMath.length(dvx, dvy)
		var max_delta := accel * dt
		if delta <= max_delta:
			vx = tvx
			vy = tvy
		elif delta > SimMath.EPSILON:
			vx += dvx / delta * max_delta
			vy += dvy / delta * max_delta
		px += vx * dt
		py += vy * dt
		var dist_sq := px * px + py * py
		if dist_sq > worst_dist_sq:
			worst_dist_sq = dist_sq
			worst_vr = _radial_outward_speed(px, py, vx, vy)
			worst_accel = brake_accel
		if dist_sq >= radius_sq:
			result.crosses_platform = true
	var max_radius := sqrt(worst_dist_sq)
	result.min_clearance = platform_radius - max_radius
	if worst_vr > 0.0 and worst_accel > SimMath.EPSILON:
		result.stopping_margin = worst_vr * worst_vr / (2.0 * worst_accel)
	else:
		result.stopping_margin = 0.0
	result.recoverable = not result.crosses_platform and result.stopping_margin < result.min_clearance
	return result


## Outward radial speed: projection of velocity onto the position unit vector.
## Positive means moving away from center.
static func _radial_outward_speed(px: float, py: float, vx: float, vy: float) -> float:
	var r := SimMath.length(px, py)
	if r < SimMath.EPSILON:
		return 0.0
	return (px * vx + py * vy) / r


## Direction multiplier matching MovementSystem's forward/lateral/backward blend.
static func _direction_multiplier(ix: float, iy: float, mag: float, facing: float, def: FighterDefinition) -> float:
	if mag <= 0.0:
		return 1.0
	var alignment := (ix * SimMath.cosine(facing) + iy * SimMath.sine(facing)) / mag
	if alignment >= 0.0:
		return SimMath.mix(def.speed_lateral, def.speed_forward, alignment)
	return SimMath.mix(def.speed_lateral, def.speed_backward, -alignment)
