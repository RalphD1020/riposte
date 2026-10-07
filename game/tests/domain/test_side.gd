extends TestCase

## SIDE: cardinal sides, seeded assignment, and the one locked world
## orientation (SIDE-001).
##
## The property being protected is that the arena has a fixed north and south
## and no "front". Everything a player sees that looks like a front — their
## spawn, their facing, their camera — is derived from their side, and side is
## derived from the seed rather than from which slot they happen to occupy.
##
## Implements: /spec/invariants.md#side-001
## See also: /docs/concepts/combat.md


func _init() -> void:
	suite_name = "SIDE"


func _rules() -> DuelRules:
	return StandardDuelRules.create()


func test_each_end_of_the_arena_has_exactly_one_fighter() -> void:
	var rules := _rules()
	for seed_value in PackedInt32Array([1, 2, 3, 7, 19, 404]):
		var state := DuelSetup.new_state(rules, seed_value)
		assert_true(
			state.fighter(0).side != state.fighter(1).side, "seed %d puts the two fighters at opposite ends" % seed_value
		)
		assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "and the state is coherent")


func test_two_fighters_on_one_side_is_rejected() -> void:
	## Both at the same end would stack the spawns and leave the camera with
	## no honest answer about who is at the bottom of the screen.
	var rules := _rules()
	var state := DuelSetup.new_state(rules, 1)
	assert_eq(StateInvariants.check(state, rules), StateInvariants.OK, "precondition: a real match is coherent")
	state.fighter(1).side = state.fighter(0).side
	assert_eq(StateInvariants.check(state, rules), StateInvariants.SIDE_COLLISION, "a duel with one end is impossible")


func test_light_spawns_south_facing_north_and_dark_the_reverse() -> void:
	var rules := _rules()
	var state := DuelSetup.new_state(rules, 1)
	for fighter in state.fighters:
		assert_eq(fighter.x, 0.0, "spawns sit on the centre line")
		if fighter.side == DuelSide.Id.LIGHT_SOUTH:
			assert_near(fighter.y, -rules.spawn_offset, 1e-12, "Light's home is south")
			assert_near(fighter.facing, DuelSide.NORTH_FACING, 1e-12, "and it looks north")
		else:
			assert_near(fighter.y, rules.spawn_offset, 1e-12, "Dark's home is north")
			assert_near(fighter.facing, DuelSide.SOUTH_FACING, 1e-12, "and it looks south")
	## Facing each other is the point, not a coincidence of the constants.
	var a := state.fighter(0)
	var b := state.fighter(1)
	var toward_b_x := b.x - a.x
	var toward_b_y := b.y - a.y
	assert_true(
		SimMath.cosine(a.facing) * toward_b_x + SimMath.sine(a.facing) * toward_b_y > 0.0,
		"each fighter opens the duel looking at the other"
	)


func test_side_is_drawn_from_the_seed_not_from_the_slot() -> void:
	## If side were pinned to the slot, the Dark spawn and the flipped camera
	## would never be exercised by ordinary play and would rot until the day
	## someone turned on multiplayer.
	var rules := _rules()
	var slot_zero_light := 0
	var slot_zero_dark := 0
	for seed_value in range(1, 41):
		var state := DuelSetup.new_state(rules, seed_value)
		if state.fighter(0).side == DuelSide.Id.LIGHT_SOUTH:
			slot_zero_light += 1
		else:
			slot_zero_dark += 1
	assert_true(slot_zero_light > 0, "slot 0 is sometimes Light")
	assert_true(slot_zero_dark > 0, "and sometimes Dark")
	## Not a fairness claim about the generator, just that neither outcome is
	## vanishingly rare: a 39-1 split would make the test above vacuous.
	assert_between(float(slot_zero_light) / 40.0, 0.25, 0.75, "and neither end is rare")


func test_the_same_seed_always_gives_the_same_sides() -> void:
	var rules := _rules()
	var first := DuelSetup.new_state(rules, 12345)
	var second := DuelSetup.new_state(rules, 12345)
	assert_eq(second.fighter(0).side, first.fighter(0).side, "replay-stable")
	assert_eq(StateHasher.hash_state(second), StateHasher.hash_state(first), "and identical down to the hash")


func test_side_survives_a_round_reset() -> void:
	## Sides are match identity, not round state: swapping ends between rounds
	## would move a player's camera mid-match.
	var rules := _rules()
	var state := DuelSetup.new_state(rules, 9)
	var sides := PackedInt32Array([state.fighter(0).side, state.fighter(1).side])
	state.fighter(0).y = 4.0
	DuelSetup.reset_round(state, rules)
	assert_eq(state.fighter(0).side, sides[0] as DuelSide.Id, "slot 0 keeps its end")
	assert_eq(state.fighter(1).side, sides[1] as DuelSide.Id, "and so does slot 1")
	assert_near(state.fighter(0).y, DuelSide.spawn_y(state.fighter(0).side, rules.spawn_offset), 1e-12, "back at that end")


