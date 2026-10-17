class_name SnapshotProjector
extends RefCounted

## The single boundary where presentation reads authoritative state: copies a
## MatchState into an immutable PresentationSnapshot once per tick.
##
## See also: /docs/concepts/presentation.md


## `threat_readings` adds each fighter's threat time and exposure — two bounded
## predictions a tick, read today only by the debug overlay — so a frame that
## shows none of them does not pay for them; left out, `has_threat_readings` is
## false and both keep their neutral defaults (COMBAT-009: not projected,
## never invented).
static func project(state: MatchState, rules: DuelRules, threat_readings: bool = false) -> PresentationSnapshot:
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
	if state.phase != MatchPhase.Id.ROUND_INTRO and state.phase != MatchPhase.Id.ROUND_ACTIVE:
		snapshot.set_winner = MatchOutcome.set_winner(state.scores, state.round_number, rules)
	snapshot.intro_ticks = rules.intro_ticks
	snapshot.spawn_offset = rules.spawn_offset
	snapshot.reference_impulse = rules.combat.reference_impulse
	var contact := state.blade_contact
	if contact.phase == SwordContactSet.Phase.CONTACTING and contact.is_touching():
		snapshot.blade_contact_ticks = contact.phase_ticks
		snapshot.blade_contact_x = contact.point_x[0]
		snapshot.blade_contact_y = contact.point_y[0]
		for point in contact.point_count:
			snapshot.contacts.append(_contact(contact, point))
	snapshot.time_left_ticks = maxi(rules.round_time_limit_ticks - state.round_ticks, 0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	snapshot.distance = DuelGeometry.distance(a, b)
	snapshot.closing_speed = DuelGeometry.closing_speed(a, b)
	snapshot.orbit_rate = DuelGeometry.orbit_rate(a, b)
	## Each fighter's threat on the other, predicted once: both rows read the
	## same two (their threat time, and their exposure as the difference).
	snapshot.has_threat_readings = threat_readings
	var threat := PackedFloat64Array([0.0, 0.0])
	if threat_readings:
		threat[0] = InitiativeModel.time_to_threat(a, b, rules)
		threat[1] = InitiativeModel.time_to_threat(b, a, rules)
	for slot in 2:
		snapshot.fighters.append(_fighter(state.fighter(slot), state.opponent_of(slot), rules, threat[slot], threat[1 - slot], threat_readings))
	return snapshot


## A read-only copy of manifold point `point` (CONTACT-PRESENTATION-001). Its
## slip is the held record's reading at the same contact (the record is stored
## in row order, so it is found by the nearest place along the blades).
static func _contact(contact: SwordContactSet, point: int) -> PresentationContact:
	var row := PresentationContact.new()
	row.x = contact.point_x[point]
	row.y = contact.point_y[point]
	row.fraction_a = contact.fraction_a[point]
	row.fraction_b = contact.fraction_b[point]
	row.normal_x = contact.point_nx[point]
	row.normal_y = contact.point_ny[point]
	row.normal_impulse = contact.normal_impulse[point]
	row.tangent_impulse = contact.tangent_impulse[point]
	row.age = contact.age[point]
	row.contact_id = contact.contact_id[point]
	var nearest := INF
	for held in contact.hold_count():
		var moved := absf(contact.hold_fraction_a[held] - row.fraction_a) + absf(contact.hold_fraction_b[held] - row.fraction_b)
		if moved < nearest:
			nearest = moved
			row.slip = contact.hold_slip[held]
	return row


## `threat` is `fighter`'s time to threaten `opponent`, `threatened` the
## opponent's time to threaten `fighter` (`InitiativeModel.time_to_threat`);
## both 0 when the readings are not projected.
static func _fighter(fighter: FighterState, opponent: FighterState, rules: DuelRules, threat: float = 0.0, threatened: float = 0.0, readings: bool = false) -> PresentationFighter:
	var row := PresentationFighter.new()
	var weapon := fighter.weapon
	var spec := rules.spec_of(fighter)
	var body := spec.fighter
	row.slot = fighter.slot
	row.side = fighter.side
	row.x = fighter.x
	row.y = fighter.y
	row.facing = fighter.facing
	row.target_bearing = DuelGeometry.bearing(fighter, opponent)
	row.turn_authority = CommitmentModel.turn_torque_share(fighter, spec, ConditionModel.of(fighter, rules), rules.combat)
	row.blade_angle = DuelGeometry.blade_angle(fighter)
	row.weapon_angle = weapon.angle
	row.swing_end = weapon.swing_end
	row.vx = fighter.vx
	row.vy = fighter.vy
	row.blade_speed = absf(fighter.turn_rate + weapon.speed)
	row.tip_speed = SwingSemantics.tip_speed(fighter, spec)
	row.swing_dir = signf(fighter.turn_rate + weapon.speed) if absf(fighter.turn_rate + weapon.speed) > 0.0 else weapon.swing_dir
	row.cut_dir = weapon.swing_dir
	row.weapon_speed = weapon.speed
	row.charge = weapon.charge
	row.swing_charge = weapon.swing_charge
	row.launch_preparation = weapon.launch_preparation
	row.swing_progress = SwingSemantics.phase_progress(weapon)
	row.swing_potential = SwingSemantics.potential(
		row.tip_speed, weapon.launch_preparation, fighter.stability, weapon.phase, spec.weapon
	)
	row.phase = weapon.phase
	row.commitment = weapon.commitment
	row.stability = fighter.stability
	## Each fighter's *own* exposure, projected for them rather than against
	## their opponent's swing: vulnerability is a physical state a player can
	## read off a body, not a prediction about an attack that has not happened.
	row.exposure = ExposureModel.reading_of(threat - threatened, rules) if readings else 0.0
	row.facing_error = DuelGeometry.facing_error(fighter, opponent)
	row.stable_side = weapon.stable_side
	row.guard_region = GuardRegion.of(weapon.angle, spec.weapon.guard_angle)
	row.burst = fighter.gesture.burst_kind
	row.health = fighter.health
	row.max_health = body.max_health
	row.stamina = fighter.stamina
	row.dash_cost = rules.combat.stamina_dash_cost
	row.impact_authority = fighter.impact_authority
	var condition := ConditionModel.of(fighter, rules)
	row.force_scale = condition.force_scale
	row.speed_scale = condition.speed_scale
	row.tracking_scale = condition.tracking_scale
	row.condition = FighterCondition.classify(fighter.health, body.max_health)
	row.push_radius = body.push_radius
	row.is_falling = fighter.is_falling
	row.terminal_cause = fighter.terminal_kind()
	row.body_lying = fighter.fallen.is_lying()
	row.body_yaw = fighter.fallen.yaw
	row.body_spin = fighter.fallen.spin
	row.body_over_edge = fighter.fallen.over_edge
	row.blade_base_radius = spec.weapon.blade_base_radius
	row.tip_radius = spec.weapon.tip_radius
	row.weapon_definition = spec.weapon
	row.combatant_spec = spec
	var tip := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	WeaponKinematics.velocity_into(fighter, tip, tip.point_x(spec.weapon.tip_radius), tip.point_y(spec.weapon.tip_radius))
	row.tip_vx = tip.vx
	row.tip_vy = tip.vy
	row.weapon_mass = spec.weapon.mass
	row.threat_time = threat
	## Combat readability state (Phase 9): normalized 0-1 derived quantities.
	row.recovery_remaining01 = _recovery_remaining(weapon)
	row.point_threat01 = _point_threat(fighter, opponent, rules)
	row.movement_speed01 = SimMath.clamp01(SimMath.length(fighter.vx, fighter.vy) / body.max_speed) if body.max_speed > 0.0 else 0.0
	row.burst01 = 1.0 if fighter.gesture.burst_kind != MovementGestureState.BurstKind.NONE else 0.0
	return row


## Recovery remaining as a fraction: 1.0 = just entered recovery, 0.0 = done.
## OVERSWING = 1.0 (maximum remaining; hasn't started recovery yet).
static func _recovery_remaining(weapon: WeaponState) -> float:
	if weapon.phase == CombatPhase.Id.OVERSWING:
		return 1.0
	if weapon.phase != CombatPhase.Id.RECOVERY:
		return 0.0
	## Recovery ends on a physical gate, not a timer (RECOVERY-001), so the
	## reading is the domain's own decay of the commitment the blade carried
	## in — the floor or the blade's remaining speed, whichever is more.
	if weapon.recovery_commitment > 0.0:
		return SimMath.clamp01(weapon.commitment / weapon.recovery_commitment)
	if weapon.recovery_ticks > 0:
		return SimMath.clamp01(float(weapon.recovery_left) / float(weapon.recovery_ticks))
	return 0.0


## Physics-derived point threat using the same tip-velocity kinematics as
## ImpactModel (PHYS-007, `WeaponKinematics`), then projected onto the blade
## axis (thrust_alignment) and toward the opponent (incidence). This replaces
## the earlier heuristic that used body closing speed + blade alignment, which
## did not capture rotational tip motion.
static func _point_threat(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	var dx := opponent.x - fighter.x
	var dy := opponent.y - fighter.y
	var dist := SimMath.length(dx, dy)
	if dist < SimMath.EPSILON:
		return 0.0
	var spec := rules.spec_of(fighter)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var blade_ax := pose.ux
	var blade_ay := pose.uy
	WeaponKinematics.velocity_into(fighter, pose, pose.point_x(spec.weapon.tip_radius), pose.point_y(spec.weapon.tip_radius))
	## Relative tip velocity vs opponent body.
	var rel_vx := pose.vx - opponent.vx
	var rel_vy := pose.vy - opponent.vy
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
	var reference_speed := spec.fighter.max_speed if spec.fighter.max_speed > 0.0 else 1.0
	var speed_fraction := SimMath.clamp01(axial_closing / reference_speed)
	## Composite: zero unless blade is aimed at opponent AND tip is moving
	## axially AND actually closing. Matches combat classification conditions.
	return SimMath.clamp01(thrust_alignment * incidence * speed_fraction)
