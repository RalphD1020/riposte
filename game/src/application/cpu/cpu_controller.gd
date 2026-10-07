class_name CpuController
extends FighterController

## Utility-scoring CPU (PLAN Phase 9). Emits the same PlayerCommand a human
## would and obeys exactly the same rules.
##
## Perception: the CPU feels its own body and weapon now (proprioception) but
## sees the opponent through a reaction-delay memory, extrapolated by the
## opponent's observed velocity in proportion to its anticipation skill.
## Decisions: at its cadence it scores footwork (approach to the range its
## weapon wants, retreat from threats, re-take measure when smothered, orbit
## against committed rotation, bait just outside reach) and attacks (taps for
## probes, punishes, and interceptions from good range; charges from outside
## measure). Standoff pressure builds until someone commits. All variety
## comes from SeededRng, so CPU play is reproducible per seed.
##
## The constants below are the heuristic's shape, shared by every
## difficulty; CpuProfile weights decide how much each term matters.
##
## Implements: /spec/invariants.md#cpu-001
## See also: /docs/concepts/cpu.md

enum Move { HOLD, APPROACH, RETREAT, ORBIT, BAIT }
enum Attack { NONE, TAP, HOLD }

const MEMORY_TICKS := 40
const HOLD_UTILITY := 0.15
const HOLD_LIMIT_EXTRA_TICKS := 40
## Ticks of standoff for pressure to reach its full weight.
const PRESSURE_TICKS := 150

## Threat reading: an opponent swinging, or charged past THREAT_CHARGE, within
## THREAT_RANGE (m) beyond reach.
const THREAT_CHARGE := 0.15
const THREAT_RANGE := 0.5
## A ready CPU closes to just past its tap range.
const READY_RANGE_LEAD := 0.05
## Distances (m) over which the approach, punish, and retreat urges ramp in.
const APPROACH_RAMP := 0.6
const PUNISH_REACH_SHARE := 0.8
const PUNISH_RAMP := 1.0
const RETREAT_RAMP := 0.8
## Closer than tap range by this much is smothered measure.
const SMOTHERED_MARGIN := 0.2
## Opponent threatening first by this much (s) within INITIATIVE_RANGE (m)
## beyond reach means step out.
const INITIATIVE_MARGIN := 0.05
const INITIATIVE_RANGE := 0.2
## Initiative (s) that earns full tap weight.
const INITIATIVE_FULL := 0.3
## Opening that earns full punish weight. A fighter in recovery with a
## committed blade reads around here, which is what "open" used to mean as a
## yes/no — the point of the reading is the gradient either side of it, not a
## different scale.
const OPENING_FULL := 0.6
## How far an opening may lean the charge draw toward full commitment.
const CHARGE_OPENING_LEAN := 0.35
## Orbit even a lightly committed swing at least this much.
const ORBIT_MIN_COMMITMENT := 0.4

## Attack choice: range tolerance (m) for taps and charges; taps need at
## least MIN_RANGE_QUALITY however tempting the opening.
const TAP_TOLERANCE := 0.4
const CHARGE_TOLERANCE := 0.6
const MIN_RANGE_QUALITY := 0.5
const CHARGE_PRESSURE_SHARE := 0.5
const OPEN_CHARGE_BOOST := 1.4
const THREATENED_CHARGE_DAMP := 0.3

## Steering: orbit is mostly tangential with a slight close-in; baiting
## hovers BAIT_MARGIN outside reach within ±BAIT_BAND.
const ORBIT_TANGENT := 0.9
const ORBIT_CLOSE := 0.2
const BAIT_MARGIN := 0.15
const BAIT_BAND := 0.12
const BAIT_STEP := 0.7
const BAIT_DRIFT := 0.4
## Within EDGE_MARGIN (m) of the boundary, steer back toward the center,
## fully by EDGE_RAMP further out.
const EDGE_MARGIN := 1.2
const EDGE_RAMP := 1.0

