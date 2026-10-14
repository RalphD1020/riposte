class_name CpuObservation
extends RefCounted

## What the CPU perceives about the duel at one tick (PLAN Phase 9.1). The
## duel has no hidden information; delay, not omission, is what keeps the CPU
## human. Built from public state only, and only what decisions read.
##
## See also: /docs/concepts/cpu.md

## Threatening first by this much (s) leaves the opponent open.
const OPEN_MARGIN := 0.15

var tick: int = 0
var opp_x: float = 0.0
var opp_y: float = 0.0
var opp_vx: float = 0.0
var opp_vy: float = 0.0
var opp_phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var opp_charge: float = 0.0
var opp_commitment: float = 0.0
var opp_swing_dir: float = 1.0
## The opponent's combat heading φ: where its sword's control domain is
## centred, so which side of its line a body stands on.
var opp_facing: float = 0.0
## How exposed the opponent currently is, in [0, 1]. A *reading of their body*
## — weapon displaced, swing committed, balance lost, angle poor — and exactly
## the reading the player's own snapshot carries, so the CPU sees no more than
## a watching human does. It is still delayed like everything else here, and
## it is emphatically not a strike quality: nothing before contact knows what
## a hit would do (COMBAT-009).
var opp_exposure: float = 0.0
## The part of that exposure which is actually an *opening* — exposure above
## what a composed fighter always carries. This is what a decision wants: the
## raw fraction never reaches zero, so scoring against it would leave the CPU
## permanently a little tempted by a perfectly guarded opponent.
var opp_opening: float = 0.0
## Each side's bounded threat prediction (THREAT-001). The times read the
## horizon past it; a ranking of two out-of-horizon options reads what was
## still left (ThreatEstimate.residual_gap, eadiness_remaining).
var my_threat := ThreatEstimate.new()
var opp_threat := ThreatEstimate.new()
var my_threat_time: float = 0.0
var opp_threat_time: float = 0.0
## How directly the opponent's sword tip is aimed at the CPU, in [0, 1].
## 1 = dead-on alignment with forward body motion; 0 = no point threat.
## Combines blade orientation with closing velocity (COMBAT-010).
var opp_point_threat: float = 0.0
## Opponent's condition band (FighterCondition). A coarse reading of injury.
var opp_condition: FighterCondition.Id = FighterCondition.Id.HEALTHY

## The two bodies as they stood at `tick`. A decision reads an observation
## `reaction_ticks` old, and only one in several ticks decides, so the costly
## readings are taken (`resolve`) only for the observations a decision reads —
## from these, never from the live state.
var _me := FighterState.new()
var _them := FighterState.new()
var _resolved := false
## Per state class, its script variables as [name, is-object] pairs: read once,
## so keeping a body never walks the property list again.
static var _layouts: Dictionary = {}


## Everything at once: the observation and its costly readings.
static func observe(state: MatchState, slot: int, rules: DuelRules) -> CpuObservation:
	var seen := record(state, slot, rules)
	seen.resolve(rules)
	return seen


## The cheap readings now and the bodies kept; the threat predictions and the
## exposure read from them wait for `resolve`.
static func record(state: MatchState, slot: int, rules: DuelRules) -> CpuObservation:
	var seen := CpuObservation.new()
	seen.record_into(state, slot, rules)
	return seen


## The same, written over this observation (a kept one, reused): every reading
## is rewritten and the costly ones wait for `resolve` again.
func record_into(state: MatchState, slot: int, rules: DuelRules) -> void:
	var me := state.fighter(slot)
	var them := state.opponent_of(slot)
	_resolved = false
	tick = state.tick
	opp_facing = them.facing
	opp_x = them.x
	opp_y = them.y
	opp_vx = them.vx
	opp_vy = them.vy
	opp_phase = them.weapon.phase
	opp_charge = them.weapon.charge
	opp_commitment = them.weapon.commitment
	opp_swing_dir = them.weapon.swing_dir
	opp_point_threat = 0.0
	opp_condition = FighterCondition.classify(them.health, rules.spec_of(them).fighter.max_health)
	opp_exposure = 0.0
	opp_opening = 0.0
	my_threat_time = 0.0
	opp_threat_time = 0.0
	for estimate: ThreatEstimate in [my_threat, opp_threat]:
		estimate.within_horizon = false
		estimate.hit_time = 0.0
		estimate.residual_gap = 0.0
		estimate.readiness_remaining = 0.0
	_copy(me, _me)
	_copy(them, _them)


