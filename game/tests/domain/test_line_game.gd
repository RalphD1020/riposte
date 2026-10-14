extends TestCase

## LINE-GAME: the line game as play (LINE-CHANGE-001, KNIFE-EDGE-LINE-001) —
## ordinary commands for the reading fighter, a Hard CPU for the other once its
## cut is out, real physics throughout. ATTACK owns the mechanism witnesses
## (what one cut meets from each side); this suite owns what that does to the
## exchange: who lands first.
##
## Implements: /spec/invariants.md#line-change-001
## Implements: /spec/invariants.md#knife-edge-line-001
## See also: /docs/reference/testing.md


func _init() -> void:
	suite_name = "LINE-GAME"


## HUMAN-CAPITALIZE-001 (ATTACK-SIDE-001, CPU-008's human twin), from a
## searched state: what a person can do with ordinary commands, no CPU, no
## predictor, no state edit after the setup. Shipping rules, 1.3 m apart,
## inside reach: the attacker taps once from rest (θ −45° → +45°, swing_dir +1)
## and is then played by a Hard CPU. The defender reads it: 4 ticks before the
## press it walks toward the cut's origin side for 5 ticks, then walks
## straight in and presses the moment its own sword is free. BEHIND THE BLADE:
## the tap meets the defender's steel instead of its body, and the defender
## lands the first body hit. CONTROL (no step): the tap also meets steel, but
## the CPU lands first — the line, not the clash, made the opening. INTO THE
## BLADE: the defender is struck. MIRROR: the same, on the same tick.
func test_a_person_can_take_the_line_and_land_first() -> void:
	var rules := StandardDuelRules.create()
	## ARRANGE + ACT
	var behind := _answered_tap(rules, "origin", false)
	var still := _answered_tap(rules, "none", false)
	var into := _answered_tap(rules, "end", false)
	var mirrored := _answered_tap(rules, "origin", true)
	## ASSERT
	assert_eq(behind.result, "steel", "behind the blade, the tap meets steel, not the body")
	assert_eq(behind.landed, "defender", "and the defender, walking in, lands the first body hit")
	assert_eq(still.result, "steel", "control: without the step the tap is met by steel too")
	assert_eq(still.landed, "attacker", "but then the attacker lands first — the step made the opening")
	assert_eq(into.result, "body", "into the blade, the defender is struck")
	assert_eq(mirrored.result, behind.result, "mirrored: the same contact")
	assert_eq(mirrored.landed, behind.landed, "the same winner")
	assert_eq(mirrored.landed_tick, behind.landed_tick, "on the same tick (%d)" % behind.landed_tick)


## The attacker (slot 0) taps once and is then a Hard CPU; the defender (slot
## 1), `distance` away, walks toward the cut's `side` from `lead` ticks before
## the press for `walk` ticks ("none": stands), then walks straight in pressing
## whenever its sword is neutral. Stops at the first body hit after the tap.
func _answered_tap(rules: DuelRules, side: String, mirror: bool, distance: float = 1.3, lead: int = -4, walk: int = 5) -> AnsweredTap:
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var attacker := runner.state.fighter(0)
	var defender := runner.state.fighter(1)
	var reflect := -1.0 if mirror else 1.0
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	DuelFixture.place(defender, distance, 0.0, PI)
	attacker.weapon.reset(-reflect * rules.combatant(0).weapon.guard_angle)
	defender.weapon.reset(-reflect * rules.combatant(1).weapon.guard_angle)
	var cpu := CpuController.create(rules, CpuProfile.hard(), 5, 0)
	## Room for the earliest step: the step starts `lead` ticks before the press.
	var press := runner.state.tick + maxi(4, -lead)
	var step_from := press + lead
	var direction := Vector2.ZERO
	var out := AnsweredTap.new()
	var tap_over := false
	for _t in 240:
		var state := runner.state
		if state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
		var tick := state.tick
		var attack := cpu.command_for(state, 0) if tap_over else PlayerCommand.create(tick, 0.0, 0.0, tick == press, tick == press)
		if tick == step_from and side != "none":
			direction = CutGeometry.origin_side(attacker) if side == "origin" else CutGeometry.end_side(attacker)
		var answer := PlayerCommand.idle(tick)
		if tick >= step_from and tick < step_from + walk and side != "none":
			var step := CutGeometry.step_intent(defender, attacker, direction)
			answer = PlayerCommand.create(tick, step.x, step.y)
		elif tick >= step_from + walk and out.result != "":
			var inward := CutGeometry.step_intent(defender, attacker, Vector2(attacker.x - defender.x, attacker.y - defender.y).normalized())
			var free := defender.weapon.phase == CombatPhase.Id.NEUTRAL
			answer = PlayerCommand.create(tick, inward.x, inward.y, free, free)
		var seen := runner.events.size()
		runner.push(attack, answer)
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if out.result == "":
				if event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
					out.result = "body"
				elif event.type == DuelEventTypes.BLADE_CONTACT:
					out.result = "steel"
			elif event.type == DuelEventTypes.BODY_HIT and out.landed == "":
				out.landed = "defender" if event.actor == 1 else "attacker"
				out.landed_tick = event.tick - press
		if not tap_over and tick > press and attacker.weapon.phase != CombatPhase.Id.LAUNCH and not CombatPhase.is_swinging(attacker.weapon.phase):
			tap_over = true
		if out.landed != "":
			break
	return out