func test_side_is_authoritative_state() -> void:
	## It decides where fighters stand, so it has to be covered by the hash or
	## a tampered replay could quietly swap the arena around.
	var state := DuelSetup.new_state(_rules(), 5)
	var before := StateHasher.hash_state(state)
	state.fighter(0).side = DuelSide.other(state.fighter(0).side)
	assert_true(StateHasher.hash_state(state) != before, "changing a side changes the hash")


func test_side_assignment_does_not_disturb_the_other_streams() -> void:
	## Sides draw from their own stream, so adding this draw must not have
	## shifted what the CPUs roll for a given seed.
	var sides := SeededRng.create(77, SeededRng.STREAM_SIDES)
	var cpu := SeededRng.create(77, SeededRng.cpu_stream(0))
	assert_true(SeededRng.STREAM_SIDES != SeededRng.cpu_stream(0), "precondition: distinct streams")
	assert_true(SeededRng.STREAM_SIDES != SeededRng.cpu_stream(1), "for both slots")
	assert_true(sides.next_float() != cpu.next_float(), "and they do not produce the same sequence")


func test_duel_axes_mean_the_same_thing_at_both_ends() -> void:
	## Closing the measure must be the same command for a Light fighter and a
	## Dark one, even though it is the opposite world direction. This is what
	## lets one command language serve both ends (MOVE-001).
	var rules := _rules()
	var state := DuelSetup.new_state(rules, 1)
	for slot in 2:
		var me := state.fighter(slot)
		var them := state.opponent_of(slot)
		var before := SimMath.length(them.x - me.x, them.y - me.y)
		for tick in 20:
			MovementSystem.step(me, them, 0.0, 1.0, tick, rules.fighter)
		var after := SimMath.length(them.x - me.x, them.y - me.y)
		assert_true(after < before, "pushing forward closes the measure from the %s end" % DuelSide.label(me.side))


## The payoff of the whole scheme. Swap which end each slot holds, feed the
## identical duel-relative commands, and the duel must play out the same — the
## fighters just stand somewhere else. Anything that differed would be an
## end-of-arena advantage, which is the one thing cardinal sides exist to rule
## out.
func test_swapping_ends_leaves_the_duel_unchanged() -> void:
	var rules := _rules()
	var scripted := PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, -1.0, 0.0, 0.0, -1.0, 0.0])
	var histories: Array[PackedFloat64Array] = []
	for swapped in 2:
		var state := DuelSetup.new_state(rules, 31)
		if swapped == 1:
			for slot in 2:
				state.fighters[slot].side = DuelSide.other(state.fighter(slot).side)
			DuelSetup.reset_round(state, rules)
		var measures := PackedFloat64Array()
		var tick := 0
		for deflection in scripted:
			for slot in 2:
				MovementSystem.step(state.fighter(slot), state.opponent_of(slot), 0.3, deflection, tick, rules.fighter)
			measures.append(DuelGeometry.distance(state.fighter(0), state.fighter(1)))
			tick += 1
		histories.append(measures)
	assert_eq(histories[0].size(), scripted.size(), "precondition: a full history was recorded")
	assert_true(histories[0][0] != histories[0][histories[0].size() - 1], "precondition: the script actually moved them")
	for i in histories[0].size():
		assert_near(histories[1][i], histories[0][i], 1e-9, "the measure evolves identically with the ends swapped (tick %d)" % i)


func test_orbiting_is_mirror_opposite_in_world_space() -> void:
	## The two ends are genuinely opposite, not accidentally identical: the
	## same local "step right" moves the two fighters in opposite world
	## directions. If it did not, one of them would be orbiting the wrong way.
	var rules := _rules()
	var state := DuelSetup.new_state(rules, 1)
	var displacement := PackedFloat64Array([0.0, 0.0])
	for slot in 2:
		var me := state.fighter(slot)
		var start := me.x
		for tick in 20:
			MovementSystem.step(me, state.opponent_of(slot), 1.0, 0.0, tick, rules.fighter)
		displacement[slot] = me.x - start
	assert_true(absf(displacement[0]) > 0.1, "precondition: both actually moved")
	assert_true(absf(displacement[1]) > 0.1, "precondition: measurably")
	assert_true(displacement[0] * displacement[1] < 0.0, "local right is opposite world directions at opposite ends")