## A dash is not a CPU ability. The CPU types the gesture: full deflection,
## genuine rest, full deflection again, on its own command stream, and
## `DirectionalTapRecognizer` reads it exactly as it reads a thumb. There is
## no private dash call to make, which is the whole point — the CPU cannot
## reach a movement state a player cannot.
const BURST_SCRIPT: Array[float] = [1.0, 1.0, 0.0, 0.0, 1.0]
## Only dash when the footwork decision was decisive. Dashing out of an
## ambivalent step is how an opponent starts looking twitchy rather than sharp.
const BURST_UTILITY_MIN := 0.6

var profile: CpuProfile
## Tick of the observation the last decision used (proves perception delay).
var last_perceived_tick: int = -1
var _rules: DuelRules
var _rng: SeededRng
var _memory: Array[CpuObservation] = []
var _next_decision_tick: int = 0
var _move: Move = Move.APPROACH
var _orbit_sign: float = 1.0
var _attack: Attack = Attack.NONE
var _charge_target: float = 0.0
var _holding: bool = false
var _hold_ticks: int = 0
var _idle_ticks: int = 0
## Position in the dash gesture being typed, and which duel direction into.
var _burst_cursor: int = BURST_SCRIPT.size()
var _burst_sign: float = 0.0
## Whether the current burst is lateral (X axis) or axial (Y axis).
var _burst_is_lateral: bool = false
## Where the opponent is believed to be now, and how far from the CPU.
var _sight_x: float = 0.0
var _sight_y: float = 0.0
var _sight_distance: float = 0.0
## Decision traces (Phase 8a). Sidecar telemetry, never authoritative.
var traces: Array[CpuDecisionTrace] = []


static func create(rules: DuelRules, cpu_profile: CpuProfile, match_seed: int, slot: int) -> CpuController:
	var controller := CpuController.new()
	controller._rules = rules
	controller.profile = cpu_profile
	controller._rng = SeededRng.create(match_seed, SeededRng.cpu_stream(slot))
	return controller


func command_for(state: MatchState, slot: int) -> PlayerCommand:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		_forget()
		return PlayerCommand.idle(state.tick)
	var me := state.fighter(slot)
	_idle_ticks += 1
	_memory.append(CpuObservation.observe(state, slot, _rules))
	if _memory.size() > MEMORY_TICKS:
		_memory.remove_at(0)
	var seen := _memory[maxi(0, _memory.size() - 1 - profile.reaction_ticks)]
	_perceive(seen, me, state.tick)
	if state.tick >= _next_decision_tick:
		last_perceived_tick = seen.tick
		_decide(seen, me, state.tick)
		_next_decision_tick = state.tick + profile.decision_ticks + _rng.next_int(0, profile.decision_jitter)
	return _execute(state.tick, me)


func _forget() -> void:
	_memory.clear()
	_holding = false
	_hold_ticks = 0
	_attack = Attack.NONE
	_move = Move.APPROACH
	_idle_ticks = 0
	_next_decision_tick = 0
	_burst_cursor = BURST_SCRIPT.size()
	_burst_sign = 0.0
	_burst_is_lateral = false
	traces.clear()


func _reach() -> float:
	return _rules.weapon.tip_radius + _rules.fighter.body_radius


static func _range_quality(distance: float, ideal: float, tolerance: float) -> float:
	return SimMath.clamp01(1.0 - absf(distance - ideal) / tolerance)


## The delayed sighting carried forward along the opponent's observed
## velocity, measured from the CPU's own (felt, not delayed) body.
func _perceive(seen: CpuObservation, me: FighterState, tick: int) -> void:
	var lead := profile.anticipation * float(tick - seen.tick) * SimulationTimebase.TICK_SECONDS
	_sight_x = seen.opp_x + seen.opp_vx * lead
	_sight_y = seen.opp_y + seen.opp_vy * lead
	_sight_distance = SimMath.length(_sight_x - me.x, _sight_y - me.y)


