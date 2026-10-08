class_name SnapshotProjector
extends RefCounted

## The single boundary where presentation reads authoritative state: copies a
## MatchState into an immutable PresentationSnapshot once per tick.
##
## See also: /docs/concepts/presentation.md


static func project(state: MatchState, rules: DuelRules) -> PresentationSnapshot:
	var snapshot := PresentationSnapshot.new()
	snapshot.tick = state.tick
	snapshot.phase = state.phase
	snapshot.phase_ticks = state.phase_ticks
	snapshot.round_number = state.round_number
	snapshot.rounds_to_win = rules.rounds_to_win
	snapshot.scores = state.scores.duplicate()
	snapshot.round_winner = state.round_winner
	snapshot.match_winner = state.match_winner
	snapshot.end_reason = state.end_reason
	snapshot.intro_ticks = rules.intro_ticks
	snapshot.spawn_offset = rules.spawn_offset
	snapshot.time_left_ticks = maxi(rules.round_time_limit_ticks - state.round_ticks, 0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	snapshot.distance = DuelGeometry.distance(a, b)
	snapshot.closing_speed = DuelGeometry.closing_speed(a, b)
	snapshot.orbit_rate = DuelGeometry.orbit_rate(a, b)
	for slot in 2:
		snapshot.fighters.append(_fighter(state.fighter(slot), state.opponent_of(slot), rules))
	return snapshot


static func _fighter(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> PresentationFighter:
	var row := PresentationFighter.new()
	var weapon := fighter.weapon
	row.slot = fighter.slot
	row.side = fighter.side
	row.x = fighter.x
	row.y = fighter.y
	row.facing = fighter.facing
	row.blade_angle = DuelGeometry.blade_angle(fighter)
	row.weapon_angle = weapon.angle
	row.vx = fighter.vx
	row.vy = fighter.vy
	row.blade_speed = absf(fighter.turn_rate + weapon.speed)
	row.tip_speed = SwingSemantics.tip_speed(fighter, rules.weapon)
	row.swing_dir = signf(fighter.turn_rate + weapon.speed) if absf(fighter.turn_rate + weapon.speed) > 0.0 else weapon.swing_dir
	row.charge = weapon.charge
	row.launch_readiness = weapon.launch_readiness
	row.swing_progress = SwingSemantics.phase_progress(weapon)
	row.swing_potential = SwingSemantics.potential(
		row.tip_speed, weapon.launch_readiness, fighter.stability, weapon.phase, rules.weapon
	)
	row.phase = weapon.phase
	row.commitment = weapon.commitment
	row.stability = fighter.stability
	## Each fighter's *own* exposure, projected for them rather than against
	## their opponent's swing: vulnerability is a physical state a player can
	## read off a body, not a prediction about an attack that has not happened.
	row.exposure = SwingSemantics.exposure_fraction(DamageModel.exposure(fighter, opponent, rules), rules.combat)
	row.facing_error = DuelGeometry.facing_error(fighter, opponent)
	row.stable_side = weapon.stable_side
	row.guard_region = GuardRegion.of(weapon.angle, rules.weapon.guard_angle)
	row.burst = fighter.gesture.burst_kind
	row.health = fighter.health
	row.max_health = rules.fighter.max_health
	row.stamina = fighter.stamina
	row.stamina_max = StaminaModel.max_for_health(fighter.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat)
	row.capability = CapabilityModel.resolve_weapon(fighter.health, rules.fighter.max_health, fighter.stamina, row.stamina_max, rules.combat)
	row.condition = FighterCondition.classify(fighter.health, rules.fighter.max_health)
	row.body_radius = rules.fighter.body_radius
	row.is_falling = fighter.is_falling
	row.hilt_radius = rules.weapon.hilt_radius
	row.tip_radius = rules.weapon.tip_radius
	row.threat_time = InitiativeModel.time_to_threat(fighter, opponent, rules)
	## Combat readability state (Phase 9): normalized 0-1 derived quantities.
	row.recovery_remaining01 = _recovery_remaining(weapon)
	row.stamina01 = fighter.stamina / StaminaModel.max_for_health(fighter.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat) if row.stamina_max > 0.0 else 0.0
	row.point_threat01 = _point_threat(fighter, opponent, rules)
	row.movement_speed01 = SimMath.clamp01(SimMath.length(fighter.vx, fighter.vy) / rules.fighter.max_speed) if rules.fighter.max_speed > 0.0 else 0.0
	row.burst01 = 1.0 if fighter.gesture.burst_kind != MovementGestureState.BurstKind.NONE else 0.0
	return row


## Recovery remaining as a fraction: 1.0 = just entered recovery, 0.0 = done.
## Uses weapon.recovery_ticks (the assigned total) as the denominator, so the
## reading is a true normalized fraction. OVERSWING = 1.0 (maximum remaining;
## hasn't started recovery yet).
static func _recovery_remaining(weapon: WeaponState) -> float:
	if weapon.phase == CombatPhase.Id.OVERSWING:
		return 1.0
	if weapon.phase == CombatPhase.Id.RECOVERY and weapon.recovery_ticks > 0:
		return SimMath.clamp01(float(weapon.recovery_left) / float(weapon.recovery_ticks))
	return 0.0


## Physics-derived point threat using the same tip-velocity kinematics as
## ImpactModel (PHYS-007): v_tip = v_fighter + omega_total × r_tip, then
## project onto the blade axis (thrust_alignment) and toward the opponent
## (incidence). This replaces the earlier heuristic that used body closing
## speed + blade alignment, which did not capture rotational tip motion.
static func _point_threat(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	var dx := opponent.x - fighter.x
	var dy := opponent.y - fighter.y
	var dist := SimMath.length(dx, dy)
	if dist < SimMath.EPSILON:
		return 0.0
	## Tip position relative to fighter pivot.
	var blade_global := SimMath.wrap_angle(fighter.facing + fighter.weapon.angle)
	var blade_ax := cos(blade_global)
	var blade_ay := sin(blade_global)
	var tip_rx := blade_ax * rules.weapon.tip_radius
	var tip_ry := blade_ay * rules.weapon.tip_radius
	## Tip velocity: v_fighter + omega_total × r_tip (same as ImpactModel).
	var omega := fighter.turn_rate + fighter.weapon.speed
	var tip_vx := fighter.vx - omega * tip_ry
	var tip_vy := fighter.vy + omega * tip_rx
	## Relative tip velocity vs opponent body.
	var rel_vx := tip_vx - opponent.vx
	var rel_vy := tip_vy - opponent.vy
	var rel_speed := SimMath.length(rel_vx, rel_vy)
	if rel_speed < SimMath.EPSILON:
		return 0.0
	## Axial speed: relative velocity projected along blade axis toward target.
	var axial_speed := maxf(0.0, rel_vx * blade_ax + rel_vy * blade_ay)
	## Thrust alignment: fraction of relative motion that is axial (same as ImpactModel).
	var thrust_alignment := axial_speed / rel_speed
	## Incidence: how directly the blade points toward the opponent center.
	var toward_x := dx / dist
	var toward_y := dy / dist
	var incidence := maxf(0.0, blade_ax * toward_x + blade_ay * toward_y)
	## Axial closing speed toward opponent, normalized against reference.
	var axial_closing := maxf(0.0, rel_vx * toward_x + rel_vy * toward_y)
	var reference_speed := rules.fighter.max_speed if rules.fighter.max_speed > 0.0 else 1.0
	var speed_fraction := SimMath.clamp01(axial_closing / reference_speed)
	## Composite: zero unless blade is aimed at opponent AND tip is moving
	## axially AND actually closing. Matches combat classification conditions.
	return SimMath.clamp01(thrust_alignment * incidence * speed_fraction)
