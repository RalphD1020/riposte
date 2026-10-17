extends TestCase

## STAMINA: stamina as a physical resource (STAMINA-004). The motors' own work
## drains it and easing off recovers it; a dash's start costs a fixed amount
## once, and an unaffordable dash is refused, never buffered; a spent charge
## stops earning but still releases on the player's command; a tick runs on
## its starting stamina and only the settled value decides the next; fatigue
## scales force alone and never rescales momentum or multiplies damage; every
## round starts rested.
##
## Implements: /spec/invariants.md#stamina-004
## See also: /docs/concepts/combat.md

## Back-to-back full charges (press, hold, release, then a breath) that are
## honest exertion, and the rest after them.
const SWING_CYCLES := 6
const SWING_HOLD_TICKS := 30
const SWING_BREATH_TICKS := 40
const REST_TICKS := 900
## Ticks of mirrored shuttle footwork.
const MIRROR_TICKS := 180
## A held charge's ticks before and after the bar is emptied.
const CHARGE_TICKS := 20
const SPENT_HOLD_TICKS := 40
## Ticks watched after a refused dash for one that fires later on its own.
const BUFFER_WATCH_TICKS := 20

var _rules: DuelRules


func _init() -> void:
	suite_name = "STAMINA"
	_rules = DuelFixture.rules()


func _runner(stamina: float = 1.0) -> SimRunner:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	runner.state.fighter(0).stamina = stamina
	return runner


func _fatigue(s: float) -> float:
	return _rules.combat.stamina_force_floor + (1.0 - _rules.combat.stamina_force_floor) * s


func test_every_round_starts_rested() -> void:
	## ARRANGE: a fresh duel, then a spent fighter.
	var state := DuelFixture.state(_rules)
	assert_eq(state.fighter(0).stamina, 1.0, "a new set starts rested")
	assert_eq(state.fighter(1).stamina, 1.0, "both fighters")
	## PERTURB
	state.fighter(0).stamina = 0.15
	state.fighter(1).stamina = 0.0
	## ACT: the between-round reset.
	DuelSetup.reset_round(state, _rules)
	## ASSERT
	assert_eq(state.fighter(0).stamina, 1.0, "fatigue never carries into the next round")
	assert_eq(state.fighter(1).stamina, 1.0, "from empty either")


func test_exertion_drains_and_easing_off_recovers() -> void:
	## ARRANGE: a rested fighter.
	var runner := _runner()
	var fighter := runner.state.fighter(0)
	## ACT: full charges, back to back — the motors' work and nothing else (no
	## dash, no contact).
	var lowest := fighter.stamina
	for _cycle in SWING_CYCLES:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true), PlayerCommand.idle(runner.state.tick))
		for _t in SWING_HOLD_TICKS:
			runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0), PlayerCommand.idle(runner.state.tick))
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(runner.state.tick))
		for _t in SWING_BREATH_TICKS:
			lowest = minf(lowest, fighter.stamina)
			runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	var spent := lowest
	## ACT: then nothing.
	runner.idle(REST_TICKS)
	## ASSERT
	assert_eq(runner.count(DuelEventTypes.ATTACK_RELEASED), SWING_CYCLES, "fixture: every charge was swung")
	assert_eq(runner.count(DuelEventTypes.BURST_STARTED), 0, "fixture: and nothing dashed")
	assert_true(spent < 1.0, "the swings' own work spends stamina (%.3f at the lowest)" % spent)
	assert_true(fighter.stamina > spent, "easing off recovers it (%.3f → %.3f)" % [spent, fighter.stamina])
	assert_eq(fighter.stamina, 1.0, "back to full after resting long enough")
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


## A tick's capability comes from the stamina it started with: the first tick
## of a walk from rest accelerates at exactly the starting fatigue term, and
## the drain it causes only shows on the next tick.
func test_a_tick_runs_on_its_starting_stamina() -> void:
	## ARRANGE: two fighters at rest, rested and tired.
	var rested := _runner(1.0)
	var tired := _runner(0.3)
	## ACT: one tick of forward footwork each.
	for runner: SimRunner in [rested, tired]:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
	## ASSERT
	var ratio := tired.state.fighter(0).speed() / rested.state.fighter(0).speed()
	assert_true(rested.state.fighter(0).speed() > 0.0, "fixture: the walk started")
	assert_near(ratio, _fatigue(0.3) / _fatigue(1.0), 1e-12, "the tick accelerated at its starting stamina's force")
	assert_true(tired.state.fighter(0).stamina != 0.3, "and only the settle at the tick's end moved the bar, for the next tick (%.5f)" % tired.state.fighter(0).stamina)