func _decide(seen: CpuObservation, me: FighterState, decision_tick: int) -> void:
	var reach := _reach()
	var perceived := _sight_distance + _rng.next_range(-profile.range_error, profile.range_error)
	var assessment := TacticalAssessment.evaluate(seen, me, perceived, reach, _rules, profile)
	var opp_charging := seen.opp_phase == CombatPhase.Id.CHARGING
	var threatened := (seen.opponent_swinging() or (opp_charging and seen.opp_charge > THREAT_CHARGE)) and perceived < reach + THREAT_RANGE
	var open := seen.opponent_open()
	var striking := CombatPhase.is_striking(me.weapon.phase)
	var ready := WeaponSystem.can_start_attack(me, _rules.weapon)
	var pressure := SimMath.clamp01(float(_idle_ticks) / float(PRESSURE_TICKS)) * profile.pressure_weight
	var desired := profile.tap_range + READY_RANGE_LEAD if ready else profile.engage_range
	var utilities := PackedFloat64Array([HOLD_UTILITY, 0.0, 0.0, 0.0, 0.0])
	utilities[Move.APPROACH] = (profile.aggression + pressure) * SimMath.clamp01((perceived - desired) / APPROACH_RAMP)
	if open:
		utilities[Move.APPROACH] += profile.punish_weight * SimMath.clamp01((perceived - reach * PUNISH_REACH_SHARE) / PUNISH_RAMP)
	## Tempo: exploit recovery/overswing windows.
	if assessment.tempo_opportunity > 0.0:
		utilities[Move.APPROACH] += profile.tempo_awareness * assessment.tempo_opportunity
	## Corner pressure: press harder when opponent is near the wall.
	if assessment.arena_pressure > 0.0:
		utilities[Move.APPROACH] += profile.corner_pressure_weight * assessment.arena_pressure
	## Edge exploitation: Hard herds the opponent toward the cliff.
	if assessment.edge_position_advantage > 0.0 and profile.edge_exploit_weight > 0.0:
		utilities[Move.APPROACH] += profile.edge_exploit_weight * assessment.edge_position_advantage
	if threatened and not striking:
		utilities[Move.RETREAT] = profile.retreat_weight * (1.0 - SimMath.clamp01((perceived - reach) / RETREAT_RAMP))
	## Point threat: the opponent's tip is aimed at the CPU.
	if seen.opp_point_threat > 0.3 and perceived < reach + THREAT_RANGE and not striking:
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], profile.point_threat_weight * seen.opp_point_threat)
		utilities[Move.ORBIT] = maxf(utilities[Move.ORBIT], profile.point_threat_weight * seen.opp_point_threat * 0.6)
	if perceived < profile.tap_range - SMOTHERED_MARGIN and not striking:
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], profile.spacing_weight)
	var initiative := seen.opp_threat_time - seen.my_threat_time
	if initiative < -INITIATIVE_MARGIN and perceived < reach + INITIATIVE_RANGE and not striking:
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], profile.initiative_weight)
	## Withdrawal: retreat or orbit after own committed attack.
	if assessment.withdrawal_urge > 0.0 and profile.withdrawal_discipline > 0.0:
		var wd := profile.withdrawal_discipline * assessment.withdrawal_urge
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], wd)
		utilities[Move.ORBIT] = maxf(utilities[Move.ORBIT], wd * 0.5)
	if seen.opponent_swinging() or opp_charging:
		utilities[Move.ORBIT] = maxf(utilities[Move.ORBIT], profile.angle_weight * maxf(seen.opp_commitment, ORBIT_MIN_COMMITMENT))
	if (seen.opp_phase == CombatPhase.Id.NEUTRAL or opp_charging) and profile.pressure_weight > 0.0:
		utilities[Move.BAIT] = profile.bait_weight * (1.0 - pressure / profile.pressure_weight)
	_move = _best_move(utilities)
	_move = _safe_move(utilities, me)
	_orbit_sign = seen.opp_swing_dir
	_consider_burst(utilities[_move], striking, assessment, me)
	_attack = Attack.NONE
	if _holding or not ready:
		return
	var intercept := (opp_charging or seen.opp_phase == CombatPhase.Id.LAUNCH) and perceived <= reach
	## Indes: interception when opponent is committed and own tap can arrive.
	if assessment.indes_opportunity > 0.0 and perceived <= reach + THREAT_RANGE:
		intercept = true
	var tap_quality := _range_quality(perceived, profile.tap_range, TAP_TOLERANCE)
	var tap := 0.0
	if tap_quality >= MIN_RANGE_QUALITY:
		tap = tap_quality * (
			profile.probe_weight
			+ pressure
			+ profile.initiative_weight * SimMath.clamp01(initiative / INITIATIVE_FULL)
			+ (profile.punish_weight if open else 0.0)
			+ (profile.intercept_weight if intercept else 0.0)
			+ profile.tempo_awareness * assessment.tempo_opportunity
		)
	var charge := _range_quality(perceived, profile.charge_range, CHARGE_TOLERANCE) * (profile.charge_weight + pressure * CHARGE_PRESSURE_SHARE)
	charge *= OPEN_CHARGE_BOOST if open else 1.0
	charge *= THREATENED_CHARGE_DAMP if threatened else 1.0
	## Stamina-aware charge dampening: holding a charge is expensive motor
	## work, so the CPU discounts charge utility by depletion × weight.
	if profile.stamina_cost_weight > 0.0 and assessment.stamina_depletion > 0.0:
		charge *= 1.0 - assessment.stamina_depletion * profile.stamina_cost_weight * 0.5
	if tap >= charge and tap > profile.attack_threshold:
		_attack = Attack.TAP
	elif charge > profile.attack_threshold:
		_attack = Attack.HOLD
		_charge_target = SimMath.mix(
			_rng.next_range(profile.charge_min, profile.charge_max),
			profile.charge_max,
			CHARGE_OPENING_LEAN * SimMath.clamp01(seen.opp_opening / OPENING_FULL)
		)
	var trace := CpuDecisionTrace.create(decision_tick, seen.tick, utilities, _move, _attack, assessment)
	trace.burst_started = _burst_cursor == 0
	trace.burst_is_lateral = _burst_is_lateral
	traces.append(trace)


