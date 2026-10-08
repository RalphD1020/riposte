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
	## Sides are drawn 50/50 from the match seed (SIDE-001) rather than nailed
	## to the slot. Both cardinal spawns and both camera orientations then get
	## exercised by ordinary play, instead of the Dark path rotting unused
	## until the day someone turns on multiplayer.
	var light_slot := SeededRng.create(seed_value, SeededRng.STREAM_SIDES).next_int(0, 1)
	for slot in 2:
		state.fighters[slot].slot = slot
		state.fighters[slot].side = DuelSide.Id.LIGHT_SOUTH if slot == light_slot else DuelSide.Id.DARK_NORTH
	reset_round(state, rules)
	## Spawn positions must be inside the arena. Validated at content time, not
	## corrected at runtime — a spawn outside the boundary is authoring error.
	for fighter in state.fighters:
		var distance := SimMath.length(fighter.x, fighter.y)
		if distance >= rules.platform_radius:
			return null
	return state


static func reset_round(state: MatchState, rules: DuelRules) -> void:
	for slot in 2:
		reset_fighter(state.fighters[slot], rules)
	state.blade_contact.reset()
	for wbc in state.weapon_body_contacts:
		wbc.reset()
	state.body_contact.reset()
	state.round_ticks = 0
	state.round_winner = MatchPhase.NO_WINNER
	state.end_reason = &""


static func reset_fighter(fighter: FighterState, rules: DuelRules) -> void:
	## Cardinal spawns on the locked north-south axis, from the fighter's own
	## side rather than its slot (SIDE-001).
	fighter.x = 0.0
	fighter.y = DuelSide.spawn_y(fighter.side, rules.spawn_offset)
	fighter.vx = 0.0
	fighter.vy = 0.0
	fighter.ax = 0.0
	fighter.ay = 0.0
	fighter.facing = DuelSide.facing(fighter.side)
	fighter.turn_rate = 0.0
	## Seeded facing the opponent, so the very first tick of footwork already
	## has a meaningful duel axis instead of a default one.
	fighter.duel_forward_x = SimMath.cosine(fighter.facing)
	fighter.duel_forward_y = SimMath.sine(fighter.facing)
	fighter.health = rules.fighter.max_health
	fighter.stamina = rules.fighter.base_stamina
	fighter.stability = 1.0
	fighter.stagger_left = 0
	fighter.lethal_fraction = FighterState.ALIVE
	fighter.is_falling = false
	fighter.weapon.reset(-rules.weapon.guard_angle)
	fighter.gesture.reset()
	fighter.clear_attack_input()
