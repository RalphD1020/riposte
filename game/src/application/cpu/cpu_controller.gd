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
## The longest a capitalize intent may live without lapsing on its own (ticks):
## a guard against stale intent, never its expected length — the intent ends
## as soon as the physics no longer supports it.
const CAPITALIZE_LIMIT_TICKS := 90
## How far under the sector-entry deflection an eased step is held.
const DASH_EASE := 0.95

var profile: CpuProfile
## Tick of the observation the last decision used (proves perception delay).
var last_perceived_tick: int = -1
var _rules: DuelRules
## The CPU's own combatant physics (its body, weapon and handling).
var _spec: CombatantPhysicsSpec
## This duel's strike reach, and the reference duel's (see `calibration_reach`).
var _reach_m: float = 0.0
var _calibration_m: float = 0.0
## How far one forward dash carries the CPU's own body before it can stop
## (m), at full condition: the burst, then its glide to rest under the brake.
var _dash_m: float = 0.0
## The longest any hold could still be earning charge (ticks), from the
## weapon coordinate's peak inertia — a release valve, never physics.
var _windback_limit_ticks: int = 0
var _rng: SeededRng
## The last `MEMORY_TICKS` observations, a ring of kept objects rewritten in
## place: `_newest` is the latest, `_remembered` how many are filled.
var _memory: Array[CpuObservation] = []
var _newest: int = -1
var _remembered: int = 0
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
## Dash gestures begun since the last reset, on any decision tick (traces
## record only decisions that reach the attack choice). Sidecar telemetry.
var bursts_begun: int = 0
## Match-lifetime decision counts. Not cleared on a round reset, not hashed,
## and not read by a later decision. `probes_suppressed` is a decision under
## the dash-cost gate with nothing owed, so no probe or charge was scored.
var decisions: int = 0
var probes_suppressed: int = 0
var capitalize_decisions: int = 0
var tempo_decisions: int = 0
var intercept_decisions: int = 0
var tap_choices: int = 0
var charge_choices: int = 0
## CapitalizeIntent (CPU-008): while true the CPU is closing on an opening it
## physically expects to reach first, by the route `_clear_side` names — 0
## straight in, ±1 beside the opponent on that side of its line (+1
## counter-clockwise of its heading), away from its sword — until
## `_capitalize_until` at the latest. Revalidated every decision; a command
## intent only — nothing here is state of the duel.
var _capitalizing: bool = false
var _clear_side: float = 0.0
var _capitalize_until: int = 0
var _route_scratch := ThreatEstimate.new()
var _threat_scratch := ThreatEstimate.new()
## The opponent's perceived heading and its body's push radius, for the
## route beside it.
var _sight_facing: float = 0.0
var _opponent_push: float = 0.0


static func create(rules: DuelRules, cpu_profile: CpuProfile, match_seed: int, slot: int) -> CpuController:
	var controller := CpuController.new()
	controller._rules = rules
	controller._spec = rules.combatant(slot)
	## Its own sword against the opponent's torso: a longer weapon or a
	## smaller target moves every preferred distance with it.
	controller._reach_m = WeaponKinematics.strike_reach(controller._spec, rules.combatant(1 - slot))
	controller._calibration_m = calibration_reach()
	var body := controller._spec.fighter
	controller._dash_m = body.burst_speed_axial * float(body.burst_ticks) * SimulationTimebase.TICK_SECONDS + body.burst_speed_axial * body.burst_speed_axial / (2.0 * body.brake_accel())
	controller._windback_limit_ticks = controller._spec.weapon.windback_limit_ticks(controller._spec.fighter.weapon_torque_scale, WeaponKinematics.peak_motor_inertia(controller._spec))
	controller.profile = cpu_profile
	controller._opponent_push = rules.combatant(1 - slot).fighter.push_radius
	controller._rng = SeededRng.create(match_seed, SeededRng.cpu_stream(slot))
	return controller


func command_for(state: MatchState, slot: int) -> PlayerCommand:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		_forget()
		return PlayerCommand.idle(state.tick)
	var me := state.fighter(slot)
	_idle_ticks += 1
	var seen := _remember(state, slot)
	_perceive(seen, me, state.tick)
	if state.tick >= _next_decision_tick:
		last_perceived_tick = seen.tick
		seen.feel_self(me)
		seen.resolve(_rules)
		_decide(seen, me, state.tick, state.body_contact)
		_next_decision_tick = state.tick + profile.decision_ticks + _rng.next_int(0, profile.decision_jitter)
	return _execute(state.tick, me)