func test_a_dash_costs_once_when_it_starts() -> void:
	## ARRANGE: a rested fighter.
	var runner := _runner()
	var fighter := runner.state.fighter(0)
	var cost := _rules.combat.stamina_dash_cost
	## ACT: dash forward and keep asking for it through the whole burst.
	var drops := PackedFloat64Array()
	for _t in _rules.combatant(0).fighter.burst_ticks + 2:
		var before := fighter.stamina
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, true), PlayerCommand.idle(runner.state.tick))
		drops.append(before - fighter.stamina)
	## ASSERT
	assert_eq(runner.count(DuelEventTypes.BURST_STARTED), 1, "one dash started")
	assert_true(drops[0] >= cost, "its start tick paid the dash cost (%.4f ≥ %.2f)" % [drops[0], cost])
	for i in range(1, drops.size()):
		assert_true(drops[i] < cost, "tick %d of the burst paid no second cost (%.4f)" % [i, drops[i]])


## A dash's cost never weakens its own start tick: it accelerates at the
## starting stamina's force, not at what is left after paying.
func test_a_dash_start_tick_runs_on_its_starting_stamina() -> void:
	## ARRANGE: two fighters at rest, rested and half spent (both can pay).
	var rested := _runner(1.0)
	var half := _runner(0.5)
	assert_true(0.5 >= _rules.combat.stamina_dash_cost, "fixture: half a bar affords a dash")
	## ACT: one dash-start tick each.
	for runner: SimRunner in [rested, half]:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, true), PlayerCommand.idle(runner.state.tick))
	## ASSERT
	assert_eq(half.count(DuelEventTypes.BURST_STARTED), 1, "fixture: the dash started")
	var ratio := half.state.fighter(0).speed() / rested.state.fighter(0).speed()
	assert_near(ratio, _fatigue(0.5) / _fatigue(1.0), 1e-12, "the start tick drove at the starting stamina (0.5), not after its cost (%.2f)" % (0.5 - _rules.combat.stamina_dash_cost))


func test_an_unaffordable_dash_is_refused_and_never_buffered() -> void:
	## ARRANGE: a fighter just under one dash's cost.
	var cost := _rules.combat.stamina_dash_cost
	var runner := _runner(cost * 0.9)
	var fighter := runner.state.fighter(0)
	var start := fighter.stamina
	## ACT: a double tap forward, then the dash modifier.
	for burst: float in [1.0, 0.0, 1.0]:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, burst), PlayerCommand.idle(runner.state.tick))
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, true), PlayerCommand.idle(runner.state.tick))
	## ASSERT: refused, and nothing paid for it.
	assert_eq(runner.count(DuelEventTypes.BURST_STARTED), 0, "neither dash starts")
	assert_true(start - fighter.stamina < cost, "and no dash cost was taken (%.4f spent)" % (start - fighter.stamina))
	## PERTURB: the bar refilled; the fighter now asks for nothing.
	fighter.stamina = 1.0
	## ACT
	runner.idle(BUFFER_WATCH_TICKS)
	## ASSERT
	assert_eq(runner.count(DuelEventTypes.BURST_STARTED), 0, "the refused dash never fires later on its own")
	assert_true(runner.is_sound(), "every tick legal")


func test_a_spent_charge_stops_earning_but_releases_on_command() -> void:
	## ARRANGE: a rested hold that is charging.
	var runner := _runner()
	var fighter := runner.state.fighter(0)
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true), PlayerCommand.idle(runner.state.tick))
	for _t in CHARGE_TICKS:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0), PlayerCommand.idle(runner.state.tick))
	assert_eq(fighter.weapon.phase, CombatPhase.Id.CHARGING, "fixture: the hold is charging")
	var earned := fighter.weapon.charge
	assert_true(earned > 0.0, "fixture: and has earned some charge (%.3f)" % earned)
	var rested := StateFork.of(runner)
	## PERTURB: the bar emptied, and kept empty.
	## ACT: hold on.
	for _t in SPENT_HOLD_TICKS:
		fighter.stamina = 0.0
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0), PlayerCommand.idle(runner.state.tick))
		rested.push(PlayerCommand.create(rested.state.tick, 0.0, 0.0), PlayerCommand.idle(rested.state.tick))
	## ASSERT: no more charge, no release for the player.
	assert_true(rested.state.fighter(0).weapon.charge > earned, "fixture: a rested hold would have kept earning (%.3f)" % rested.state.fighter(0).weapon.charge)
	assert_eq(fighter.weapon.charge, earned, "a spent hold earns nothing more")
	assert_eq(fighter.weapon.phase, CombatPhase.Id.CHARGING, "and is never released for the player")
	assert_eq(runner.count(DuelEventTypes.ATTACK_RELEASED), 0, "no attack left the hand on its own")
	## ACT: the player releases.
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(runner.state.tick))
	## ASSERT
	var released := runner.first(DuelEventTypes.ATTACK_RELEASED)
	assert_true(released != null, "the release fires")
	if released != null:
		assert_eq(float(released.data[DuelEventKeys.CHARGE]), earned, "with the charge already earned")


