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
var my_threat_time: float = 0.0
var opp_threat_time: float = 0.0
## How directly the opponent's sword tip is aimed at the CPU, in [0, 1].
## 1 = dead-on alignment with forward body motion; 0 = no point threat.
## Combines blade orientation with closing velocity (COMBAT-010).
var opp_point_threat: float = 0.0
## Opponent's condition band (FighterCondition). A coarse reading of injury.
var opp_condition: FighterCondition.Id = FighterCondition.Id.HEALTHY


static func observe(state: MatchState, slot: int, rules: DuelRules) -> CpuObservation:
	var me := state.fighter(slot)
	var them := state.opponent_of(slot)
	var seen := CpuObservation.new()
	seen.tick = state.tick
	seen.opp_x = them.x
	seen.opp_y = them.y
	seen.opp_vx = them.vx
	seen.opp_vy = them.vy
	seen.opp_phase = them.weapon.phase
	seen.opp_charge = them.weapon.charge
	seen.opp_commitment = them.weapon.commitment
	seen.opp_swing_dir = them.weapon.swing_dir
	var exposure := DamageModel.exposure(them, me, rules)
	seen.opp_exposure = SwingSemantics.exposure_fraction(exposure, rules.combat)
	seen.opp_opening = SwingSemantics.opening(exposure, rules.combat)
	seen.my_threat_time = InitiativeModel.time_to_threat(me, them, rules)
	seen.opp_threat_time = InitiativeModel.time_to_threat(them, me, rules)
	seen.opp_point_threat = _point_threat(them, me, rules)
	seen.opp_condition = FighterCondition.classify(them.health, rules.fighter.max_health)
	return seen


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
	var blade_angle := DuelGeometry.blade_angle(them)
	var tip_x := them.x + rules.weapon.tip_radius * cos(blade_angle)
	var tip_y := them.y + rules.weapon.tip_radius * sin(blade_angle)
	var dx := me.x - tip_x
	var dy := me.y - tip_y
	var dist := SimMath.length(dx, dy)
	if dist <= SimMath.EPSILON:
		return 1.0
	var nx := dx / dist
	var ny := dy / dist
	var blade_dir_x := cos(blade_angle)
	var blade_dir_y := sin(blade_angle)
	var alignment := maxf(0.0, blade_dir_x * nx + blade_dir_y * ny)
	var closing := maxf(0.0, them.vx * nx + them.vy * ny)
	var speed_factor := SimMath.clamp01(closing / rules.fighter.max_speed)
	return alignment * (0.6 + 0.4 * speed_factor)