func _forget() -> void:
	_newest = -1
	_remembered = 0
	_holding = false
	_hold_ticks = 0
	_attack = Attack.NONE
	_move = Move.APPROACH
	_idle_ticks = 0
	_next_decision_tick = 0
	_burst_cursor = BURST_SCRIPT.size()
	_burst_sign = 0.0
	_burst_is_lateral = false
	_capitalizing = false
	_clear_side = 0.0
	traces.clear()
	bursts_begun = 0


## The strike reach the profiles' distances are authored at: the reference
## loadout's own (the reference duelist with his sword against himself), so
## for the reference fighter and sword a profile metre is a metre. A
## calibration constant of the CPU's authoring, never a default fighter. Correcting the reference's geometry — the hurt
## torso, the attack path — never silently rescales a profile; only a
## different fighter or weapon does.
static func calibration_reach() -> float:
	var reference_spec := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	return WeaponKinematics.strike_reach(reference_spec, reference_spec)


func _reach() -> float:
	return _reach_m


## The range an approach closes to (m): just past tap range when this CPU can
## strike, its engage range otherwise (CPU-009).
func preferred_range(ready: bool) -> float:
	return _range(profile.tap_range) + READY_RANGE_LEAD if ready else _range(profile.engage_range)


## Closer than this (m) is smothered measure, which a CPU free to act steps
## back out of (CPU-009).
func smothered_line() -> float:
	return _range(profile.tap_range) - SMOTHERED_MARGIN


## How far one forward dash carries this CPU before it can stop (m), at full
## condition (CPU-009).
func dash_travel() -> float:
	return _dash_m


## A profile's preferred distance (authored in metres at `calibration_reach`)
## at this duel's actual reach. Profile weights are calibrated against the
## scale of what they measure (CPU-001): a longer sword or longer arms move
## every preferred distance with the reach, so the same profile keeps the
## same judgement.
func _range(authored: float) -> float:
	return authored * _reach_m / _calibration_m


## How much closer the two bodies get before an approach decided now can be
## stopped (m): the CPU's own speed toward the opponent (felt) and the
## opponent's toward it (observed, delayed like every other reading) over one
## decision period, plus the CPU's own braking distance.
## Record this tick and return the observation `reaction_ticks` old (the oldest
## kept while fewer are remembered).
func _remember(state: MatchState, slot: int) -> CpuObservation:
	if _memory.is_empty():
		for _i in MEMORY_TICKS:
			_memory.append(CpuObservation.new())
	_newest = (_newest + 1) % MEMORY_TICKS
	_memory[_newest].record_into(state, slot, _rules)
	_remembered = mini(_remembered + 1, MEMORY_TICKS)
	var back := mini(profile.reaction_ticks, _remembered - 1)
	return _memory[(_newest - back + MEMORY_TICKS) % MEMORY_TICKS]


func _closing_lead(seen: CpuObservation, me: FighterState) -> float:
	var dx := _sight_x - me.x
	var dy := _sight_y - me.y
	var distance := SimMath.length(dx, dy)
	if distance <= SimMath.EPSILON:
		return 0.0
	var ux := dx / distance
	var uy := dy / distance
	var mine := maxf(me.vx * ux + me.vy * uy, 0.0)
	var theirs := maxf(-(seen.opp_vx * ux + seen.opp_vy * uy), 0.0)
	var horizon := float(profile.decision_ticks) * SimulationTimebase.TICK_SECONDS
	return (mine + theirs) * horizon + mine * mine / (2.0 * _spec.fighter.brake_accel())


static func _range_quality(distance: float, ideal: float, tolerance: float) -> float:
	return SimMath.clamp01(1.0 - absf(distance - ideal) / tolerance)


## The delayed sighting carried forward along the opponent's observed
## velocity, measured from the CPU's own (felt, not delayed) body.
func _perceive(seen: CpuObservation, me: FighterState, tick: int) -> void:
	var lead := profile.anticipation * float(tick - seen.tick) * SimulationTimebase.TICK_SECONDS
	_sight_x = seen.opp_x + seen.opp_vx * lead
	_sight_y = seen.opp_y + seen.opp_vy * lead
	_sight_distance = SimMath.length(_sight_x - me.x, _sight_y - me.y)


