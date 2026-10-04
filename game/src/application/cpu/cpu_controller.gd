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
enum Attack { NONE, TAP, CHARGE }

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
## Where the opponent is believed to be now, and how far from the CPU.
var _sight_x: float = 0.0
var _sight_y: float = 0.0
var _sight_distance: float = 0.0


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
		_decide(seen, me)
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


func _decide(seen: CpuObservation, me: FighterState) -> void:
	var reach := _reach()
	var perceived := _sight_distance + _rng.next_range(-profile.range_error, profile.range_error)
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
	if threatened and not striking:
		utilities[Move.RETREAT] = profile.retreat_weight * (1.0 - SimMath.clamp01((perceived - reach) / RETREAT_RAMP))
	if perceived < profile.tap_range - SMOTHERED_MARGIN and not striking:
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], profile.spacing_weight)
	var initiative := seen.opp_threat_time - seen.my_threat_time
	if initiative < -INITIATIVE_MARGIN and perceived < reach + INITIATIVE_RANGE and not striking:
		utilities[Move.RETREAT] = maxf(utilities[Move.RETREAT], profile.initiative_weight)
	if seen.opponent_swinging() or opp_charging:
		utilities[Move.ORBIT] = profile.angle_weight * maxf(seen.opp_commitment, ORBIT_MIN_COMMITMENT)
	if (seen.opp_phase == CombatPhase.Id.NEUTRAL or opp_charging) and profile.pressure_weight > 0.0:
		utilities[Move.BAIT] = profile.bait_weight * (1.0 - pressure / profile.pressure_weight)
	_move = _best_move(utilities)
	_orbit_sign = seen.opp_swing_dir
	_attack = Attack.NONE
	if _holding or not ready:
		return
	var intercept := (opp_charging or seen.opp_phase == CombatPhase.Id.LAUNCH) and perceived <= reach
	var tap_quality := _range_quality(perceived, profile.tap_range, TAP_TOLERANCE)
	var tap := 0.0
	if tap_quality >= MIN_RANGE_QUALITY:
		tap = tap_quality * (
			profile.probe_weight
			+ pressure
			+ profile.initiative_weight * SimMath.clamp01(initiative / INITIATIVE_FULL)
			+ (profile.punish_weight if open else 0.0)
			+ (profile.intercept_weight if intercept else 0.0)
		)
	var charge := _range_quality(perceived, profile.charge_range, CHARGE_TOLERANCE) * (profile.charge_weight + pressure * CHARGE_PRESSURE_SHARE)
	charge *= OPEN_CHARGE_BOOST if open else 1.0
	charge *= THREATENED_CHARGE_DAMP if threatened else 1.0
	if tap >= charge and tap > profile.attack_threshold:
		_attack = Attack.TAP
	elif charge > profile.attack_threshold:
		_attack = Attack.CHARGE
		_charge_target = _rng.next_range(profile.charge_min, profile.charge_max)


static func _best_move(utilities: PackedFloat64Array) -> Move:
	var best := 0
	for index in range(1, utilities.size()):
		if utilities[index] > utilities[best]:
			best = index
	return best as Move


func _execute(tick: int, me: FighterState) -> PlayerCommand:
	var steer := _steer(me)
	var pressed := false
	var released := false
	if _holding:
		_hold_ticks += 1
		var weapon := me.weapon
		var charging := weapon.phase == CombatPhase.Id.CHARGING
		var in_reach := _sight_distance <= _reach() + profile.release_slack
		var charged := charging and weapon.charge >= _charge_target
		var interrupted := not charging and weapon.phase != CombatPhase.Id.NEUTRAL
		var held_too_long := _hold_ticks > _rules.weapon.tap_threshold_ticks + _rules.weapon.charge_ticks + HOLD_LIMIT_EXTRA_TICKS
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
	var edge := _rules.arena_radius - EDGE_MARGIN
	if radius > edge:
		var pull := SimMath.clamp01((radius - edge) / EDGE_RAMP)
		x = SimMath.mix(x, -me.x / radius, pull)
		y = SimMath.mix(y, -me.y / radius, pull)
	return PackedFloat64Array([x, y])
