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
var my_threat_time: float = 0.0
var opp_threat_time: float = 0.0


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
	seen.my_threat_time = InitiativeModel.time_to_threat(me, them, rules)
	seen.opp_threat_time = InitiativeModel.time_to_threat(them, me, rules)
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
