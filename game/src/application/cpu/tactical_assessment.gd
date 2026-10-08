class_name TacticalAssessment
extends RefCounted

## Compact tactical state derived from CpuObservation and own fighter state.
## One evaluator across all difficulties (CPU-004): the assessment is the same
## pure function; profiles weight how much each signal matters.
##
## See also: /docs/concepts/cpu.md

## Burst evaluation indices: one score per direction.
const BURST_FORWARD := 0
const BURST_BACKWARD := 1
const BURST_CLOCKWISE := 2
const BURST_COUNTERCLOCKWISE := 3
const BURST_COUNT := 4

## How close the perceived distance is to the preferred range, [0, 1].
var measure_quality: float = 0.0
## Time differential (seconds). Positive = own fighter threatens first.
var initiative: float = 0.0
## Opponent in recovery/overswing and we can arrive in time, [0, 1].
var tempo_opportunity: float = 0.0
## Opponent committed (LAUNCH/swinging) and own tap can intercept, [0, 1].
var indes_opportunity: float = 0.0
## Own blade alignment toward opponent center, [0, 1].
var line_advantage: float = 0.0
## How pressed the opponent is relative to own edge distance, [-1, 1].
## Positive = opponent is closer to the wall.
var arena_pressure: float = 0.0
## Opponent commitment from the observation.
var opponent_commitment: float = 0.0
## Urgency to withdraw after own committed attack, [0, 1].
var withdrawal_urge: float = 0.0
## Own stamina depletion [0, 1]. 0 = full, 1 = empty. Scaled by profile's
## stamina_cost_weight to penalize costly actions when exhausted.
var stamina_depletion: float = 0.0
## Utility scores for all 4 burst directions.
var burst_scores: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Own distance to the platform edge (m). Higher = safer.
var edge_clearance: float = 0.0
## Radial component of own velocity (m/s). Positive = moving toward edge.
var outward_radial_speed: float = 0.0
## Stopping distance at current outward speed: v_r² / (2 × a_inward).
var stopping_margin: float = 0.0
## Opponent's distance to the platform edge (m).
var opponent_edge_clearance: float = 0.0
## Positional edge advantage: opponent_pressure - own_pressure. Positive =
## opponent is closer to the cliff.
var edge_position_advantage: float = 0.0
## Body contact push awareness (CPU-007). Derived from the solved constraint
## impulse, not from hidden opponent motor intent.
var body_contact_active: bool = false
## Push pressure = J_constraint / dt, signed so positive = toward own edge.
var push_pressure: float = 0.0
## True when push pressure toward own edge exceeds a threshold.
var being_displaced: bool = false
## Estimated ticks until pushed off the platform at the current displacement
## rate. INT32_MAX when not being displaced.
var time_to_support_loss: int = 2147483647


static func evaluate(
	seen: CpuObservation,
	me: FighterState,
	perceived_distance: float,
	reach: float,
	rules: DuelRules,
	profile: CpuProfile,
	body_contact: BodyContactState = null,
) -> TacticalAssessment:
	var assessment := TacticalAssessment.new()
	var desired := profile.tap_range if WeaponSystem.can_start_attack(me, rules.weapon) else profile.engage_range
	assessment.measure_quality = SimMath.clamp01(1.0 - absf(perceived_distance - desired) / CpuController.APPROACH_RAMP)
	assessment.initiative = seen.opp_threat_time - seen.my_threat_time
	assessment.opponent_commitment = seen.opp_commitment
	_assess_tempo(assessment, seen, perceived_distance, reach, rules)
	_assess_indes(assessment, seen)
	_assess_line(assessment, seen, me)
	_assess_arena(assessment, seen, me, rules)
	_assess_withdrawal(assessment, me)
	_assess_stamina(assessment, me, rules)
	_assess_push(assessment, me, rules, body_contact)
	_evaluate_bursts(assessment, seen, me, perceived_distance, reach, desired, rules, profile)
	return assessment


static func _assess_tempo(assessment: TacticalAssessment, seen: CpuObservation, perceived_distance: float, reach: float, rules: DuelRules) -> void:
	if seen.opp_phase != CombatPhase.Id.RECOVERY and seen.opp_phase != CombatPhase.Id.OVERSWING:
		return
	var gap := maxf(0.0, perceived_distance - reach)
	var close_time := gap / maxf(rules.fighter.max_speed, SimMath.EPSILON)
	var window := maxf(seen.opp_threat_time, SimMath.EPSILON)
	assessment.tempo_opportunity = SimMath.clamp01(1.0 - close_time / window)