func _decide(seen: CpuObservation, me: FighterState, decision_tick: int, body_contact: BodyContactState = null) -> void:
	var reach := _reach()
	var perceived := _sight_distance + _rng.next_range(-profile.range_error, profile.range_error)
	var assessment := TacticalAssessment.evaluate(seen, me, perceived, reach, _rules, profile, body_contact)
	var opp_charging := seen.opp_phase == CombatPhase.Id.CHARGING
	var threatened := (seen.opponent_swinging() or (opp_charging and seen.opp_charge > THREAT_CHARGE)) and perceived < reach + THREAT_RANGE
	var open := seen.opponent_open()
	var striking := CombatPhase.is_striking(me.weapon.phase)
	var ready := WeaponSystem.can_start_attack(me, _spec.weapon)
	var pressure := SimMath.clamp01(float(_idle_ticks) / float(PRESSURE_TICKS)) * profile.pressure_weight
	var desired := preferred_range(ready)
	## Measure is judged where the bodies will be once this approach can be
	## stopped, not where they stand: both still close until the next decision,
	## and the CPU's own stride takes its braking distance to stop. Judged on
	## the distance alone, two approaching fighters overshoot into each other's
	## grips.
	var arriving := perceived - _closing_lead(seen, me)
	var utilities := PackedFloat64Array([HOLD_UTILITY, 0.0, 0.0, 0.0, 0.0])
	utilities[Move.APPROACH] = (profile.aggression + pressure) * SimMath.clamp01((arriving - desired) / APPROACH_RAMP)
	if open:
		utilities[Move.APPROACH] += profile.punish_weight * SimMath.clamp01((arriving - reach * PUNISH_REACH_SHARE) / PUNISH_RAMP)
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
	if perceived < smothered_line() and not striking:
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
	## Push-pressure survival (CPU-007). When being displaced toward the edge
	## by a solved constraint impulse, boost retreat/orbit utility. Only acts
	## in the outer rim where ring-out is a real threat; center-arena contact
	## is handled by existing spacing and initiative logic.
	if assessment.being_displaced and assessment.edge_clearance < _rules.platform_radius * 0.3:
		var push_urgency := SimMath.clamp01(1.0 - float(assessment.time_to_support_loss) / 120.0)
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], push_urgency * 0.4)
		utilities[Move.ORBIT] = maxf(utilities[Move.ORBIT], push_urgency * 0.3)
	_move = _best_move(utilities)
	_move = _safe_move(utilities, me)
	_orbit_sign = seen.opp_swing_dir
	_sight_facing = seen.opp_facing
	_update_capitalize(seen, me, decision_tick, striking, utilities)
	var burst_utility := utilities[_move]
	if _capitalizing:
		_move = Move.APPROACH
		## Dash in only when the gap still needs closing.
		if perceived > reach:
			burst_utility = maxf(burst_utility, BURST_UTILITY_MIN)
	_consider_burst(burst_utility, striking, assessment, me, arriving - desired)
	var intercept := (opp_charging or seen.opp_phase == CombatPhase.Id.LAUNCH) and perceived <= reach
	## Indes: interception when opponent is committed and own tap can arrive.
	if assessment.indes_opportunity > 0.0 and perceived <= reach + THREAT_RANGE:
		intercept = true
	_attack = Attack.NONE
	if _holding or not ready:
		return
	if _capitalizing:
		if perceived <= reach:
			_attack = Attack.TAP
		_record_decision(decision_tick, seen.tick, utilities, assessment, me, open, intercept, true)
		return
	## Low stamina is the dash the bar cannot afford (STAMINA-004). That one
	## bar is the guarded-probe gate on purpose: mobility affordability and
	## attack selection share it, and there is no second threshold. With
	## nothing owed — no open opponent, no intercept, no tempo window — a
	## probe or a charge waits. A capitalize already returned above, and an
	## owed window still scores.
	var owed := open or intercept or assessment.tempo_opportunity > 0.0
	if _condition(me).can_dash or owed:
		var tap_quality := _range_quality(perceived, _range(profile.tap_range), TAP_TOLERANCE)
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
		var charge := _range_quality(perceived, _range(profile.charge_range), CHARGE_TOLERANCE) * (profile.charge_weight + pressure * CHARGE_PRESSURE_SHARE)
		charge *= OPEN_CHARGE_BOOST if open else 1.0
		charge *= THREATENED_CHARGE_DAMP if threatened else 1.0
		if tap >= charge and tap > profile.attack_threshold:
			_attack = Attack.TAP
		elif charge > profile.attack_threshold:
			_attack = Attack.HOLD
			_charge_target = SimMath.mix(
				_rng.next_range(profile.charge_min, profile.charge_max),
				profile.charge_max,
				CHARGE_OPENING_LEAN * SimMath.clamp01(seen.opp_opening / OPENING_FULL)
			)
	var trace := _record_decision(decision_tick, seen.tick, utilities, assessment, me, open, intercept, false)
	trace.burst_started = _burst_cursor == 0
	trace.burst_is_lateral = _burst_is_lateral


