class_name DuelSetup
extends RefCounted

## Canonical initial and between-round state (PLAN Phase 8.4). Resets are
## deterministic: canonical positions, facing, sword state, and full health.
## Both fighters start right-handed: the sword rests on the right side.
##
## See also: /docs/concepts/simulation.md


static func new_state(rules: DuelRules, seed_value: int) -> MatchState:
	var state := MatchState.new()
	state.seed_value = seed_value
	state.fighters = [FighterState.new(), FighterState.new()]
	for slot in 2:
		state.fighters[slot].slot = slot
	reset_round(state, rules)
	return state


static func reset_round(state: MatchState, rules: DuelRules) -> void:
	for slot in 2:
		reset_fighter(state.fighters[slot], rules)
	state.blade_cooldown = 0
	state.round_ticks = 0
	state.round_winner = MatchPhase.NO_WINNER
	state.end_reason = &""


static func reset_fighter(fighter: FighterState, rules: DuelRules) -> void:
	var side := -1.0 if fighter.slot == 0 else 1.0
	fighter.x = side * rules.spawn_offset
	fighter.y = 0.0
	fighter.vx = 0.0
	fighter.vy = 0.0
	fighter.facing = 0.0 if fighter.slot == 0 else PI
	fighter.turn_rate = 0.0
	fighter.health = rules.fighter.max_health
	fighter.stability = 1.0
	fighter.stagger_left = 0
	fighter.weapon.reset(-rules.weapon.guard_angle)
	fighter.clear_attack_input()
