class_name DuelRules
extends RefCounted

## Complete, immutable rule set for one duel: fighter, weapon, combat tuning,
## arena, and match format. Same rules + seed + commands → same result.
## Every value is authored in content; defaults here are neutral.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md
## Source: game/content/rules/standard_duel_rules.gd

## Replays pin rules by id + version; bump the version when any value changes.
var id: StringName = &""
var version: int = 0

var fighter: FighterDefinition
var weapon: WeaponDefinition
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


func is_valid() -> bool:
	return (
		fighter != null
		and weapon != null
		and combat != null
		and fighter.is_valid()
		and weapon.is_valid()
		and combat.is_valid()
		and rounds_to_win > 0
		and max_rounds >= rounds_to_win * 2 - 1
		and platform_radius > spawn_offset + fighter.body_radius
		and spawn_offset > fighter.body_radius
		and round_time_limit_ticks > 0
		and post_round_free_ticks >= 0
	)


## Visual warning ring radius, derived from the physical platform edge.
func warning_ring_radius() -> float:
	return platform_radius - edge_warning_inset
