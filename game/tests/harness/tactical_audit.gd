class_name TacticalAudit
extends RefCounted

## Opportunity → Action → Outcome accounting for a duel, per fighter.
##
## A win rate cannot say which decision went wrong. Difficulty is a claim
## about decision quality (CPU-004), so it has to be measured as decisions:
## how often a tactical situation actually arose, and how often the fighter
## answered it the way a competent fencer would.
##
## Every metric therefore carries its **support** — the number of eligible
## situations — beside its success rate, and a rate whose support is too thin
## reports `INSUFFICIENT_SUPPORT` rather than a percentage (CPU-005). "100%
## punish rate" over three opportunities is not a result, and reporting it as
## a pass is how a balance document comes to state things nobody measured.
##
## Opportunities are counted per **episode**, not per tick. An opponent in
## recovery for forty ticks is one chance to punish, and counting it forty
## times would turn a single decision into a statistic.
##
## Pure observation: reads `MatchState` and changes nothing. Dev-only, so it
## lives beside the harness rather than in `src`.
##
## Implements: /spec/invariants.md#cpu-005
## See also: /docs/concepts/cpu.md, /game/tools/balance_report.gd

enum Verdict { PASS, FAIL, INSUFFICIENT_SUPPORT }

## Phases in which a fighter has spent their action and cannot answer yet.
const PUNISHABLE: Array[CombatPhase.Id] = [CombatPhase.Id.OVERSWING, CombatPhase.Id.RECOVERY, CombatPhase.Id.STAGGER]
## Phases in which the blade is committed and travelling.
const COMMITTED: Array[CombatPhase.Id] = [CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE]
## A strike released beyond reach by more than this (m) was never going to
## land. Derived from the blade, not chosen: it is the distance at which the
## tip cannot arrive even if the target stands still.
const BAD_MEASURE_MARGIN := 0.35
## A wind-back this far is visible to a watching fencer and worth a stop-hit.
## Read from `charge`, the physical wind-back, and not from `commitment`:
## commitment during CHARGING is scaled down by the phase factor, so a
## threshold that looks like "a quarter committed" is never reached and the
## metric silently reports zero opportunities instead of none existing.
const CHARGE_WINDBACK := 0.25


## One measured behaviour: how often it was possible, how often it happened,
## and what would count as competent.
class Metric:
	extends RefCounted

	var label: String
	## Minimum eligible situations before a rate means anything.
	var support_floor: int
	## Rate a competent fighter should reach, or stay under when inverted.
	var target: float
	## True when a *low* rate is the competent answer (attacking from bad
	## measure is a mistake, not a skill).
	var inverted: bool
	var support: int = 0
	var taken: int = 0

	static func create(metric_label: String, floor_support: int, floor_rate: float, invert: bool = false) -> Metric:
		var metric := Metric.new()
		metric.label = metric_label
		metric.support_floor = floor_support
		metric.target = floor_rate
		metric.inverted = invert
		return metric

	func rate() -> float:
		return 0.0 if support == 0 else float(taken) / float(support)

	func verdict() -> Verdict:
		if support < support_floor:
			return Verdict.INSUFFICIENT_SUPPORT
		if inverted:
			return Verdict.PASS if rate() <= target else Verdict.FAIL
		return Verdict.PASS if rate() >= target else Verdict.FAIL


var slot: int
var rules: DuelRules
var punish: Metric
var intercept: Metric
var angular_escape: Metric
var bind_yield: Metric
var bad_measure: Metric
var whiff: Metric
var total_ticks: int = 0
var ideal_measure_ticks: int = 0

## Episode bookkeeping. Each is -1 when no episode is open, otherwise the tick
## it opened, so an answer can be attributed to the chance that invited it.
var _punish_open: int = -1
var _intercept_open: int = -1
var _escape_open: int = -1
var _bind_open: int = -1
var _escape_lateral: float = 0.0
var _escape_radial: float = 0.0
var _was_launching: bool = false
var _bind_was_weak: bool = false
var _swing_resolved: bool = true