static func _assess_indes(assessment: TacticalAssessment, seen: CpuObservation) -> void:
	var committed := seen.opp_phase == CombatPhase.Id.LAUNCH or CombatPhase.is_swinging(seen.opp_phase)
	if committed and assessment.initiative > 0.0:
		assessment.indes_opportunity = SimMath.clamp01(assessment.initiative / CpuController.INITIATIVE_FULL)


static func _assess_line(assessment: TacticalAssessment, seen: CpuObservation, me: FighterState) -> void:
	var dx := seen.opp_x - me.x
	var dy := seen.opp_y - me.y
	var dist := SimMath.length(dx, dy)
	if dist <= SimMath.EPSILON:
		return
	var blade_angle := DuelGeometry.blade_angle(me)
	var blade_x := SimMath.cosine(blade_angle)
	var blade_y := SimMath.sine(blade_angle)
	assessment.line_advantage = maxf(0.0, blade_x * dx / dist + blade_y * dy / dist)


static func _assess_arena(assessment: TacticalAssessment, seen: CpuObservation, me: FighterState, rules: DuelRules) -> void:
	if rules.platform_radius <= SimMath.EPSILON:
		return
	var my_dist := SimMath.length(me.x, me.y)
	var opp_dist := SimMath.length(seen.opp_x, seen.opp_y)
	assessment.arena_pressure = (opp_dist - my_dist) / rules.platform_radius
	assessment.edge_clearance = rules.platform_radius - my_dist
	assessment.opponent_edge_clearance = rules.platform_radius - opp_dist
	var my_r := my_dist
	var opp_r := opp_dist
	var my_pressure := SimMath.clamp01(1.0 - my_r / rules.platform_radius) if rules.platform_radius > SimMath.EPSILON else 0.0
	var opp_pressure := SimMath.clamp01(1.0 - opp_r / rules.platform_radius) if rules.platform_radius > SimMath.EPSILON else 0.0
	assessment.edge_position_advantage = opp_pressure - my_pressure
	if my_dist > SimMath.EPSILON:
		assessment.outward_radial_speed = (me.x * me.vx + me.y * me.vy) / my_dist
	var brake_accel := rules.fighter.brake_accel()
	if assessment.outward_radial_speed > 0.0 and brake_accel > SimMath.EPSILON:
		assessment.stopping_margin = assessment.outward_radial_speed * assessment.outward_radial_speed / (2.0 * brake_accel)


static func _assess_withdrawal(assessment: TacticalAssessment, me: FighterState) -> void:
	var own_committed := (
		CombatPhase.is_swinging(me.weapon.phase)
		or me.weapon.phase == CombatPhase.Id.OVERSWING
		or me.weapon.phase == CombatPhase.Id.RECOVERY
	)
	if own_committed:
		assessment.withdrawal_urge = SimMath.clamp01(me.weapon.commitment + (1.0 - me.stability))


static func _assess_stamina(assessment: TacticalAssessment, me: FighterState, rules: DuelRules) -> void:
	var max_stamina := StaminaModel.max_for_health(me.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat)
	if max_stamina <= SimMath.EPSILON:
		assessment.stamina_depletion = 1.0
		return
	assessment.stamina_depletion = SimMath.clamp01(1.0 - me.stamina / max_stamina)


## Push-pressure awareness (CPU-007). Reads the solved constraint impulse from
## the body contact state — observable physics, not hidden opponent intent.
## Positive push_pressure means the CPU is being pushed toward its own edge.
static func _assess_push(assessment: TacticalAssessment, me: FighterState, rules: DuelRules, body_contact: BodyContactState) -> void:
	if body_contact == null or body_contact.phase != BodyContactState.Phase.CONTACTING:
		return
	assessment.body_contact_active = true
	var dt := SimulationTimebase.TICK_SECONDS
	if dt <= SimMath.EPSILON:
		return
	## The constraint normal points from fighter 0 toward fighter 1. Fighter 0
	## receives impulse in the −n direction, fighter 1 in the +n direction.
	var push_sign := -1.0 if me.slot == 0 else 1.0
	var push_dir_x := push_sign * body_contact.last_constraint_normal_x
	var push_dir_y := push_sign * body_contact.last_constraint_normal_y
	var force := body_contact.last_constraint_impulse / dt
	## Project the push direction onto the arena radial (from center to CPU).
	var my_r := SimMath.length(me.x, me.y)
	if my_r < SimMath.EPSILON:
		return
	var radial_x := me.x / my_r
	var radial_y := me.y / my_r
	var push_radial := (push_dir_x * radial_x + push_dir_y * radial_y) * force
	assessment.push_pressure = push_radial
	## Being displaced: pushed outward with significant force.
	var displacement_threshold := rules.fighter.mass * 2.0
	if push_radial > displacement_threshold:
		assessment.being_displaced = true
		## Time to support loss: edge_clearance / displacement_rate.
		var displacement_rate := push_radial / rules.fighter.mass * dt
		if displacement_rate > SimMath.EPSILON:
			var ticks := int(assessment.edge_clearance / displacement_rate)
			assessment.time_to_support_loss = clampi(ticks, 0, 2147483647)


