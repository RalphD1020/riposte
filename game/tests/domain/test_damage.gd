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
	assert_near(strike.impact.normal_speed, 8.0 * 0.9, 1e-9, "closing speed is blade-point speed")
	assert_near(strike.impact.edge_alignment, 1.0, 1e-9, "edge leads the cut")
	assert_between(strike.damage, 14.0, 55.0, "a clean mid-blade cut is light-to-heavy, not lethal")


func test_moving_into_the_blade_hurts_more_than_retreating() -> void:
	var still := _strike(_scene(12.0)).quality
	var advancing := _strike(_scene(12.0, -3.0)).quality
	var retreating := _strike(_scene(12.0, 3.0)).quality
	assert_true(advancing > still, "the target participates: stepping in raises impact")
	assert_true(retreating < still, "retreating with the blade lowers impact")


func test_impulse_and_severity_are_different_quantities() -> void:
	## COMBAT §36A. Momentum and energy of the same event: impulse is linear
	## in closing speed, severity quadratic, so doubling the speed doubles the
	## shove and quadruples the cut.
	var slow := _strike(_scene(6.0)).impact
	var fast := _strike(_scene(12.0)).impact
	assert_near(fast.impulse, slow.impulse * 2.0, 1e-9, "impulse scales with closing speed")
	assert_near(fast.kinetic_severity, slow.kinetic_severity * 4.0, 1e-9, "severity scales with its square")
	assert_near(slow.impulse, slow.attacker_effective_mass * slow.normal_speed, 1e-12, "J = m_eff · v_n")
	assert_near(slow.kinetic_severity, 0.5 * slow.attacker_effective_mass * slow.normal_speed * slow.normal_speed, 1e-12, "E = ½ m_eff · v_n²")


func test_a_slow_heavy_strike_shoves_more_per_joule_than_a_fast_light_one() -> void:
	## The sharpest consequence of keeping impulse and severity apart: for the
	## same cutting energy, `J = 2E / v`, so the slower strike delivers more
	## momentum. A heavy weapon swung moderately shoves; a light one swung
	## viciously cuts. One scalar could not express that (PHYS-004).
	var heavy := _strike(_scene(8.0)).impact
	## Faster blade, far worse structure: withdrawing at full speed while
	## wrenching the body's own motion around.
	var light_state := _scene(17.0)
	var flailing := light_state.fighter(0)
	flailing.vy = -_rules.fighter.max_speed
	flailing.ax = _rules.fighter.brake_accel()
	var light := _strike(light_state).impact
	assert_near(heavy.impulse * heavy.normal_speed, 2.0 * heavy.kinetic_severity, 1e-9, "J = 2E / v is an identity, not a tuning choice")
	assert_true(light.normal_speed > heavy.normal_speed, "precondition: the flailing strike is faster")
	assert_between(light.kinetic_severity / heavy.kinetic_severity, 0.8, 1.2, "precondition: and carries comparable energy")
	assert_true(heavy.impulse > light.impulse, "so the slower, better-coupled strike carries more momentum")
	assert_true(heavy.target_delta_v() > light.target_delta_v(), "and displaces the target further")


func test_heavier_targets_are_displaced_less_by_equal_impulse() -> void:
	## Physical sanity: Δv = J / m. A braced target takes the same impulse and
	## moves less, and exposure has nothing to do with it (PHYS-004).
	var braced := _scene(12.0)
	var scrambling := _scene(12.0)
	var loose := scrambling.fighter(1)
	loose.ax = _rules.fighter.brake_accel()
	loose.turn_rate = _rules.fighter.turn_speed_max
	var braced_impact := _strike(braced).impact
	var loose_impact := _strike(scrambling).impact
	assert_near(braced_impact.impulse, loose_impact.impulse, 1e-9, "precondition: the same impulse arrives")
	assert_true(loose_impact.target_effective_mass < braced_impact.target_effective_mass, "a scrambling target braces less")
	assert_true(loose_impact.target_delta_v() > braced_impact.target_delta_v(), "so the same impulse throws them further")
	assert_true(braced_impact.target_effective_mass <= _rules.fighter.mass, "nobody resists with more than their own mass")