## Decide whether this footwork is worth a dash, and if so start typing the
## gesture for it. Approach and retreat trigger axial dashes (forward/back);
## orbit triggers a lateral dash (side-step) when the profile allows it.
## Bait never dashes — baiting holds spacing, dashing spends it.
## EdgeSafetyEvaluator filters any burst whose predicted trajectory crosses
## the platform edge.
func _consider_burst(utility: float, striking: bool, assessment: TacticalAssessment, me: FighterState) -> void:
	if profile.burst_weight <= 0.0 or _burst_cursor < BURST_SCRIPT.size() or striking:
		return
	if utility < BURST_UTILITY_MIN:
		return
	var capability := _move_capability(me)
	## Axial burst: approach or retreat.
	if _move == Move.APPROACH or _move == Move.RETREAT:
		var sign_for_move := 1.0 if _move == Move.APPROACH else -1.0
		if _rng.next_float() >= profile.burst_weight:
			return
		var kind := MovementGestureState.BurstKind.FORWARD_DASH if sign_for_move > 0.0 else MovementGestureState.BurstKind.BACK_DASH
		var safety := EdgeSafetyEvaluator.evaluate_burst(me, kind, _rules, capability)
		if safety.crosses_platform:
			return
		_burst_sign = sign_for_move
		_burst_is_lateral = false
		_burst_cursor = 0
		return
	## Lateral burst: orbit may become a side-step.
	if _move == Move.ORBIT and profile.lateral_dash_weight > 0.0:
		var best_lateral := TacticalAssessment.BURST_CLOCKWISE
		if assessment.burst_scores[TacticalAssessment.BURST_COUNTERCLOCKWISE] > assessment.burst_scores[TacticalAssessment.BURST_CLOCKWISE]:
			best_lateral = TacticalAssessment.BURST_COUNTERCLOCKWISE
		if assessment.burst_scores[best_lateral] < BURST_UTILITY_MIN:
			return
		if _rng.next_float() >= profile.lateral_dash_weight:
			return
		var cw_kind := MovementGestureState.BurstKind.RIGHT_STEP
		var ccw_kind := MovementGestureState.BurstKind.LEFT_STEP
		var chosen_kind := cw_kind if best_lateral == TacticalAssessment.BURST_CLOCKWISE else ccw_kind
		var safety := EdgeSafetyEvaluator.evaluate_burst(me, chosen_kind, _rules, capability)
		if safety.crosses_platform:
			## Try the other lateral direction.
			var alt_kind := ccw_kind if best_lateral == TacticalAssessment.BURST_CLOCKWISE else cw_kind
			safety = EdgeSafetyEvaluator.evaluate_burst(me, alt_kind, _rules, capability)
			if safety.crosses_platform:
				return
			_burst_sign = -_orbit_sign if best_lateral == TacticalAssessment.BURST_CLOCKWISE else _orbit_sign
		else:
			_burst_sign = _orbit_sign if best_lateral == TacticalAssessment.BURST_CLOCKWISE else -_orbit_sign
		_burst_is_lateral = true
		_burst_cursor = 0