## Score each burst direction: measure improvement, tactical gain, and edge
## risk. The formula is intentionally coarse — it picks which direction to
## dash, not how far the dash will carry.
static func _evaluate_bursts(
	assessment: TacticalAssessment,
	_seen: CpuObservation,
	me: FighterState,
	perceived_distance: float,
	_reach: float,
	desired: float,
	rules: DuelRules,
	profile: CpuProfile,
) -> void:
	var approach_ramp := CpuController.APPROACH_RAMP
	var burst_estimate := rules.fighter.burst_speed_axial * float(rules.fighter.burst_ticks) * SimulationTimebase.TICK_SECONDS
	var lateral_estimate := rules.fighter.burst_speed_lateral * float(rules.fighter.burst_ticks) * SimulationTimebase.TICK_SECONDS
	## Forward: closes distance. Good when approaching from outside.
	var fwd_dist := maxf(0.0, perceived_distance - burst_estimate)
	var fwd_measure := SimMath.clamp01(1.0 - absf(fwd_dist - desired) / approach_ramp)
	var fwd_edge := _edge_risk_axial(me, burst_estimate, rules)
	assessment.burst_scores[BURST_FORWARD] = fwd_measure + assessment.tempo_opportunity - fwd_edge
	## Backward: opens distance. Good when withdrawing or threatened.
	var back_dist := perceived_distance + burst_estimate
	var back_measure := SimMath.clamp01(1.0 - absf(back_dist - desired) / approach_ramp)
	var back_edge := _edge_risk_axial(me, -burst_estimate, rules)
	assessment.burst_scores[BURST_BACKWARD] = back_measure + assessment.withdrawal_urge - back_edge
	## Clockwise / counterclockwise: lateral repositioning. Good when
	## orbiting against a committed opponent or exploiting angles.
	var angle_gain := assessment.opponent_commitment * profile.angle_weight
	var cw_edge := _edge_risk_lateral(me, lateral_estimate, rules)
	var ccw_edge := _edge_risk_lateral(me, -lateral_estimate, rules)
	assessment.burst_scores[BURST_CLOCKWISE] = angle_gain * 0.8 - cw_edge
	assessment.burst_scores[BURST_COUNTERCLOCKWISE] = angle_gain * 0.8 - ccw_edge
	## Stamina cost penalty: motor-derived, same law for all directions (STAMINA-001).
	if profile.stamina_cost_weight > 0.0:
		var dt := SimulationTimebase.TICK_SECONDS
		var ticks := float(rules.fighter.burst_ticks)
		var ref := maxf(rules.combat.stamina_move_reference_work, SimMath.EPSILON)
		var axial_work := rules.fighter.burst_force * rules.fighter.burst_speed_axial * dt
		var lateral_work := rules.fighter.burst_force * rules.fighter.burst_speed_lateral * dt
		var axial_cost := (axial_work * ticks / ref) * assessment.stamina_depletion * profile.stamina_cost_weight
		var lateral_cost := (lateral_work * ticks / ref) * assessment.stamina_depletion * profile.stamina_cost_weight
		assessment.burst_scores[BURST_FORWARD] -= axial_cost
		assessment.burst_scores[BURST_BACKWARD] -= axial_cost
		assessment.burst_scores[BURST_CLOCKWISE] -= lateral_cost
		assessment.burst_scores[BURST_COUNTERCLOCKWISE] -= lateral_cost


## Estimated edge risk if the fighter moved `delta` along the duel forward axis.
static func _edge_risk_axial(me: FighterState, delta: float, rules: DuelRules) -> float:
	var post_x := me.x + me.duel_forward_x * delta
	var post_y := me.y + me.duel_forward_y * delta
	var edge_dist := rules.platform_radius - SimMath.length(post_x, post_y)
	return SimMath.clamp01(1.0 - edge_dist / CpuController.EDGE_MARGIN)


## Estimated edge risk for a lateral step. `delta` positive = to the right.
static func _edge_risk_lateral(me: FighterState, delta: float, rules: DuelRules) -> float:
	var right_x := me.duel_forward_y
	var right_y := -me.duel_forward_x
	var post_x := me.x + right_x * delta
	var post_y := me.y + right_y * delta
	var edge_dist := rules.platform_radius - SimMath.length(post_x, post_y)
	return SimMath.clamp01(1.0 - edge_dist / CpuController.EDGE_MARGIN)