## Floors are design targets to test against, not laws of fencing. They are
## monotone across difficulty by construction, which is the property that
## actually matters: Hard must be better at these than Medium, and Medium
## better than Easy, whatever the absolute numbers settle at.
static func create(fighter_slot: int, duel_rules: DuelRules, difficulty: MatchConfig.Difficulty) -> TacticalAudit:
	var audit := TacticalAudit.new()
	audit.slot = fighter_slot
	audit.rules = duel_rules
	var tier := _tier(difficulty)
	audit.punish = Metric.create("punish clear whiff", 100, tier[0])
	audit.intercept = Metric.create("intercept committed charge", 100, tier[1])
	audit.angular_escape = Metric.create("escape angularly, not backwards", 100, tier[2])
	audit.bind_yield = Metric.create("yield a losing bind", 100, tier[3])
	audit.bad_measure = Metric.create("release from hopeless measure", 100, tier[4], true)
	audit.whiff = Metric.create("swing without contact", 100, tier[5], true)
	return audit


## punish, intercept, angular escape, bind yield, bad-measure release (max), whiff (max).
static func _tier(difficulty: MatchConfig.Difficulty) -> PackedFloat64Array:
	match difficulty:
		MatchConfig.Difficulty.EASY:
			return PackedFloat64Array([0.30, 0.15, 0.20, 0.20, 0.40, 0.60])
		MatchConfig.Difficulty.HARD:
			return PackedFloat64Array([0.85, 0.75, 0.80, 0.85, 0.08, 0.15])
	return PackedFloat64Array([0.60, 0.50, 0.55, 0.60, 0.20, 0.35])


## Call once per tick, after the step. Order matters only in that an episode
## is opened and answered from the same reading of the world.
func observe(state: MatchState) -> void:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		return
	var me := state.fighter(slot)
	var them := state.fighter(1 - slot)
	if not me.is_alive() or not them.is_alive():
		return
	total_ticks += 1
	var gap := DuelGeometry.distance(me, them)
	var reach := rules.weapon.tip_radius + rules.fighter.body_radius
	if gap <= reach and gap >= reach - rules.weapon.blade_length():
		ideal_measure_ticks += 1
	var launched := _launched(me)
	_score_whiff(me, launched)
	_score_bad_measure(launched, gap, reach)
	_score_punish(me, them, launched, state.tick)
	_score_intercept(me, them, launched, gap, reach, state.tick)
	_score_angular_escape(me, them, gap, reach, state.tick)
	_score_bind_yield(me, them, state.tick)


## A release is a phase edge into LAUNCH, read from state rather than from the
## event stream so the audit needs nothing but the state it is given.
func _launched(me: FighterState) -> bool:
	var launching := me.weapon.phase == CombatPhase.Id.LAUNCH
	var edge := launching and not _was_launching
	_was_launching = launching
	return edge


## Releasing at a distance the tip cannot reach is a mistake with no upside,
## which makes it the cleanest single read on measure discipline.
func _score_bad_measure(launched: bool, gap: float, reach: float) -> void:
	if not launched:
		return
	bad_measure.support += 1
	if gap > reach + BAD_MEASURE_MARGIN:
		bad_measure.taken += 1


## The opponent has spent their action and cannot answer. One episode per
## recovery, answered by releasing into it.
func _score_punish(me: FighterState, them: FighterState, launched: bool, tick: int) -> void:
	var open := PUNISHABLE.has(them.weapon.phase)
	if open and _punish_open < 0:
		## Only a chance we could actually take: our own blade must be free.
		if me.weapon.phase == CombatPhase.Id.NEUTRAL or me.weapon.phase == CombatPhase.Id.CHARGING:
			_punish_open = tick
			punish.support += 1
	elif not open and _punish_open >= 0:
		_punish_open = -1
	if _punish_open >= 0 and launched:
		punish.taken += 1
		_punish_open = -1