## Append one decision trace and count it. `capitalizing` is the intent that
## already returned above the probe gate. The counts outlive a round reset.
func _record_decision(
	decision_tick: int,
	seen_tick: int,
	utilities: PackedFloat64Array,
	assessment: TacticalAssessment,
	me: FighterState,
	open: bool,
	intercept: bool,
	capitalizing: bool,
) -> CpuDecisionTrace:
	var trace := CpuDecisionTrace.create(decision_tick, seen_tick, utilities, _move, _attack, assessment)
	var owed := open or intercept or assessment.tempo_opportunity > 0.0
	trace.below_dash = not _condition(me).can_dash
	trace.owed_open = open
	trace.owed_intercept = intercept
	trace.capitalizing = capitalizing
	trace.probe_suppressed = trace.below_dash and not owed and not capitalizing
	decisions += 1
	if trace.probe_suppressed:
		probes_suppressed += 1
	if capitalizing:
		capitalize_decisions += 1
	if assessment.tempo_opportunity > 0.0:
		tempo_decisions += 1
	if intercept:
		intercept_decisions += 1
	if _attack == Attack.TAP:
		tap_choices += 1
	elif _attack == Attack.HOLD:
		charge_choices += 1
	traces.append(trace)
	return trace


## Decide whether this footwork is worth a dash, and if so start typing the
## gesture for it. Approach and retreat trigger axial dashes (forward/back);
## orbit triggers a lateral dash (side-step) when the profile allows it.
## Bait never dashes — baiting holds spacing, dashing spends it.
## EdgeSafetyEvaluator filters any burst whose predicted trajectory crosses
## the platform edge. A forward dash spends its whole distance at once, so it
## is taken only when `to_close` — how much farther than the range this
## approach closes to the bodies will be once it can stop — is at least one
## dash: the dash never carries the CPU inside its own preferred measure.
func _consider_burst(utility: float, striking: bool, assessment: TacticalAssessment, me: FighterState, to_close: float) -> void:
	if profile.burst_weight <= 0.0 or _burst_cursor < BURST_SCRIPT.size() or striking:
		return
	if utility < BURST_UTILITY_MIN:
		return
	var condition := _condition(me)
	## A dash it cannot pay for would be refused (STAMINA-004): the CPU reads
	## its own stamina, as a player reads their bar, and does not type one.
	if not condition.can_dash:
		return
	## Axial burst: approach or retreat.
	if _move == Move.APPROACH or _move == Move.RETREAT:
		var sign_for_move := 1.0 if _move == Move.APPROACH else -1.0
		if _rng.next_float() >= profile.burst_weight:
			return
		if _move == Move.APPROACH and to_close < dash_travel():
			return
		var kind := MovementGestureState.BurstKind.FORWARD_DASH if sign_for_move > 0.0 else MovementGestureState.BurstKind.BACK_DASH
		var safety := EdgeSafetyEvaluator.evaluate_burst(me, kind, _rules, condition)
		if safety.crosses_platform:
			return
		_burst_sign = sign_for_move
		_burst_is_lateral = false
		_burst_cursor = 0
		bursts_begun += 1
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
		var safety := EdgeSafetyEvaluator.evaluate_burst(me, chosen_kind, _rules, condition)
		if safety.crosses_platform:
			## Try the other lateral direction.
			var alt_kind := ccw_kind if best_lateral == TacticalAssessment.BURST_CLOCKWISE else cw_kind
			safety = EdgeSafetyEvaluator.evaluate_burst(me, alt_kind, _rules, condition)
			if safety.crosses_platform:
				return
			_burst_sign = -_orbit_sign if best_lateral == TacticalAssessment.BURST_CLOCKWISE else _orbit_sign
		else:
			_burst_sign = _orbit_sign if best_lateral == TacticalAssessment.BURST_CLOCKWISE else -_orbit_sign
		_burst_is_lateral = true
		_burst_cursor = 0
		bursts_begun += 1


