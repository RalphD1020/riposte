extends TestCase

## LINE-GAME: the line game as play (LINE-CHANGE-001, KNIFE-EDGE-LINE-001) —
## ordinary commands for the reading fighter, a Hard CPU for the other once its
## cut is out, real physics throughout. ATTACK owns the mechanism witnesses
## (what one cut meets from each side); this suite owns what that does to the
## exchange.
##
## Rules 50 (blade-only steel): at striking measure two swords crossing in
## front of the fighters cross near their grips, so the rules-49 "behind the
## blade the tap meets steel, and the defender lands first" came from crossguard
## and handle steel. Those claims are not asserted here: they are the open
## design objective LINE-CHANGE-CAPITALIZATION-001, tracked in the spec, never
## a passing law of this topology. What is asserted is what the line does now.
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
## straight in and presses the moment its own sword is free. The line changes
## what the tap meets: on rules 52, where the blade's steel starts at the drawn
## blade just above the guard, STANDING and BEHIND THE BLADE its first contact
## is the defender's blade near the hands (on rules 50–51, when that stretch
## passed from the grip side, behind the blade met the grip and standing the
## torso); INTO THE BLADE it is the torso. MIRROR: the same, on the same tick.
## A scenario trace, not a rule about every step. (Who lands first is
## LINE-CHANGE-CAPITALIZATION-001, open.)
func test_the_line_changes_what_a_tap_meets() -> void:
	var rules := StandardDuelRules.create()
	## ARRANGE + ACT
	var behind := _answered_tap(rules, "origin", false)
	var still := _answered_tap(rules, "none", false)
	var into := _answered_tap(rules, "end", false)
	var mirrored := _answered_tap(rules, "origin", true)
	## ASSERT
	assert_eq(behind.result, "steel", "behind the blade, the tap's first contact is the defender's blade, not the torso")
	assert_eq(still.result, "steel", "standing, the same blade")
	assert_eq(into.result, "torso", "into the blade, the torso")
	assert_eq(mirrored.result, behind.result, "mirrored: the same contact")
	assert_eq(mirrored.landed, behind.landed, "the same next hit")
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
					out.result = event.text(DuelEventKeys.REGION)
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
## blade takes the torso out of the tap's first contact more often than
## stepping into it — an ordering, never the rates themselves. (Whether the
## step then wins the exchange is LINE-CHANGE-CAPITALIZATION-001, open.)
func test_behind_the_blade_shields_the_torso_more_than_into_it() -> void:
	var rules := StandardDuelRules.create()
	var torso := {"origin": 0, "end": 0}
	var runs := 0
	for distance: float in [1.35, 1.5, 1.65, 1.8]:
		for lead: int in [-6, -4, -2]:
			runs += 1
			for side: String in ["origin", "end"]:
				## ARRANGE + PERTURB + ACT
				var answered := _answered_tap(rules, side, false, distance, lead, 6)
				if answered.result == DuelEventKeys.REGION_TORSO:
					torso[side] += 1
	## ASSERT
	assert_eq(runs, 12, "fixture: the whole grid was played")
	assert_true(torso["origin"] < torso["end"], "behind the blade the tap's first contact is the torso less often than into it (%d vs %d of %d)" % [torso["origin"], torso["end"], runs])


## FIRST-CONTACT-002 (THREAT-AGREEMENT-AUDIT's canonical regression), on a
## constructed state: slot 0 at rest and able to strike; slot 1 standing 1.8 m
## ahead facing it, its sword at rest turned off the line (−0.9 rad). Slot 0
## walks straight in pressing its tap as soon as it can, slot 1 standing. The
## steel-aware prediction says the strike reaches flesh, and in the duel it
## does: the first thing the cut meets is the torso or the grip, never the
## blade first. (The rules-50 to rules-52 witnesses were live audit states,
## seed 204 tick 120 then tick 90, each moved by a later change to the steel;
## the constructed state sits inside a band, −0.6 to −1.2 rad, where the reading
## and the duel agree, so a small change does not move it.)
func test_a_strike_the_prediction_saw_reaching_flesh_reaches_flesh() -> void:
	## ARRANGE: the constructed state.
	var rules := StandardDuelRules.create()
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var weapon := rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, -weapon.guard_angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), 1.8, 0.0, PI, -0.9, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var me := runner.state.fighter(0)
	var them := runner.state.fighter(1)
	var line := Vector2(1.0, 0.0)
	assert_true(WeaponSystem.can_start_attack(me, rules.spec_of(me).weapon), "fixture: slot 0 can strike")
	## ACT: the prediction, then the duel under the same continuation.
	var predicted := InitiativeModel.estimate(me, rules.spec_of(me), them, rules.spec_of(them), rules.combat, ThreatEstimate.new(), ThreatContinuation.route(line.x, line.y))
	var steel := -1
	var struck := -1
	var launched := false
	for _t in 40:
		var tick := runner.state.tick
		var a := runner.state.fighter(0)
		var b := runner.state.fighter(1)
		var step := CutGeometry.step_intent(a, b, line)
		var press := not launched and WeaponSystem.can_start_attack(a, rules.spec_of(a).weapon)
		var seen := runner.events.size()
		runner.push(PlayerCommand.create(tick, step.x, step.y, press, press), PlayerCommand.idle(tick))
		launched = launched or press
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if event.type == DuelEventTypes.BLADE_CONTACT and steel < 0 and struck < 0:
				steel = event.tick
			if event.type == DuelEventTypes.BODY_HIT and event.actor == 0 and struck < 0:
				struck = event.tick
		if struck >= 0:
			break
	## ASSERT
	assert_false(predicted.starts_bound, "fixture: the swords start clear")
	assert_true(predicted.first_contact == ThreatEstimate.BODY or predicted.first_contact == ThreatEstimate.GRIP, "the prediction says the strike reaches flesh (%d)" % predicted.first_contact)
	assert_true(struck >= 0, "the real cut reaches flesh, as predicted")
	assert_eq(steel, -1, "and meets no blade before it")
	assert_true(runner.is_sound(), "every tick legal")


## What one `_answered_tap` did: the tap's first contact, then who struck the
## first body hit and when (ticks after the press).
class AnsweredTap:
	var result := ""
	var landed := ""
	var landed_tick := -1
