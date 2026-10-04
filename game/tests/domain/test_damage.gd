extends TestCase

## DAMAGE: strike quality is relational and nonlinear (COMBAT §34–§39, §46–§54).
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "DAMAGE"
	_rules = DuelFixture.rules()


## Attacker at the origin, blade along +X turning counter-clockwise at
## `omega`; target body just above the blade, facing the attacker.
func _scene(omega: float, target_vy: float = 0.0) -> MatchState:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, omega, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.weapon)
	var target := state.fighter(1)
	ContactFixture.arm(target, 0.9, 0.27, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.weapon)
	target.facing = SimMath.arctan2(-target.y, -target.x)
	target.vy = target_vy
	return state


func _strike(state: MatchState, x: float = 0.9) -> StrikeResult:
	return DamageModel.evaluate(state.fighter(0), state.fighter(1), x, 0.0, _rules)


func test_reference_cut_is_solid() -> void:
	var strike := _strike(_scene(8.0))
	assert_near(strike.closing_speed, 8.0 * 0.9, 1e-9, "closing speed is blade-point speed")
	assert_near(strike.alignment, 1.0, 1e-9, "edge leads the cut")
	assert_between(strike.damage, 14.0, 55.0, "a clean mid-blade cut is light-to-heavy, not lethal")


func test_moving_into_the_blade_hurts_more_than_retreating() -> void:
	var still := _strike(_scene(12.0)).quality
	var advancing := _strike(_scene(12.0, -3.0)).quality
	var retreating := _strike(_scene(12.0, 3.0)).quality
	assert_true(advancing > still, "the target participates: stepping in raises impact")
	assert_true(retreating < still, "retreating with the blade lowers impact")


func test_outer_middle_beats_the_hilt() -> void:
	var state := _scene(12.0)
	assert_true(_strike(state, 0.9).quality > _strike(state, 0.35).quality, "sweet spot beats the hilt region")


func test_flat_contact_glances() -> void:
	var cut := _scene(0.0)
	cut.fighter(0).vy = 6.0
	var aligned := _strike(cut)
	var slide := _scene(0.0)
	slide.fighter(0).vx = 6.0
	slide.fighter(0).vy = 6.0
	var glancing := _strike(slide)
	assert_near(aligned.closing_speed, glancing.closing_speed, 1e-9, "precondition: same closing speed")
	assert_true(glancing.alignment < aligned.alignment, "sliding along the blade is misaligned")
	assert_true(glancing.quality < aligned.quality, "misalignment weakens the strike")


func test_exposure_reflects_commitment_balance_and_angle() -> void:
	var state := _scene(12.0)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	var calm := DamageModel.exposure(target, attacker, _rules)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	var committed := DamageModel.exposure(target, attacker, _rules)
	target.facing += PI / 2.0
	target.stability = 0.5
	var flanked := DamageModel.exposure(target, attacker, _rules)
	assert_true(calm < committed, "commitment exposes")
	assert_true(committed < flanked, "being out-angled and off balance exposes further")
	assert_true(flanked <= _rules.combat.exposure_max, "bounded")


func test_graze_stays_small_and_convergence_is_lethal() -> void:
	var graze := _scene(2.0)
	var small := DamageModel.evaluate(graze.fighter(0), graze.fighter(1), 1.2, 0.0, _rules)
	assert_true(small.damage < 5.0, "a slow tip graze is a scrape (%s)" % str(small.damage))
	var perfect := _scene(18.0, -3.0)
	var target := perfect.fighter(1)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	target.facing += PI / 2.0
	target.stability = 0.5
	var lethal := DamageModel.evaluate(perfect.fighter(0), target, 0.95, 0.0, _rules)
	assert_true(lethal.damage >= 85.0, "convergence of speed, sweet spot, alignment, and exposure is lethal (%s)" % str(lethal.damage))
	assert_true(lethal.critical, "and is classified critical")


func test_critical_requires_every_condition() -> void:
	var state := _scene(18.0, -3.0)
	var target := state.fighter(1)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	target.facing += PI / 2.0
	assert_true(DamageModel.evaluate(state.fighter(0), target, 0.95, 0.0, _rules).critical, "precondition: converged strike is critical")
	assert_false(DamageModel.evaluate(state.fighter(0), target, 0.3, 0.0, _rules).critical, "hilt contact is never critical")
	target.weapon.reset(-_rules.weapon.guard_angle)
	target.facing -= PI / 2.0
	assert_false(DamageModel.evaluate(state.fighter(0), target, 0.95, 0.0, _rules).critical, "an unexposed target is never critical")


func test_degenerate_contact_stays_finite() -> void:
	var state := _scene(12.0)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.0, 0.0, _rules)
	assert_finite(strike.quality, "quality finite at the pivot")
	assert_finite(strike.damage, "damage finite at the pivot")


func test_recovering_fighter_threatens_later() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 1.4, 0.0, PI)
	b.weapon.angle = 0.0
	WeaponSystem.enter_recovery(a.weapon, 30)
	assert_true(InitiativeModel.initiative(b, a, _rules) > 0.0, "the neutral fighter holds initiative")
	assert_true(InitiativeModel.time_to_threat(a, b, _rules) >= 0.5, "thirty recovery ticks delay the threat")


func test_distance_delays_threat_and_the_dead_never_threaten() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 1.4, 0.0, PI)
	var near := InitiativeModel.time_to_threat(a, b, _rules)
	b.x = 5.0
	assert_true(InitiativeModel.time_to_threat(a, b, _rules) > near, "farther opponents take longer to threaten")
	WeaponSystem.kill(a)
	assert_eq(InitiativeModel.time_to_threat(a, b, _rules), InitiativeModel.UNREACHABLE, "the dead are unreachable")