## CapitalizeIntent (CPU-008): start, keep or drop the intent from physics
## alone — never a WHIFF, PARRY or DEFLECTION label. The same test serves a
## miss, a parry, a deflection, a clash, an overswing or a stumble. Read from
## the CPU's current self and its delayed view of the opponent.
##
## - A clear route (`_clear_route`): the direct line if, pressed now and
##   closing along it, my blade would reach the torso before the opponent's
##   protective steel; otherwise a detour beside the opponent on the side away
##   from its sword, if that reaches the torso. The opponent's sword moves
##   only under its own known law for its perceived phase.
## - Feasible (every profile alike): along that route I arrive before the
##   opponent's own threat, read in the same imagined world — one
##   `ThreatContinuation`, both swords swept, each body at its current
##   velocity (`opponent_threat_reading`).
## - Confident (this profile): sooner by `capitalize_margin`.
## - Safe: approaching does not walk off the platform.
##
## It starts when the opponent is open and all four hold. Every later decision
## re-asks all of them (the opponent need no longer be open: it is owed until
## it threatens first), re-choosing the route — the detour only while steel is
## in the direct line — and drops the intent at the first that fails, or at the
## safety cap. Once the strike is out it has done its work.
func _update_capitalize(seen: CpuObservation, me: FighterState, decision_tick: int, striking: bool, utilities: PackedFloat64Array) -> void:
	if striking:
		_capitalizing = false
		return
	if not _capitalizing:
		## Only an opponent who owes something — overswinging, recovering,
		## staggered, or its threat lagging mine (`opponent_open`, the state of
		## its weapon and body, never an event) — is an opening; a guarded
		## opponent at rest is neutral, decided by the ordinary utilities.
		if not seen.opponent_open():
			return
	elif decision_tick >= _capitalize_until:
		_capitalizing = false
		return
	var arrival := _clear_route(seen, me)
	if arrival < 0.0:
		_capitalizing = false
		return
	## The opponent's threat in the same imagined world as the route (one
	## continuation): a strike of theirs that my steel would stop first, or
	## that reaches nothing inside the horizon, is no threat to arrive before.
	var theirs := seen.opponent_threat_reading(_rules, _threat_scratch)
	var their_time := theirs.hit_time if _reaches_flesh(theirs) else INF
	var margin := 0.0 if _capitalizing else profile.capitalize_margin
	var go := arrival + margin < their_time and _approach_safe(utilities, me)
	if not go:
		_capitalizing = false
		return
	if not _capitalizing:
		_capitalizing = true
		_capitalize_until = decision_tick + CAPITALIZE_LIMIT_TICKS


## The route to the opening, as `_clear_side` (0 straight in; ±1 beside the
## opponent on that side of its line, away from its sword), and its arrival
## time — or −1 when neither the direct line nor the detour reaches the torso
## before protective steel.
func _clear_route(seen: CpuObservation, me: FighterState) -> float:
	var direct := Vector2(_sight_x - me.x, _sight_y - me.y)
	if direct.length() <= SimMath.EPSILON:
		return -1.0
	direct = direct.normalized()
	var reading := seen.route_reading(_rules, direct.x, direct.y, _route_scratch)
	if _reaches_flesh(reading):
		_clear_side = 0.0
		return reading.hit_time
	var side := _side_away_from_blade(seen)
	var detour := _route_beside(me, side)
	reading = seen.route_reading(_rules, detour.x, detour.y, _route_scratch)
	if _reaches_flesh(reading):
		_clear_side = side
		return reading.hit_time
	return -1.0


## A route reaches flesh when the predicted strike meets the torso circle
## before any steel. A prediction that starts with the swords already bound is
## no answer: the cheap predictor does not carry the bind's constraint, and
## the agreement audit found its "clear" readings from a bind mostly wrong, so
## a bound route is never taken as clear — the bind is decided by the ordinary
## utilities and by physics, not by an invented forecast.
static func _reaches_flesh(reading: ThreatEstimate) -> bool:
	return not reading.starts_bound and reading.first_contact == ThreatEstimate.BODY


## The side of the opponent's line (its heading, as perceived; +1
## counter-clockwise) its sword is not on: the open side.
func _side_away_from_blade(seen: CpuObservation) -> float:
	var off_line := SimMath.sine(seen.opp_blade_angle() - seen.opp_facing)
	return -1.0 if off_line > 0.0 else 1.0