## Take the costly readings from the bodies as they stood at `tick`: one
## bounded threat prediction per side (THREAT-001), and the opponent's
## exposure as the physics reads it — how far behind me they are in
## time-to-threat (v36), from those same two predictions. A reading, never a
## damage factor. Taken once; later calls change nothing.
func resolve(rules: DuelRules) -> void:
	if _resolved:
		return
	_resolved = true
	InitiativeModel.estimate(_me, rules.spec_of(_me), _them, rules.spec_of(_them), rules.combat, my_threat)
	InitiativeModel.estimate(_them, rules.spec_of(_them), _me, rules.spec_of(_me), rules.combat, opp_threat)
	my_threat_time = my_threat.hit_time
	opp_threat_time = opp_threat.hit_time
	var late := opp_threat_time - my_threat_time
	opp_exposure = ExposureModel.reading_of(late, rules)
	## The delayed opponent's point against my current body (CPU-001).
	opp_point_threat = _point_threat(_them, _me, rules)
	opp_opening = ExposureModel.opening_of(late, rules)


## Proprioception (CPU-001, CPU-PROPRIOCEPTION-001): the CPU feels its own
## body and sword as they are now, and sees only the opponent through the
## delay. A decision hands its current self to the observation it reads;
## every costly reading is then taken from the current self and the delayed
## opponent. The cheap readings recorded with the observation (the opponent's
## position, phase, point threat) stay as seen.
func feel_self(me: FighterState) -> void:
	_copy(me, _me)
	_resolved = false


## What my strike would meet first if I pressed it now and closed at my own
## authority along the world direction (`route_x`, `route_y`) — the route I
## intend, not a generic close: the opponent's sword is swept under its own
## known law for the phase it was seen in, never its future input (CPU-008).
## Written into `out`.
func route_reading(rules: DuelRules, route_x: float, route_y: float, out: ThreatEstimate) -> ThreatEstimate:
	return InitiativeModel.estimate(_me, rules.spec_of(_me), _them, rules.spec_of(_them), rules.combat, out, ThreatContinuation.route(route_x, route_y))


## The opponent's threat against me in the same imagined world a route
## reading uses (CPU-008, one continuation): both swords swept, every heading
## tracking under its own law, each body at its current velocity — the
## opponent's footwork included, since its next input is not known. A route's
## arrival is compared against this, never against the unopposed close.
func opponent_threat_reading(rules: DuelRules, out: ThreatEstimate) -> ThreatEstimate:
	return InitiativeModel.estimate(_them, rules.spec_of(_them), _me, rules.spec_of(_me), rules.combat, out, ThreatContinuation.planted(true))


## Where the opponent's sword lies, as seen: its world angle (φ + θ).
func opp_blade_angle() -> float:
	return _them.facing + _them.weapon.angle


## Every script variable of `from` into `to`, nested state included, so a kept
## body is the whole body: a field added to the state later is kept too.
static func _copy(from: Object, to: Object) -> void:
	var layout: Array = _layout_of(from)
	for i in range(0, layout.size(), 2):
		var key: StringName = layout[i]
		if layout[i + 1]:
			_copy(from.get(key), to.get(key))
		else:
			to.set(key, from.get(key))


static func _layout_of(from: Object) -> Array:
	var script: Script = from.get_script()
	var layout: Array = _layouts.get(script, [])
	if layout.is_empty():
		for property: Dictionary in from.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			layout.append(StringName(property["name"]))
			layout.append(int(property["type"]) == TYPE_OBJECT)
		_layouts[script] = layout
	return layout


func opponent_swinging() -> bool:
	return CombatPhase.is_swinging(opp_phase)


## Recovering, overswinging, staggered, or out-angled by a clear margin.
func opponent_open() -> bool:
	return (
		opp_phase == CombatPhase.Id.OVERSWING
		or opp_phase == CombatPhase.Id.RECOVERY
		or opp_phase == CombatPhase.Id.STAGGER
		or opp_threat_time > my_threat_time + OPEN_MARGIN
	)


## Point-threat reading: how directly the opponent's sword tip aims at the
## CPU, weighted by closing velocity. Pure geometry over perceived state.
static func _point_threat(them: FighterState, me: FighterState, rules: DuelRules) -> float:
	var spec := rules.spec_of(them)
	var pose := WeaponKinematics.pose_of(them, spec, BladePose.new())
	var dx := me.x - pose.point_x(spec.weapon.tip_radius)
	var dy := me.y - pose.point_y(spec.weapon.tip_radius)
	var dist := SimMath.length(dx, dy)
	if dist <= SimMath.EPSILON:
		return 1.0
	var nx := dx / dist
	var ny := dy / dist
	var blade_dir_x := pose.ux
	var blade_dir_y := pose.uy
	var alignment := maxf(0.0, blade_dir_x * nx + blade_dir_y * ny)
	var closing := maxf(0.0, them.vx * nx + them.vy * ny)
	var speed_factor := SimMath.clamp01(closing / spec.fighter.max_speed)
	return alignment * (0.6 + 0.4 * speed_factor)