## The settle writes stamina and nothing else: the same dash-start tick under
## a rule set whose motors and dash cost (all but) nothing leaves every other
## field bit-identical, so momentum is never rescaled by a drain.
func test_the_settle_touches_nothing_but_stamina() -> void:
	## ARRANGE: the standard costs, and a variant that costs (all but) nothing.
	var free_rules := DuelFixture.rules()
	free_rules.combat.stamina_move_cost = 0.0
	free_rules.combat.stamina_turn_cost = 0.0
	free_rules.combat.stamina_swing_cost = 0.0
	free_rules.combat.stamina_dash_cost = 1.0e-6
	var costed := SimRunner.create(_rules, 3)
	var costless := SimRunner.create(free_rules, 3)
	for runner: SimRunner in [costed, costless]:
		runner.skip_intro()
	## ACT: the same tick: a dash start, a press, the opponent walking.
	for runner: SimRunner in [costed, costless]:
		runner.push(PlayerCommand.create(runner.state.tick, 0.4, 1.0, true, false, false, true), PlayerCommand.create(runner.state.tick, -0.3, 1.0))
	## ASSERT
	var a := costed.state.fighter(0)
	var b := costless.state.fighter(0)
	assert_eq(costed.count(DuelEventTypes.BURST_STARTED), 1, "fixture: both dashed")
	assert_true(b.stamina - a.stamina > 0.1, "fixture: only the costed fighter paid (%.5f against %.5f)" % [a.stamina, b.stamina])
	for field: String in ["x", "y", "vx", "vy", "ax", "ay", "facing", "turn_rate", "health", "stability"]:
		assert_eq(a.get(field), b.get(field), "%s is bit-identical on the drain tick" % field)
	assert_eq(a.weapon.angle, b.weapon.angle, "the blade's angle")
	assert_eq(a.weapon.speed, b.weapon.speed, "and its speed")


## Fatigue never multiplies damage: a cut at its ceiling speed — where the
## motor adds nothing a tired arm could withhold — wounds the same rested or
## spent. A tired cut does less only because its actuator drove it less hard.
func test_fatigue_never_multiplies_damage() -> void:
	## ARRANGE: the same cut, struck rested and spent.
	var rested := _cut_at_ceiling(1.0)
	var spent := _cut_at_ceiling(0.0)
	## ASSERT
	assert_true(rested.x > 0.0, "fixture: the cut wounds (%.2f)" % rested.x)
	assert_eq(spent.y, rested.y, "fixture: the blade met the body at the same speed")
	assert_eq(spent.x, rested.x, "and the wound is the same")


## [damage dealt, blade speed at contact] for a cut already at its ceiling
## when it meets a standing body, with the attacker's stamina at `s`.
func _cut_at_ceiling(s: float) -> Vector2:
	var rules := DuelFixture.revolute_rules()
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	var spec := rules.combatant(0)
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, PI / 2.0)
	DuelFixture.place(b, 0.0, spec.weapon.tip_radius * 0.8 + spec.fighter.push_radius, -PI / 2.0)
	a.stamina = s
	var w := a.weapon
	w.phase = CombatPhase.Id.ACTIVE_THREAT
	w.swing_dir = 1.0
	w.swing_charge = 0.0
	w.launch_preparation = 1.0
	w.angle = -0.9
	w.swing_start = w.angle
	w.swing_end = spec.weapon.guard_limit
	w.speed = spec.weapon.achievable_swing_speed(0.0, 1.0)
	var health := b.health
	var speed := 0.0
	for _t in 20:
		var before := w.speed
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if b.health < health:
			speed = before
			break
	return Vector2(health - b.health, speed)


func test_an_impossible_stamina_fails_closed() -> void:
	## ARRANGE
	var state := DuelFixture.state(_rules)
	assert_eq(StateInvariants.check(state, _rules), StateInvariants.OK, "fixture: a fresh state is sound")
	## PERTURB + ACT + ASSERT
	for bad: float in [NAN, -0.01, 1.01]:
		state.fighter(0).stamina = bad
		assert_eq(StateInvariants.check(state, _rules), StateInvariants.STAMINA_RANGE, "stamina %s is outside its legal set" % str(bad))
	state.fighter(0).stamina = 1.0


## Two identical fighters in mirrored play spend and recover identically.
func test_stamina_mirrors_exactly() -> void:
	## ARRANGE: the canonical mirrored spar.
	var runner := _runner()
	## ACT: both fighters shuttle in mirror.
	for tick in MIRROR_TICKS:
		var dash := tick % 60 == 0
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, dash), PlayerCommand.create(runner.state.tick, 0.0, 1.0, false, false, false, dash))
	## ASSERT
	assert_true(runner.state.fighter(0).stamina < 1.0, "fixture: both spent stamina (%.3f)" % runner.state.fighter(0).stamina)
	assert_eq(runner.state.fighter(0).stamina, runner.state.fighter(1).stamina, "to the last bit")