## LINE-CHANGE-001 relationship grid (KNIFE-EDGE-LINE-001): over a small grid
## of measures inside reach and read timings, the same planted tap, the same
## ordinary human answer, the attacker then a Hard CPU. Stepping behind the
## blade must be struck less often than stepping into it, and must land the
## first answer more often — orderings, never the rates themselves.
func test_behind_the_blade_beats_into_it_across_measure_and_timing() -> void:
	var rules := StandardDuelRules.create()
	var struck := {"origin": 0, "end": 0}
	var first := {"origin": 0, "end": 0}
	var runs := 0
	for distance: float in [1.35, 1.5, 1.65, 1.8]:
		for lead: int in [-6, -4, -2]:
			runs += 1
			for side: String in ["origin", "end"]:
				## ARRANGE + PERTURB + ACT
				var answered := _answered_tap(rules, side, false, distance, lead, 6)
				## A tap that struck the body was the first to land.
				if answered.result == "body":
					struck[side] += 1
				elif answered.landed == "defender":
					first[side] += 1
	## ASSERT
	assert_eq(runs, 12, "fixture: the whole grid was played")
	assert_true(struck["origin"] < struck["end"], "behind the blade is struck less often than into it (%d vs %d of %d)" % [struck["origin"], struck["end"], runs])
	assert_true(first["origin"] > first["end"], "and lands the first answer more often (%d vs %d of %d)" % [first["origin"], first["end"], runs])


## FIRST-CONTACT-002 (THREAT-AGREEMENT-AUDIT's canonical regression): a state
## from live play — Hard v Medium, audit seed 204, tick 120, slot 0 walks
## straight in pressing its tap as soon as it can, the opponent keeping its
## velocity. The steel-aware prediction says the strike reaches flesh. In the
## real fork the cut grazes the opponent's handle and carries on into the body
## in the same tick: a graze that does not stop a cut is not a block, so the
## prediction was right and the strike is a hit, not a contact on steel.
func test_a_handle_graze_that_carries_through_is_the_hit_the_prediction_saw() -> void:
	## ARRANGE: the live state.
	var rules := StandardDuelRules.create()
	var duel := CpuLadder.session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, 204)
	while duel.state.tick < 120:
		duel.step()
	var me := duel.state.fighter(0)
	var them := duel.state.fighter(1)
	var line := Vector2(them.x - me.x, them.y - me.y).normalized()
	## ACT: the prediction, then the real fork under the same continuation.
	var predicted := InitiativeModel.estimate(me, rules.spec_of(me), them, rules.spec_of(them), rules.combat, ThreatEstimate.new(), ThreatContinuation.route(line.x, line.y))
	var fork := SimRunner.create(duel.config.rules, duel.state.seed_value)
	StateFork.copy(duel.state, fork.state)
	var drift := Vector2(them.vx, them.vy)
	var share := clampf(drift.length() / rules.spec_of(them).fighter.max_speed, 0.0, 1.0)
	var grazed := -1
	var struck := -1
	for _t in 20:
		var tick := fork.state.tick
		var a := fork.state.fighter(0)
		var b := fork.state.fighter(1)
		var step := CutGeometry.step_intent(a, b, line)
		var press := struck < 0 and WeaponSystem.can_start_attack(a, rules.spec_of(a).weapon)
		var keep := CutGeometry.step_intent(b, a, drift.normalized()) * share
		var seen := fork.events.size()
		fork.push(PlayerCommand.create(tick, step.x, step.y, press, press), PlayerCommand.create(tick, keep.x, keep.y))
		for i in range(seen, fork.events.size()):
			var event: DuelEvent = fork.events[i]
			if event.type == DuelEventTypes.BLADE_CONTACT and grazed < 0 and int(event.data[DuelEventKeys.FEATURE_1]) == SwordContactSet.Feature.HILT:
				grazed = event.tick
			if event.type == DuelEventTypes.BODY_HIT and event.actor == 0 and struck < 0:
				struck = event.tick
		if struck >= 0:
			break
	## ASSERT
	assert_false(predicted.starts_bound, "fixture: the swords start clear")
	assert_true(predicted.first_contact == ThreatEstimate.BODY or predicted.first_contact == ThreatEstimate.HAND, "the prediction says the strike reaches flesh (%d)" % predicted.first_contact)
	assert_true(grazed >= 0, "fixture: the real cut grazes the opponent's handle")
	assert_eq(struck, grazed, "and carries on into the body in the same tick — a hit, as predicted")


## What one `_answered_tap` did: the tap's first contact, then who struck the
## first body hit and when (ticks after the press).
class AnsweredTap:
	var result := ""
	var landed := ""
	var landed_tick := -1