static func _best_move(utilities: PackedFloat64Array) -> Move:
	var best := 0
	for index in range(1, utilities.size()):
		if utilities[index] > utilities[best]:
			best = index
	return best as Move


## Movement capability scalar for the current fighter state.
func _move_capability(me: FighterState) -> float:
	var stamina_max := StaminaModel.max_for_health(
		me.health, _rules.fighter.max_health, _rules.fighter.base_stamina, _rules.combat
	)
	return CapabilityModel.resolve_movement(
		me.health, _rules.fighter.max_health, me.stamina, stamina_max, _rules.combat
	)


## Steer vector (duel axes) for a given Move, used by the safety evaluator to
## predict trajectory without executing a real step.
func _steer_for_move(move: Move, me: FighterState) -> PackedFloat64Array:
	var distance := _sight_distance
	var tx := 1.0
	var ty := 0.0
	if distance > SimMath.EPSILON:
		tx = (_sight_x - me.x) / distance
		ty = (_sight_y - me.y) / distance
	var x := 0.0
	var y := 0.0
	match move:
		Move.APPROACH:
			x = tx
			y = ty
		Move.RETREAT:
			x = -tx
			y = -ty
		Move.ORBIT:
			x = -ty * _orbit_sign * ORBIT_TANGENT + tx * ORBIT_CLOSE
			y = tx * _orbit_sign * ORBIT_TANGENT + ty * ORBIT_CLOSE
		Move.BAIT:
			var hover := _reach() + BAIT_MARGIN
			if distance > hover + BAIT_BAND:
				x = tx * BAIT_STEP
				y = ty * BAIT_STEP
			elif distance < hover - BAIT_BAND:
				x = -tx * BAIT_STEP
				y = -ty * BAIT_STEP
			else:
				x = -ty * _orbit_sign * BAIT_DRIFT
				y = tx * _orbit_sign * BAIT_DRIFT
	return DuelGeometry.to_duel(x, y, tx, ty)


## Choose the best utility move that does not voluntarily cross the platform
## edge. If no candidate is safe, choose the one with maximum clearance.
## Walk safety only activates when the fighter is already close to the edge
## (within twice its body radius). Further out, the edge steering in _steer()
## handles avoidance. Burst safety is the hard filter (handled in
## _consider_burst), because a burst commits and cannot be steered.
func _safe_move(utilities: PackedFloat64Array, me: FighterState) -> Move:
	var chosen := _best_move(utilities)
	var radius := SimMath.length(me.x, me.y)
	if radius < _rules.platform_radius - _rules.fighter.body_radius:
		return chosen
	var capability := _move_capability(me)
	var steer := _steer_for_move(chosen, me)
	var safety := EdgeSafetyEvaluator.evaluate_walk(me, steer[0], steer[1], _rules, capability)
	if not safety.crosses_platform:
		return chosen
	## The best move would cross the platform from near the edge. Try
	## alternatives in utility order.
	var ranked: Array[int] = []
	for i in utilities.size():
		ranked.append(i)
	ranked.sort_custom(func(a: int, b: int) -> bool: return utilities[a] > utilities[b])
	var best_clearance_move := chosen
	var best_clearance := safety.min_clearance
	for idx in ranked:
		var move := idx as Move
		if move == chosen:
			continue
		var alt_steer := _steer_for_move(move, me)
		var alt_safety := EdgeSafetyEvaluator.evaluate_walk(me, alt_steer[0], alt_steer[1], _rules, capability)
		if not alt_safety.crosses_platform:
			return move
		if alt_safety.min_clearance > best_clearance:
			best_clearance = alt_safety.min_clearance
			best_clearance_move = move
	## All candidates fall — choose the one with maximum survival.
	return best_clearance_move