## The opponent is winding back inside the distance a short strike covers.
## A tap arrives before a charge does, which is the whole point of a stop-hit.
func _score_intercept(me: FighterState, them: FighterState, launched: bool, gap: float, reach: float, tick: int) -> void:
	var charging := them.weapon.phase == CombatPhase.Id.CHARGING and them.weapon.charge >= CHARGE_WINDBACK
	var open := charging and gap <= reach and me.weapon.phase != CombatPhase.Id.RECOVERY
	if open and _intercept_open < 0:
		_intercept_open = tick
		intercept.support += 1
	elif not charging and _intercept_open >= 0:
		_intercept_open = -1
	if _intercept_open >= 0 and launched:
		intercept.taken += 1
		_intercept_open = -1


## Their blade is committed and travelling. Backing straight up along the line
## of the attack keeps us in it; stepping across the swing increases their
## tracking demand and puts us in the recovery wake. Measured as which
## component of our own movement dominated over the episode.
func _score_angular_escape(me: FighterState, them: FighterState, gap: float, reach: float, tick: int) -> void:
	var open := COMMITTED.has(them.weapon.phase) and gap <= reach + BAD_MEASURE_MARGIN
	if open:
		if _escape_open < 0:
			_escape_open = tick
			_escape_lateral = 0.0
			_escape_radial = 0.0
			angular_escape.support += 1
		## Our velocity resolved about them: radial is along the line between
		## us, lateral is around it.
		var to_x := me.x - them.x
		var to_y := me.y - them.y
		var span := sqrt(to_x * to_x + to_y * to_y)
		if span > SimMath.EPSILON:
			var nx := to_x / span
			var ny := to_y / span
			_escape_radial += absf(me.vx * nx + me.vy * ny)
			_escape_lateral += absf(me.vx * -ny + me.vy * nx)
		return
	if _escape_open >= 0:
		if _escape_lateral > _escape_radial:
			angular_escape.taken += 1
		_escape_open = -1


## Strong on weak controls the bind; weak on strong should yield rather than
## push. Leverage here is the blade's own authority in the bind — how much
## speed it still carries and how committed it is — so the weaker party is
## the one that should be leaving.
func _score_bind_yield(me: FighterState, them: FighterState, tick: int) -> void:
	var bound := me.weapon.phase == CombatPhase.Id.BIND
	if bound and _bind_open < 0:
		_bind_open = tick
		_bind_was_weak = me.weapon.commitment < them.weapon.commitment
		if _bind_was_weak:
			bind_yield.support += 1
		return
	if bound or _bind_open < 0:
		return
	## The bind ended. Yielding means leaving it without having thrown a
	## committed strike out of a position that could not support one.
	if _bind_was_weak and me.weapon.phase != CombatPhase.Id.LAUNCH:
		bind_yield.taken += 1
	_bind_open = -1


## A swing that completes without contacting anything is a whiff. Each swing
## scores exactly once: the episode opens on launch and closes when the swing
## resolves into OVERSWING, RECOVERY, or NEUTRAL.
func _score_whiff(me: FighterState, launched: bool) -> void:
	if launched:
		_swing_resolved = false
		whiff.support += 1
	if _swing_resolved:
		return
	var resolved := (
		me.weapon.phase == CombatPhase.Id.OVERSWING
		or me.weapon.phase == CombatPhase.Id.RECOVERY
		or me.weapon.phase == CombatPhase.Id.NEUTRAL
	)
	if not resolved:
		return
	_swing_resolved = true
	if not me.weapon.swing_contact:
		whiff.taken += 1


func metrics() -> Array[Metric]:
	return [punish, intercept, angular_escape, bind_yield, bad_measure, whiff]


## Fold another duel's counts in, so a corpus of seeds reports one support
## total rather than a verdict per duel that nothing can be concluded from.
func absorb(other: TacticalAudit) -> void:
	var mine := metrics()
	var theirs := other.metrics()
	for index in mine.size():
		mine[index].support += theirs[index].support
		mine[index].taken += theirs[index].taken
	ideal_measure_ticks += other.ideal_measure_ticks
	total_ticks += other.total_ticks


static func verdict_label(verdict: Verdict) -> String:
	match verdict:
		Verdict.PASS:
			return "PASS"
		Verdict.FAIL:
			return "FAIL"
	return "INSUFFICIENT_SUPPORT"
