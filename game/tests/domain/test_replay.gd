extends TestCase

## REPLAY: same commands → same duel; records verify; tampering is caught;
## random play never breaks state invariants (COMBAT §77, PLAN Phase 16).
##
## Implements: /spec/invariants.md#sim-002
## See also: /docs/concepts/simulation.md

const TICKS := 1800


func _init() -> void:
	suite_name = "REPLAY"


func _played(seed_value: int, keep_hashes: bool = false) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.rules(), seed_value)
	runner.run(Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23), TICKS, keep_hashes)
	return runner


func test_identical_commands_reproduce_identical_duels() -> void:
	var first := _played(5, true)
	var second := _played(5, true)
	assert_true(first.count(DuelEventTypes.ATTACK_RELEASED) > 10, "precondition: plenty of attacks")
	assert_true(first.count(DuelEventTypes.BODY_HIT) + first.count(DuelEventTypes.BLADE_CONTACT) > 3, "precondition: real contacts")
	assert_eq(first.hashes.size(), second.hashes.size(), "same length")
	assert_eq(first.hashes, second.hashes, "every tick hash matches")


func test_different_seeds_diverge() -> void:
	assert_ne(_played(5).record.final_hash, _played(6).record.final_hash, "different inputs, different duels")


func test_record_verifies_and_tampering_is_caught() -> void:
	var runner := _played(9)
	var rules := DuelFixture.rules()
	assert_eq(ReplayVerifier.verify(runner.record, rules), ReplayVerifier.VERIFIED, "honest record verifies")
	var forged := ReplayRecord.from_dictionary(runner.record.to_dictionary())
	for index in range(1, forged.commands_0.size(), PlayerCommand.PACKED_STRIDE):
		forged.commands_0[index] = -forged.commands_0[index]
	assert_eq(ReplayVerifier.verify(forged, rules), ReplayVerifier.HASH_MISMATCH, "a forged command stream is detected")
	rules.version += 1
	assert_eq(ReplayVerifier.verify(runner.record, rules), ReplayVerifier.RULES_MISMATCH, "replays pin their rules")


func test_record_survives_json() -> void:
	var runner := _played(3)
	var text := JSON.stringify(runner.record.to_dictionary())
	var restored := ReplayRecord.from_dictionary(JSON.parse_string(text) as Dictionary)
	assert_true(restored != null, "parsed back")
	assert_eq(restored.tick_count(), runner.record.tick_count(), "same length")
	assert_eq(ReplayVerifier.verify(restored, DuelFixture.rules()), ReplayVerifier.VERIFIED, "still verifies after JSON")
	assert_true(ReplayRecord.from_dictionary({"format": 99}) == null, "unknown format rejected")
	assert_true(ReplayRecord.from_dictionary({"format": 1, "commands_0": [1, 2, 3], "commands_1": []}) == null, "malformed streams rejected")


func test_hash_sees_the_smallest_change() -> void:
	var state := DuelFixture.state(DuelFixture.rules())
	var before := StateHasher.hash_state(state)
	state.fighter(1).weapon.angle += 1e-12
	assert_ne(StateHasher.hash_state(state), before, "one ulp-scale change alters the hash")


func test_random_play_never_breaks_state_invariants() -> void:
	var rules := DuelFixture.rules()
	var violations := PackedStringArray()
	var contacts := 0
	for seed_value: int in [1, 2, 3, 4]:
		var runner := SimRunner.create(rules, seed_value)
		var pilot_0 := Pilot.wander(seed_value, 31)
		var pilot_1 := Pilot.wander(seed_value, 47)
		for _tick in TICKS:
			if runner.state.is_finished():
				break
			var events := runner.simulation.step(runner.state, pilot_0.command(runner.state, 0), pilot_1.command(runner.state, 1))
			for event in events:
				if event.type == DuelEventTypes.BODY_HIT or event.type == DuelEventTypes.BLADE_CONTACT:
					contacts += 1
			_check(runner.state, rules, violations)
	assert_true(contacts > 10, "precondition: the fights made contact (%d)" % contacts)
	assert_eq(violations.size(), 0, "invariants held: %s" % ", ".join(violations.slice(0, 5)))


func _check(state: MatchState, rules: DuelRules, violations: PackedStringArray) -> void:
	for fighter in state.fighters:
		var w := fighter.weapon
		for value: float in [fighter.x, fighter.y, fighter.vx, fighter.vy, fighter.facing, fighter.turn_rate, w.angle, w.speed]:
			if not is_finite(value):
				violations.append("non-finite value at tick %d" % state.tick)
		if fighter.health < 0.0 or fighter.health > rules.fighter.max_health:
			violations.append("health out of range at tick %d" % state.tick)
		if SimMath.length(fighter.x, fighter.y) > rules.arena_radius - rules.fighter.body_radius + 1e-9:
			violations.append("left the arena at tick %d" % state.tick)
		if absf(w.angle) > rules.weapon.guard_limit + 1e-12:
			violations.append("blade beyond guard at tick %d" % state.tick)
		if w.charge < 0.0 or w.charge > 1.0:
			violations.append("charge out of range at tick %d" % state.tick)
	if DuelGeometry.distance(state.fighter(0), state.fighter(1)) < rules.fighter.body_radius * 2.0 - 1e-9:
		violations.append("bodies overlap at tick %d" % state.tick)