func _execute(tick: int, me: FighterState) -> PlayerCommand:
	var steer := _burst_step() if _burst_cursor < BURST_SCRIPT.size() else _steer(me)
	var pressed := false
	var released := false
	if _holding:
		_hold_ticks += 1
		var weapon := me.weapon
		var charging := weapon.phase == CombatPhase.Id.CHARGING
		var in_reach := _sight_distance <= _reach() + profile.release_slack
		var charged := charging and weapon.charge >= _charge_target
		var interrupted := not charging and weapon.phase != CombatPhase.Id.NEUTRAL
		## A blade that is pinned or already at the guard limit stops earning
		## charge, so a target it cannot reach would otherwise hold forever.
		var held_too_long := _hold_ticks > _rules.weapon.tap_threshold_ticks + _rules.weapon.windback_limit_ticks(_rules.fighter.weapon_torque_scale) + HOLD_LIMIT_EXTRA_TICKS
		if interrupted or held_too_long or (charged and (in_reach or profile.release_any_range)):
			released = true
			_holding = false
	elif _attack != Attack.NONE and WeaponSystem.can_start_attack(me, _rules.weapon):
		pressed = true
		_idle_ticks = 0
		if _attack == Attack.TAP:
			released = true
		else:
			_holding = true
			_hold_ticks = 0
		_attack = Attack.NONE
	return PlayerCommand.create(tick, steer[0], steer[1], pressed, released)


## One tick of the dash gesture, in duel axes. Axial bursts go on the Y axis
## (forward/back), lateral bursts on X (right/left). The rest ticks are real
## rests: the recognizer requires the intent to come genuinely to neutral
## between taps, so a CPU that merely eased off would never earn a dash.
func _burst_step() -> PackedFloat64Array:
	var deflection := BURST_SCRIPT[_burst_cursor] * _burst_sign
	_burst_cursor += 1
	if _burst_is_lateral:
		return PackedFloat64Array([deflection, 0.0])
	return PackedFloat64Array([0.0, deflection])


## Footwork vector toward / away from / around the perceived opponent, with
## a pull back toward the center near the arena edge.
func _steer(me: FighterState) -> PackedFloat64Array:
	var distance := _sight_distance
	var tx := 1.0
	var ty := 0.0
	if distance > SimMath.EPSILON:
		tx = (_sight_x - me.x) / distance
		ty = (_sight_y - me.y) / distance
	var x := 0.0
	var y := 0.0
	match _move:
		Move.APPROACH:
			x = tx
			y = ty
		Move.RETREAT:
			x = -tx
			y = -ty
		Move.ORBIT:
			x = -ty * _orbit_sign * ORBIT_TANGENT + tx * ORBIT_CLOSE
			y = tx * _orbit_sign * ORBIT_TANGENT + ty * ORBIT_CLOSE
		Move.BAIT:
			var hover := _reach() + BAIT_MARGIN
			if distance > hover + BAIT_BAND:
				x = tx * BAIT_STEP
				y = ty * BAIT_STEP
			elif distance < hover - BAIT_BAND:
				x = -tx * BAIT_STEP
				y = -ty * BAIT_STEP
			else:
				x = -ty * _orbit_sign * BAIT_DRIFT
				y = tx * _orbit_sign * BAIT_DRIFT
	var radius := SimMath.length(me.x, me.y)
	var edge := _rules.platform_radius - EDGE_MARGIN
	if radius > edge:
		var pull := SimMath.clamp01((radius - edge) / EDGE_RAMP)
		x = SimMath.mix(x, -me.x / radius, pull)
		y = SimMath.mix(y, -me.y / radius, pull)
	## The CPU reasons in world geometry but must speak the same duel-relative
	## command language a keyboard does (CPU-001), so the vector is expressed
	## in the axis it *believes* the opponent lies on. Where its perception is
	## stale the simulation's true basis will bend the step slightly — which is
	## the reaction delay showing up in footwork, exactly as it should.
	return DuelGeometry.to_duel(x, y, tx, ty)