## Whether an approach is a move the edge-safety filter would allow.
func _approach_safe(utilities: PackedFloat64Array, me: FighterState) -> bool:
	var preferring := utilities.duplicate()
	preferring[Move.APPROACH] = INF
	return _safe_move(preferring, me) == Move.APPROACH


static func _best_move(utilities: PackedFloat64Array) -> Move:
	var best := 0
	for index in range(1, utilities.size()):
		if utilities[index] > utilities[best]:
			best = index
	return best as Move


## The CPU's own condition (CONDITION-001) — health is public, and its body
## is its own to feel.
func _condition(me: FighterState) -> ConditionState:
	return ConditionModel.compute(me.health, _spec.fighter.max_health, me.stamina, _rules.combat, ConditionState.new())


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
	if radius < _rules.platform_radius - _spec.fighter.push_radius:
		return chosen
	var condition := _condition(me)
	var steer := _steer_for_move(chosen, me)
	var safety := EdgeSafetyEvaluator.evaluate_walk(me, steer[0], steer[1], _rules, condition)
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
		var alt_safety := EdgeSafetyEvaluator.evaluate_walk(me, alt_steer[0], alt_steer[1], _rules, condition)
		if not alt_safety.crosses_platform:
			return move
		if alt_safety.min_clearance > best_clearance:
			best_clearance = alt_safety.min_clearance
			best_clearance_move = move
	## All candidates fall — choose the one with maximum survival.
	return best_clearance_move


func _execute(tick: int, me: FighterState) -> PlayerCommand:
	var steer := _burst_step() if _burst_cursor < BURST_SCRIPT.size() else _without_accidental_dash(_steer(me), tick, me)
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
		var held_too_long := _hold_ticks > _spec.weapon.tap_threshold_ticks + _windback_limit_ticks + HOLD_LIMIT_EXTRA_TICKS
		if interrupted or held_too_long or (charged and (in_reach or profile.release_any_range)):
			released = true
			_holding = false
	elif _attack != Attack.NONE and WeaponSystem.can_start_attack(me, _spec.weapon):
		pressed = true
		_idle_ticks = 0
		if _attack == Attack.TAP:
			released = true
		else:
			_holding = true
			_hold_ticks = 0
		_attack = Attack.NONE
	return PlayerCommand.create(tick, steer[0], steer[1], pressed, released)


## Input hygiene: a dash is a decision (`_consider_burst`), never an accident
## of footwork switching. The CPU feels its own input as a player does — its
## own gesture state (`FighterState.gesture`, what `DirectionalTapRecognizer`
## remembers of its taps) — and a footwork step that would be the second tap
## of a double tap it did not decide on is eased just under the deflection
## that enters a sector, so it walks without dashing.
func _without_accidental_dash(steer: PackedFloat64Array, tick: int, me: FighterState) -> PackedFloat64Array:
	var body := _spec.fighter
	var gesture := me.gesture
	var probe := PlayerCommand.create(tick, steer[0], steer[1])
	var next := DirectionalTapRecognizer.sector_of(gesture.sector, probe.axis_x(), probe.axis_y(), body)
	var second_tap := (
		next != gesture.sector
		and next != MovementGestureState.Direction.NONE
		and gesture.awaiting_second_tap
		and gesture.last_direction == next
		and gesture.returned_to_neutral
		and tick - gesture.first_tap_tick <= body.double_tap_window_ticks
	)
	if not second_tap:
		return steer
	var magnitude := SimMath.length(steer[0], steer[1])
	var eased := body.burst_enter_deflection * DASH_EASE / magnitude
	return PackedFloat64Array([steer[0] * eased, steer[1] * eased])


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


## The capitalize close (CPU-008) along `side`: 0 straight at the perceived
## opponent; ±1 toward a point beside it on that side of its line — its body's
## edge and mine off its centre line — so the step closes while keeping its
## sword out of the path. From the bodies' own radii; no authored angle. A
## unit world vector.
func _route_beside(me: FighterState, side: float) -> Vector2:
	var offset := (_opponent_push + _spec.fighter.push_radius) * side
	var route := Vector2(_sight_x - SimMath.heading_sine(_sight_facing) * offset - me.x, _sight_y + SimMath.heading_cosine(_sight_facing) * offset - me.y)
	return route.normalized() if route.length() > SimMath.EPSILON else Vector2(_sight_x - me.x, _sight_y - me.y).normalized()


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
			if _capitalizing:
				var route := _route_beside(me, _clear_side)
				x = route.x
				y = route.y
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
