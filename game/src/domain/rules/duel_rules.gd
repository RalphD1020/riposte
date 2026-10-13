class_name DuelRules
extends RefCounted

## Complete, immutable rule set for one duel — the match's physics context:
## one resolved `CombatantPhysicsSpec` per fighter slot, the combat tuning,
## the arena and the match format. Same rules + seed + commands → same result.
## Every value is authored in content; defaults here are neutral.
##
## The two combatants are independent (COMBATANT-GENERIC-001). Nothing here is
## "the" fighter or "the" weapon: a mirror match simply holds two equal specs,
## and a system that needs a fighter's physics asks `spec_of(fighter)`.
##
## Implements: /spec/invariants.md#sim-001
## Implements: /spec/invariants.md#combatant-generic-001
## See also: /docs/concepts/simulation.md
## Source: game/content/rules/standard_duel_rules.gd

## Replays pin rules by id + version; bump the version when any value changes.
var id: StringName = &""
var version: int = 0

## Indexed by fighter slot (`FighterState.slot`); exactly two.
var combatants: Array[CombatantPhysicsSpec] = []
var combat: CombatTuning

## Arena: circular, open edge (ring-out on crossing).
var arena_id: StringName = &""
var platform_radius: float = 0.0
var edge_warning_inset: float = 0.0
var spawn_offset: float = 0.0

## Match format. rounds_to_win = 3 is best of five.
var rounds_to_win: int = 0
var max_rounds: int = 0
var intro_ticks: int = 0
var result_ticks: int = 0
var round_time_limit_ticks: int = 0
## How long the winner controls the stage after a round ends (POST_ROUND_FREE).
var post_round_free_ticks: int = 0


## The physics of the fighter in `slot`.
func combatant(slot: int) -> CombatantPhysicsSpec:
	return combatants[slot]


## The physics of `fighter` — the one lookup every system uses.
func spec_of(fighter: FighterState) -> CombatantPhysicsSpec:
	return combatants[fighter.slot]


func is_valid() -> bool:
	return problem() == ""


## Why these rules cannot run a duel, or "" when they can. Invalid rules fail
## closed — no duel, never a substituted rule set or loadout (WEAPON-PATH-003,
## LOADOUT-001) — and this is the diagnostic that says which part is wrong.
func problem() -> String:
	if combatants.size() != 2 or combat == null:
		return "the two combatants or the combat tuning are missing"
	for slot in 2:
		if combatants[slot] == null:
			return "combatant %d is missing" % slot
		var loadout := combatants[slot].problem()
		if loadout != "":
			return "combatant %d: %s" % [slot, loadout]
	if not combat.is_valid():
		return "the combat tuning is invalid"
	if rounds_to_win <= 0 or max_rounds < rounds_to_win * 2 - 1 or round_time_limit_ticks <= 0 or post_round_free_ticks < 0:
		return "the match format is invalid"
	for slot in 2:
		var push := combatants[slot].fighter.push_radius
		if platform_radius <= spawn_offset + push or spawn_offset <= push:
			return "the arena cannot hold the fighters apart"
	return ""


## Visual warning ring radius, derived from the physical platform edge.
func warning_ring_radius() -> float:
	return platform_radius - edge_warning_inset