func test_exposure_never_touches_the_physics() -> void:
	## PHYS-004, stated directly: changing only how badly the target is
	## positioned must change the consequence and nothing physical.
	var composed := _scene(12.0)
	var helpless := _scene(12.0)
	var victim := helpless.fighter(1)
	DuelFixture.commit(victim, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	victim.stability = _rules.fighter.stability_floor
	var calm := _strike(composed)
	var exposed := _strike(helpless)
	assert_true(exposed.exposure > calm.exposure, "precondition: one target really is more exposed")
	assert_near(exposed.impact.normal_speed, calm.impact.normal_speed, 1e-12, "exposure adds no closing speed")
	assert_near(exposed.impact.impulse, calm.impact.impulse, 1e-12, "exposure adds no impulse")
	assert_near(exposed.impact.kinetic_severity, calm.impact.kinetic_severity, 1e-12, "exposure adds no energy")
	assert_near(exposed.physical_quality, calm.physical_quality, 1e-12, "and no physical severity")
	assert_true(exposed.damage > calm.damage, "it only changes what the strike costs the target")
	assert_true(exposed.stagger_pressure > calm.stagger_pressure, "and how easily they are unbalanced")


func test_effective_mass_is_coupling_not_body_mass() -> void:
	## PHYS-002. A 78 kg fighter never puts 78 kg behind a sword, and the
	## share that does arrive is decided by structure, not by the mass field.
	var state := _scene(12.0)
	var strike := _strike(state)
	assert_true(strike.impact.attacker_effective_mass < _rules.fighter.mass, "effective mass is a fraction of the body")
	assert_true(strike.impact.attacker_effective_mass > _rules.weapon.mass, "but more than the bare weapon")
	assert_near(
		strike.impact.attacker_effective_mass,
		_rules.weapon.mass + strike.impact.coupling * _rules.combat.body_contribution_mass,
		1e-12,
		"effective mass is weapon mass plus the coupled share"
	)
	assert_between(strike.impact.coupling, _rules.combat.coupling_floor, 1.0, "coupling stays in range")


func test_planted_couples_better_than_an_abrupt_correction() -> void:
	## PHYS-002. Same blade velocity, different body structure.
	var definition := _rules.fighter
	var combat := _rules.combat
	var planted := FighterState.new()
	planted.weapon.reset(-_rules.weapon.guard_angle)
	var scrambling := FighterState.new()
	scrambling.weapon.reset(-_rules.weapon.guard_angle)
	scrambling.vy = definition.max_speed
	scrambling.ax = definition.brake_accel()
	scrambling.turn_rate = definition.turn_speed_max
	assert_eq(planted.speed(), 0.0, "precondition: one fighter is still")
	assert_true(scrambling.acceleration() > 0.0, "precondition: the other is wrenching its own motion")
	var planted_plant := StructuralCoupling.plant_quality(planted, definition, combat)
	var scrambling_plant := StructuralCoupling.plant_quality(scrambling, definition, combat)
	assert_eq(planted_plant, 1.0, "standing quiet is fully planted")
	assert_true(scrambling_plant < planted_plant, "speed, acceleration debt and rotation all erode plant quality")
	var strike_x := 1.0
	var strike_y := 0.0
	assert_true(
		StructuralCoupling.coupling(planted, strike_x, strike_y, definition, combat)
		> StructuralCoupling.coupling(scrambling, strike_x, strike_y, definition, combat),
		"so the planted fighter couples better"
	)


func test_movement_coherence_rewards_driving_through_the_strike() -> void:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	assert_eq(StructuralCoupling.movement_coherence(fighter, 1.0, 0.0), 0.5, "a still body is neutral, not penalised")
	fighter.vx = 3.0
	var driving := StructuralCoupling.movement_coherence(fighter, 1.0, 0.0)
	var across := StructuralCoupling.movement_coherence(fighter, 0.0, 1.0)
	var away := StructuralCoupling.movement_coherence(fighter, -1.0, 0.0)
	assert_near(driving, 1.0, 1e-12, "driving straight through the strike is fully coherent")
	assert_near(across, 0.5, 1e-12, "moving across it is neutral")
	assert_near(away, 0.0, 1e-12, "moving away from it is incoherent")
	assert_true(driving > across and across > away, "coherence is ordered, not a switch")


func test_no_movement_state_carries_a_damage_modifier() -> void:
	## PHYS-001/002. Advancing must only ever help through closing speed and
	## coupling — never through a bonus applied because a flag was set.
	var definition := _rules.fighter
	var combat := _rules.combat
	var forward := FighterState.new()
	forward.weapon.reset(-_rules.weapon.guard_angle)
	forward.vx = 2.0
	var backward := FighterState.new()
	backward.weapon.reset(-_rules.weapon.guard_angle)
	backward.vx = -2.0
	## The cut here sweeps along +Y, so forward and backward motion are both
	## perpendicular to it and must couple identically.
	assert_near(
		StructuralCoupling.coupling(forward, 0.0, 1.0, definition, combat),
		StructuralCoupling.coupling(backward, 0.0, 1.0, definition, combat),
		1e-12,
		"advancing and retreating are physically symmetric for a crosswise cut"
	)


func test_retreating_against_a_charging_opponent_still_lands_hard() -> void:
	## COMBAT §36B: a retreating fighter gets no blanket penalty. The
	## opponent's own momentum restores the closing velocity.
	## The cut sweeps along +Y here, so the attacker withdraws along -Y.
	var planted := _strike(_scene(12.0))
	var retreating := _scene(12.0)
	retreating.fighter(0).vy = -2.0
	var retreating_alone := _strike(retreating)
	var charged_into := _scene(12.0, -3.0)
	charged_into.fighter(0).vy = -2.0
	var counter := _strike(charged_into)
	assert_true(retreating_alone.physical_quality < planted.physical_quality, "withdrawing alone gives up contribution")
	assert_true(retreating_alone.impact.coupling < planted.impact.coupling, "because the body is no longer behind the blade")
	assert_true(counter.impact.normal_speed > planted.impact.normal_speed, "but the charging opponent more than restores the closing speed")
	assert_true(counter.physical_quality > retreating_alone.physical_quality, "so the strike recovers physically")

	## And the pull counter completes through exposure, not a counter bonus:
	## the fighter who charged in is the one who cannot respond to it.
	var committed_charger := _scene(12.0, -3.0)
	committed_charger.fighter(0).vy = -2.0
	var exposed := committed_charger.fighter(1)
	DuelFixture.commit(exposed, CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	exposed.facing += PI / 2.0
	exposed.stability = 0.5
	var pull_counter := _strike(committed_charger)
	assert_true(pull_counter.exposure > planted.exposure, "precondition: the charger is badly exposed")
	assert_near(pull_counter.physical_quality, counter.physical_quality, 1e-12, "exposure adds no physical energy")
	assert_true(pull_counter.damage > planted.damage, "a retreating counter can out-damage a planted cut on a composed target")


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
	assert_near(aligned.impact.normal_speed, glancing.impact.normal_speed, 1e-9, "precondition: same closing speed")
	assert_true(glancing.impact.edge_alignment < aligned.impact.edge_alignment, "sliding along the blade is misaligned")
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
	DuelFixture.kill(a)
	assert_eq(InitiativeModel.time_to_threat(a, b, _rules), InitiativeModel.UNREACHABLE, "the dead are unreachable")
