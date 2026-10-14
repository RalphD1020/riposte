extends TestCase

## DAMAGE: strike quality is relational and nonlinear (COMBAT §34–§39, §46–§54).
##
## Implements: /spec/invariants.md#combat-003
## Implements: /spec/invariants.md#line-change-001
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "DAMAGE"
	## Hand-built revolute scenes: the mechanism under test, on the fixed pivot.
	_rules = DuelFixture.revolute_rules()


## Attacker at the origin, blade along +X turning counter-clockwise at
## `omega`; target body just above the blade, facing the attacker.
func _scene(omega: float, target_vy: float = 0.0) -> MatchState:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, omega, CombatPhase.Id.ACTIVE_THREAT, 0.5, _rules.combatant(0).weapon)
	var target := state.fighter(1)
	ContactFixture.arm(target, 0.9, 0.27, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	target.facing = SimMath.arctan2(-target.y, -target.x)
	target.vy = target_vy
	return state


## For exposure readings: the target rests on its canonical guard instead of
## holding its blade straight down the line, where in this hand-built scene it
## would already lie across the attacker's torso — an immediate threat in any
## phase, which no live duel reaches (THREAT-001 reads the actual blade).
func _on_guard(state: MatchState) -> MatchState:
	state.fighter(1).weapon.angle = -_rules.combatant(0).weapon.guard_angle
	return state


func _strike(state: MatchState, x: float = 0.9) -> StrikeResult:
	return DamageModel.evaluate(state.fighter(0), state.fighter(1), x, 0.0, _rules)


func test_reference_cut_is_solid() -> void:
	var strike := _strike(_scene(8.0))
	assert_near(strike.impact.normal_speed, 8.0 * 0.9, 1e-9, "closing speed is blade-point speed")
	assert_near(strike.impact.edge_alignment, 1.0, 1e-9, "edge leads the cut")
	assert_between(strike.damage, 14.0, 55.0, "a clean mid-blade cut is light-to-heavy, not lethal")


## CLEAN-STRIKE-LETHALITY: the same clean cut, faster, dissipates more energy
## and never does less injury. The law is pinned here; how lethal a clean fast
## cut is belongs to the calibration and is read from the feel corpus.
func test_more_clean_energy_never_does_less_injury() -> void:
	var previous: StrikeResult = null
	var broke := ""
	for step in range(1, 41):
		## ARRANGE + PERTURB: the same square, edge-first cut, 0.5 rad/s faster.
		var omega := float(step) * 0.5
		## ACT
		var strike := _strike(_scene(omega))
		if previous != null and broke == "":
			if not (strike.impact.kinetic_severity > previous.impact.kinetic_severity):
				broke = "energy did not rise at %.1f rad/s" % omega
			elif strike.damage < previous.damage:
				broke = "damage fell at %.1f rad/s (%.3f < %.3f)" % [omega, strike.damage, previous.damage]
		previous = strike
	## ASSERT
	var slow := _strike(_scene(0.5))
	assert_true(slow.contact_kind == StrikeResult.ContactKind.SLASH, "fixture: a clean, edge-first cut")
	assert_eq(broke, "", "more dissipated energy, never less injury")
	assert_true(previous.damage > slow.damage, "and the fast cut wounds more than the slow one (%.1f > %.1f)" % [previous.damage, slow.damage])


func test_moving_into_the_blade_hurts_more_than_retreating() -> void:
	var still := _strike(_scene(12.0))
	var advancing := _strike(_scene(12.0, -3.0))
	var retreating := _strike(_scene(12.0, 3.0))
	assert_true(advancing.impact.kinetic_severity > still.impact.kinetic_severity, "the target participates: stepping in raises impact")
	assert_true(retreating.impact.kinetic_severity < still.impact.kinetic_severity, "retreating with the blade lowers impact")
	## Injury follows, up to the curve's compressive cap (which a 12 rad/s cut
	## may already reach): never the other way round.
	assert_true(advancing.quality >= still.quality and still.quality >= retreating.quality, "and the wound never reverses that order")
	assert_true(advancing.quality > retreating.quality, "a cut met stepping in out-wounds one met retreating")


func test_impulse_and_severity_are_different_quantities() -> void:
	## COMBAT §36A. Momentum and energy of the same event: impulse is linear
	## in closing speed, severity quadratic, so doubling the speed doubles the
	## shove and quadruples the cut.
	var slow := _strike(_scene(6.0)).impact
	var fast := _strike(_scene(12.0)).impact
	assert_near(fast.impulse, slow.impulse * 2.0, 1e-9, "impulse scales with closing speed")
	assert_near(fast.kinetic_severity, slow.kinetic_severity * 4.0, 1e-9, "severity scales with its square")
	## Both out of the contact's one effective mass (IMPACT-PHYSICS-001).
	var e := slow.restitution
	var k := slow.inverse_effective_mass
	assert_near(k, 1.0 / slow.attacker_mass + 1.0 / slow.target_mass + slow.lever_cross * slow.lever_cross / slow.weapon_inertia, 1e-12, "k = 1/m_A + 1/m_T + c²/M_θ")
	assert_near(slow.impulse, (1.0 + e) * slow.normal_speed / k, 1e-12, "J = (1 + e)·v_n / k")
	assert_near(slow.kinetic_severity, 0.5 * (1.0 - e * e) * slow.normal_speed * slow.normal_speed / k, 1e-12, "E = ½(1 − e²)·v_n² / k")


func test_a_slow_heavy_strike_shoves_more_per_joule_than_a_fast_light_one() -> void:
	## For the same dissipated energy, `J·v = 2E / (1 − e)`, so the slower
	## closing speed carries more momentum. The heavy contact is the short
	## lever; the light one is the long lever, sped up until the energies
	## match. Footing does not enter (PHYS-002, PHYS-004).
	var heavy_point := 0.45
	var light_point := 1.05
	var heavy := _strike(_scene(8.0), heavy_point).impact
	var probe := _strike(_scene(1.0), light_point).impact
	assert_true(heavy.inverse_effective_mass < probe.inverse_effective_mass, "precondition: the short lever is the heavier contact")
	var light_omega := heavy.normal_speed * sqrt(probe.inverse_effective_mass / heavy.inverse_effective_mass) / probe.normal_speed
	var light := _strike(_scene(light_omega), light_point).impact
	assert_near(heavy.impulse * heavy.normal_speed * (1.0 - heavy.restitution), 2.0 * heavy.kinetic_severity, 1e-9, "J·v = 2E / (1 − e) is an identity, not a tuning choice")
	assert_near(light.impulse * light.normal_speed * (1.0 - light.restitution), 2.0 * light.kinetic_severity, 1e-9, "and it holds for the light contact too")
	assert_true(light.normal_speed > heavy.normal_speed, "precondition: the long lever is the faster closing")
	assert_near(light.kinetic_severity, heavy.kinetic_severity, 1e-6 * heavy.kinetic_severity, "precondition: the two contacts dissipate the same energy")
	assert_true(heavy.impulse > light.impulse, "so the slower, heavier contact carries more momentum")
	assert_true(heavy.target_delta_v() > light.target_delta_v(), "and displaces the target further")


func test_footing_never_changes_how_much_a_body_weighs() -> void:
	## Mass answers "how hard is this body to accelerate"; footing is the
	## actuators' business (rules v33). A scrambling target is exactly as heavy
	## as a braced one, so the same blade gives both the same impulse and the
	## same Δv = J / m — and exposure has nothing to do with it (PHYS-004).
	var braced := _scene(12.0)
	var scrambling := _scene(12.0)
	var loose := scrambling.fighter(1)
	loose.ax = _rules.combatant(0).fighter.brake_accel()
	loose.turn_rate = _rules.combatant(0).fighter.turn_speed_max
	assert_true(StructuralCoupling.plant_quality(loose, _rules.combatant(0).fighter, _rules.combat) < StructuralCoupling.plant_quality(braced.fighter(1), _rules.combatant(0).fighter, _rules.combat), "precondition: one target really is scrambling")
	var braced_impact := _strike(braced).impact
	var loose_impact := _strike(scrambling).impact
	assert_near(braced_impact.normal_speed, loose_impact.normal_speed, 1e-9, "precondition: the same blade arrives at the same speed")
	assert_eq(loose_impact.target_mass, _rules.combatant(0).fighter.mass, "a scrambling target weighs its real mass")
	assert_eq(braced_impact.target_mass, _rules.combatant(0).fighter.mass, "and so does a braced one")
	assert_near(loose_impact.impulse, braced_impact.impulse, 1e-12, "so the same impulse arrives")
	assert_near(loose_impact.target_delta_v(), braced_impact.target_delta_v(), 1e-12, "and throws them exactly as far")
	assert_near(braced_impact.target_delta_v(), braced_impact.impulse / _rules.combatant(0).fighter.mass, 1e-12, "Δv = J / m")


func test_exposure_never_touches_the_physics() -> void:
	## PHYS-004, stated directly: changing only how badly the target is
	## positioned changes nothing physical — and since v36 no consequence
	## either (exposure is a reading of initiative).
	var composed := _on_guard(_scene(12.0))
	var helpless := _on_guard(_scene(12.0))
	var victim := helpless.fighter(1)
	DuelFixture.commit(victim, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	victim.stability = _rules.combatant(0).fighter.stability_floor
	var calm := _strike(composed)
	var exposed := _strike(helpless)
	assert_true(exposed.exposure > calm.exposure, "precondition: one target really is more exposed")
	assert_near(exposed.impact.normal_speed, calm.impact.normal_speed, 1e-12, "exposure adds no closing speed")
	assert_near(exposed.impact.impulse, calm.impact.impulse, 1e-12, "exposure adds no impulse")
	assert_near(exposed.impact.kinetic_severity, calm.impact.kinetic_severity, 1e-12, "exposure adds no energy")
	assert_near(exposed.physical_quality, calm.physical_quality, 1e-12, "and no physical severity")
	assert_near(exposed.damage, calm.damage, 1e-12, "nor what the strike costs the target")
	assert_near(exposed.stagger_pressure, calm.stagger_pressure, 1e-12, "nor how easily they are unbalanced")


func test_bodies_answer_with_their_real_mass_and_inertia_ignores_plant_and_commitment() -> void:
	## PHYS-002 (rules v33). Mass is what exists. Inertia is where that mass
	## sits. A planted or committed fighter is not a heavier sword.
	var state := _scene(12.0)
	var strike := _strike(state)
	var impact := strike.impact
	assert_eq(impact.attacker_mass, _rules.combatant(0).fighter.mass, "the attacker's body is its real mass")
	assert_eq(impact.target_mass, _rules.combatant(0).fighter.mass, "the target's body is its real mass")
	assert_between(impact.coupling, _rules.combat.coupling_floor, 1.0, "coupling stays a reading, in range")
	var attacker := state.fighter(0)
	var pose := WeaponKinematics.pose_of(attacker, _rules.combatant(0), BladePose.new())
	var held := WeaponKinematics.held_inertia(_rules.combatant(0), pose)
	assert_near(impact.weapon_inertia, held, 1e-12, "passive inertia is the held sword, unscaled")
	attacker.weapon.commitment = 1.0
	attacker.vx = _rules.combatant(0).fighter.max_speed
	attacker.ax = _rules.combatant(0).fighter.brake_accel()
	var scrambled := ImpactModel.resolve(attacker, state.fighter(1), impact.point_x, impact.point_y, _rules)
	assert_near(scrambled.weapon_inertia, held, 1e-12, "scrambling and full commitment leave the same inertia")
	assert_true(scrambled.coupling < impact.coupling, "precondition: the reading itself did change")
	assert_near(1.0 / float(strike.to_payload()[DuelEventKeys.EFFECTIVE_MASS]), impact.inverse_effective_mass, 1e-12, "the strike reports the contact's effective mass 1/k")


func test_planted_couples_better_than_an_abrupt_correction() -> void:
	## PHYS-002. Same blade velocity, different body structure.
	var definition := _rules.combatant(0).fighter
	var combat := _rules.combat
	var planted := FighterState.new()
	planted.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	var scrambling := FighterState.new()
	scrambling.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
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
	fighter.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
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
	var definition := _rules.combatant(0).fighter
	var combat := _rules.combat
	var forward := FighterState.new()
	forward.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	forward.vx = 2.0
	var backward := FighterState.new()
	backward.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
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

	## And the pull counter completes through physics, not a counter bonus:
	## the charger's own momentum restores the closing speed (v36 — the
	## charger's exposure is a reading of being late, never a damage factor).
	assert_true(counter.damage > retreating_alone.damage, "a retreating counter into a charge out-damages the same retreat alone")


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


## v36: exposure is a reading of initiative — how far behind the attacker the
## target is in time-to-threat — not an authored additive table. A target
## caught in overswing, or turned away, is later to threaten, so reads as more
## exposed; the reading is bounded and even initiative reads one half.
func test_exposure_reads_how_late_the_target_is() -> void:
	var state := _on_guard(_scene(12.0))
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	attacker.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	attacker.weapon.speed = 0.0
	var calm := ExposureModel.reading(target, attacker, _rules)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	var committed := ExposureModel.reading(target, attacker, _rules)
	target.facing += PI / 2.0
	var turned := ExposureModel.reading(target, attacker, _rules)
	assert_true(calm < committed, "caught in overswing, the target is later to threaten (%.3f < %.3f)" % [calm, committed])
	assert_true(committed <= turned, "turned away, later still (%.3f ≤ %.3f)" % [committed, turned])
	assert_between(turned, 0.0, 1.0, "bounded")
	var mirror := ExposureModel.margin(attacker, target, _rules)
	assert_near(ExposureModel.margin(target, attacker, _rules), -mirror, 1e-12, "one fighter's lateness is the other's lead")


## v36: damage, stagger and criticals read the physics alone. The same impact
## on a composed target and on one caught helpless does the same damage; the
## helpless one is punished by being hit first, not by softer flesh.
func test_exposure_never_scales_damage() -> void:
	var composed := _scene(12.0)
	var helpless := _scene(12.0)
	var target := helpless.fighter(1)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	target.facing += PI / 2.0
	target.stability = 0.5
	var calm := _strike(composed)
	var caught := _strike(helpless)
	assert_true(caught.exposure > calm.exposure, "precondition: one target is far worse positioned (%.3f > %.3f)" % [caught.exposure, calm.exposure])
	assert_near(caught.impact.impulse, calm.impact.impulse, 1e-12, "fixture: the same impact arrived")
	assert_near(caught.quality, calm.quality, 1e-12, "the same strike quality")
	assert_near(caught.damage, calm.damage, 1e-12, "the same damage")
	assert_near(caught.stagger_pressure, calm.stagger_pressure, 1e-12, "the same stagger pressure")
	assert_eq(caught.critical, calm.critical, "and the same critical verdict")


func test_graze_stays_small_and_convergence_is_lethal() -> void:
	var graze := _scene(2.0)
	var small := DamageModel.evaluate(graze.fighter(0), graze.fighter(1), 1.2, 0.0, _rules)
	assert_true(small.damage < 5.0, "a slow tip graze is a scrape (%s)" % str(small.damage))
	var perfect := _scene(18.0, -3.0)
	var target := perfect.fighter(1)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	target.facing += PI / 2.0
	target.stability = 0.5
	var lethal := DamageModel.evaluate(perfect.fighter(0), target, 0.95, 0.0, _rules)
	assert_true(lethal.critical, "convergence of speed, sweet spot and alignment is classified critical")
	assert_true(lethal.damage >= _rules.combat.damage_for(_rules.combat.critical_quality), "and does at least a critical's damage (%s)" % str(lethal.damage))
	assert_true(lethal.damage > 15.0 * small.damage, "a converged cut is in another class from a graze (%s vs %s)" % [str(lethal.damage), str(small.damage)])


func test_critical_requires_every_condition() -> void:
	var state := _scene(18.0, -3.0)
	var target := state.fighter(1)
	DuelFixture.commit(target, CombatPhase.Id.OVERSWING, 1.0, _rules.combatant(0).weapon)
	target.facing += PI / 2.0
	assert_true(DamageModel.evaluate(state.fighter(0), target, 0.95, 0.0, _rules).critical, "precondition: converged strike is critical")
	assert_false(DamageModel.evaluate(state.fighter(0), target, 0.3, 0.0, _rules).critical, "hilt contact is never critical")
	target.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	target.facing -= PI / 2.0
	## v36: convergence is physical. The same strike on a composed target is
	## just as critical; the composed target's defence is not being hit.
	assert_true(DamageModel.evaluate(state.fighter(0), target, 0.95, 0.0, _rules).critical, "a composed target takes the same critical")
	var slow := _scene(6.0)
	assert_false(DamageModel.evaluate(slow.fighter(0), slow.fighter(1), 0.95, 0.0, _rules).critical, "a slow strike at the same place never converges")


func test_degenerate_contact_stays_finite() -> void:
	var state := _scene(12.0)
	var strike := DamageModel.evaluate(state.fighter(0), state.fighter(1), 0.0, 0.0, _rules)
	assert_finite(strike.quality, "quality finite at the origin")
	assert_finite(strike.damage, "damage finite at the origin")


func test_recovering_fighter_threatens_later() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 1.4, 0.0, PI)
	b.weapon.angle = 0.0
	## ARRANGE: a's blade rests square to the side, so walked forward it
	## cannot touch b (THREAT-001 counts a resting blade that can); only a
	## swing across b's bearing can — a tap from 90° sweeps through 0°.
	a.weapon.angle = deg_to_rad(90.0)
	a.weapon.stable_side = 1.0
	var horizon := float(InitiativeModel.HORIZON_TICKS) * SimulationTimebase.TICK_SECONDS
	var ready := InitiativeModel.time_to_threat(a, b, _rules)
	assert_true(ready < horizon, "precondition: ready, a's tap from the side threatens inside the horizon (%.3f s)" % ready)
	## PERTURB: the same fighter, thirty ticks of recovery floor still to sit out.
	WeaponSystem.enter_recovery(a.weapon, 30)
	## ACT + ASSERT
	var recovering := InitiativeModel.time_to_threat(a, b, _rules)
	assert_true(recovering > ready, "recovery delays the threat (%.3f s vs %.3f s)" % [recovering, ready])
	assert_true(InitiativeModel.initiative(b, a, _rules) > 0.0, "the neutral fighter holds initiative")


## THREAT-001: past its horizon the predictor has no time to give. Two targets
## out of reach read the same time — the horizon, tagged as such — and differ
## only in what was still left, which is what a ranking may use.
func test_past_the_horizon_there_is_no_invented_time() -> void:
	## ARRANGE: one target just out of the horizon's reach, one much farther.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 6.0, 0.0, PI)
	var horizon := float(InitiativeModel.HORIZON_TICKS) * SimulationTimebase.TICK_SECONDS
	## ACT
	var near := InitiativeModel.estimate(a, _rules.combatant(0), b, _rules.combatant(1), _rules.combat, ThreatEstimate.new())
	b.x = 9.0
	var far := InitiativeModel.estimate(a, _rules.combatant(0), b, _rules.combatant(1), _rules.combat, ThreatEstimate.new())
	## ASSERT
	assert_false(near.within_horizon, "precondition: 6 m is out of the horizon's reach")
	assert_false(far.within_horizon, "so is 9 m")
	assert_eq(near.hit_time, horizon, "out of the horizon the time is the horizon, nothing more")
	assert_eq(far.hit_time, horizon, "for every such target")
	assert_true(near.residual_gap > 0.0, "the gap still left is what is known (%.3f m)" % near.residual_gap)
	assert_true(far.residual_gap > near.residual_gap, "and it ranks the farther target behind (%.3f > %.3f m)" % [far.residual_gap, near.residual_gap])
	assert_eq(InitiativeModel.time_to_threat(a, b, _rules), horizon, "the time reading is the same honest horizon")
	## PERTURB: within reach the estimate is a real predicted time.
	b.x = 1.4
	var close := InitiativeModel.estimate(a, _rules.combatant(0), b, _rules.combatant(1), _rules.combat, ThreatEstimate.new())
	assert_true(close.within_horizon and close.hit_time < horizon, "in reach the time is the prediction (%.3f s)" % close.hit_time)
	assert_eq(close.residual_gap, 0.0, "with nothing left over")


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


# ── THREAT-001: time-to-threat is the actual swept blade (rules 43) ──────────


## The shipped track, attacker at the origin facing +X in Long Guard, about to
## tap toward its left (θ increasing); the target at `bearing` (rad, off the
## attacker's heading) and `distance` (m).
func _threat_scene(bearing: float, distance: float) -> MatchState:
	var state := DuelFixture.state(DuelFixture.rules())
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	attacker.weapon.reset(0.0)
	DuelFixture.place(target, distance * SimMath.cosine(bearing), distance * SimMath.sine(bearing), bearing + PI)
	return state


## A target inside the 270° control domain and inside the strike reach, but
## behind a committed cut that is sweeping away from it, is not threatened:
## coverage is not a hitbox (SLASH-SHAPE-001), and only the actual future blade
## counts.
func test_a_target_inside_the_sector_but_outside_the_sweep_reads_unthreatened() -> void:
	## ARRANGE
	var rules := DuelFixture.rules()
	var bearing := deg_to_rad(-100.0)
	var state := _committed_cut(rules, bearing)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	assert_true(absf(bearing) < rules.combatant(0).weapon.guard_limit, "fixture: the target is inside the 270° domain")
	assert_true(DuelGeometry.distance(attacker, target) < WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)), "fixture: and inside the strike reach")
	assert_true((bearing - attacker.weapon.angle) * attacker.weapon.swing_dir < 0.0, "fixture: the blade has already passed it")
	## ACT
	var threat := InitiativeModel.time_to_threat(attacker, target, rules)
	## ASSERT: the blade is sweeping away from it, so the only way to reach it
	## is the heading turning the sweep back round — at least the gap between
	## the blade and the target, at the heading's top rate. Being inside the
	## 270° domain is never a hit by itself.
	var gap := absf(bearing - attacker.weapon.angle)
	var earliest := gap / rules.combatant(0).fighter.turn_speed_max
	assert_true(threat >= earliest - 1e-9, "the target behind the blade waits for the heading to turn %.0f° (%.3f s ≥ %.3f s)" % [rad_to_deg(gap), threat, earliest])
	## PERTURB: the same target ahead of the blade is threatened at once.
	var ahead := _committed_cut(rules, deg_to_rad(20.0))
	var at_once := InitiativeModel.time_to_threat(ahead.fighter(0), ahead.fighter(1), rules)
	assert_true(at_once < earliest and at_once < threat, "control: a target the cut is sweeping toward is threatened sooner (%.3f s)" % at_once)


## A sidestep out of a committed cut's path raises the attacker's threat time:
## the cut in flight sweeps on, and a committed heading cannot bring it back.
func test_a_sidestep_raises_the_attackers_threat_time() -> void:
	## ARRANGE: a full cut in flight from the right, sweeping left, committed.
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(0).weapon
	var front := _committed_cut(rules, 0.0)
	var stepped := _committed_cut(rules, deg_to_rad(-100.0))
	## ACT
	var in_path := InitiativeModel.time_to_threat(front.fighter(0), front.fighter(1), rules)
	var out_of_path := InitiativeModel.time_to_threat(stepped.fighter(0), stepped.fighter(1), rules)
	## ASSERT
	assert_true(front.fighter(0).weapon.commitment > 0.5, "fixture: the cut is committed (K %.2f)" % front.fighter(0).weapon.commitment)
	assert_true(in_path < 0.15, "a target in the cut's path is threatened at once (%.3f s)" % in_path)
	assert_true(out_of_path > in_path + 0.2, "a target that stepped behind the blade is threatened much later (%.3f vs %.3f s)" % [out_of_path, in_path])
	## PERTURB: mirrored, the same.
	var mirrored := _committed_cut(rules, deg_to_rad(100.0), -1.0)
	assert_near(InitiativeModel.time_to_threat(mirrored.fighter(0), mirrored.fighter(1), rules), out_of_path, 1e-9, "and the mirrored scene reads exactly the same")
	assert_true(weapon.guard_limit > deg_to_rad(100.0), "fixture: the stepped bearing is still inside the domain")


## THREAT-COMMIT-001: on an empty line the estimate and the duel agree. A
## full committed cut in flight at a target whose own blade is turned away
## beyond its torso, so nothing but the torso lies on the cut's line: the
## estimate taken from the scene and the tick the real simulation (the same
## state, rolled on, the target idle) first strikes the body are the same
## time, to one tick, across bearings, distances and how far the cut still
## has to travel.
func test_on_an_empty_line_the_threat_estimate_is_the_strike_the_duel_lands() -> void:
	var rules := DuelFixture.rules()
	var definition := rules.combatant(0).weapon
	var tick := SimulationTimebase.TICK_SECONDS
	for bearing_deg: float in [0.0, 15.0]:
		for distance: float in [1.3, 1.5]:
			for travel_deg: float in [60.0, 40.0, 20.0]:
				## ARRANGE
				var runner := SimRunner.create(rules, 7)
				runner.skip_intro()
				var attacker := runner.state.fighter(0)
				var target := runner.state.fighter(1)
				var bearing := deg_to_rad(bearing_deg)
				DuelFixture.place(attacker, 0.0, 0.0, 0.0)
				attacker.weapon.reset(0.0)
				DuelFixture.place(target, distance * SimMath.cosine(bearing), distance * SimMath.sine(bearing), bearing + PI)
				target.weapon.reset(0.0)
				target.weapon.angle = -PI * 0.5
				var w := attacker.weapon
				w.phase = CombatPhase.Id.ACTIVE_EARLY
				w.swing_dir = 1.0
				w.swing_charge = 1.0
				w.launch_preparation = 1.0
				w.swing_start = -definition.guard_limit
				w.swing_end = w.swing_start + definition.arc(1.0)
				w.angle = -deg_to_rad(travel_deg)
				w.speed = definition.swing_speed_full
				w.stable_side = -1.0
				w.commitment = CommitmentModel.commitment(w, definition)
				var label := "bearing %+.0f°, %.1f m, %.0f° to travel" % [bearing_deg, distance, travel_deg]
				## ACT
				var estimate := InitiativeModel.time_to_threat(attacker, target, rules)
				var start := runner.state.tick
				var struck := -1
				for _i in 40:
					runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
					var hit := runner.first(DuelEventTypes.BODY_HIT)
					if hit != null:
						struck = hit.tick - start + 1
						break
				## ASSERT
				assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT), 0, "fixture (%s): the line is empty — no steel is met" % label)
				assert_true(w.commitment > 0.5, "fixture (%s): the cut is committed" % label)
				assert_true(struck > 0, "the real cut lands (%s)" % label)
				assert_near(estimate, float(struck) * tick, tick + 1.0e-9, "the estimate is the strike the duel lands (%s: %.3f s vs %.3f s)" % [label, estimate, float(struck) * tick])


## A full cut from the right (`side` = +1) or the left (−1), 40° short of the
## centre, at full speed; the target 1.3 m off at `bearing`.
func _committed_cut(rules: DuelRules, bearing: float, side: float = 1.0) -> MatchState:
	var state := _threat_scene(bearing, 1.3)
	var w := state.fighter(0).weapon
	var definition := rules.combatant(0).weapon
	w.phase = CombatPhase.Id.ACTIVE_EARLY
	w.swing_dir = side
	w.swing_charge = 1.0
	w.launch_preparation = 1.0
	w.swing_start = -side * definition.guard_limit
	w.swing_end = w.swing_start + side * definition.arc(1.0)
	w.angle = -side * deg_to_rad(40.0)
	w.speed = side * definition.swing_speed_full
	w.stable_side = -side
	w.commitment = CommitmentModel.commitment(w, definition)
	return state


## An injured attacker threatens later — through its own weaker actuators
## (CONDITION-001), with no injury branch anywhere in the estimate.
func test_an_injured_attacker_threatens_later() -> void:
	## ARRANGE: the tap has to travel to reach the target.
	var rules := DuelFixture.rules()
	var healthy := _threat_scene(deg_to_rad(50.0), 1.35)
	var wounded := _threat_scene(deg_to_rad(50.0), 1.35)
	wounded.fighter(0).health = 5.0
	## ACT
	var fresh := InitiativeModel.time_to_threat(healthy.fighter(0), healthy.fighter(1), rules)
	var hurt := InitiativeModel.time_to_threat(wounded.fighter(0), wounded.fighter(1), rules)
	## ASSERT
	var horizon := float(InitiativeModel.HORIZON_TICKS) * SimulationTimebase.TICK_SECONDS
	assert_true(fresh < horizon, "fixture: the healthy tap reaches the target within the horizon (%.3f s)" % fresh)
	assert_true(hurt > fresh, "the wounded attacker's blade arrives later (%.3f vs %.3f s)" % [hurt, fresh])
	## PERTURB: the target's own wounds change nothing about the attacker's threat.
	healthy.fighter(1).health = 20.0
	assert_eq(InitiativeModel.time_to_threat(healthy.fighter(0), healthy.fighter(1), rules), fresh, "only the attacker's condition counts")


## The estimate is bounded work: a target out of every reach runs exactly the
## horizon and stops there — tagged out of it, reading the horizon, and keeping
## the gap the footwork could not close. No closed-form tail of seconds.
func test_the_threat_estimate_is_bounded() -> void:
	## ARRANGE
	var rules := DuelFixture.rules()
	var far := _threat_scene(0.0, 9.0)
	var attacker := far.fighter(0)
	var target := far.fighter(1)
	## ACT
	var estimate := InitiativeModel.estimate(attacker, rules.combatant(0), target, rules.combatant(1), rules.combat, ThreatEstimate.new())
	## ASSERT
	var dt := SimulationTimebase.TICK_SECONDS
	var horizon := float(InitiativeModel.HORIZON_TICKS) * dt
	assert_eq(InitiativeModel.HORIZON_TICKS, 30, "the horizon is half a second")
	assert_false(estimate.within_horizon, "a distant target is out of the horizon")
	assert_eq(estimate.hit_time, horizon, "and reads the horizon, never more")
	## The predicted footwork closes at most max_speed for the whole horizon,
	## so at least the rest of the distance is still left.
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var closed := rules.combatant(0).fighter.max_speed * horizon
	var still_to_close := 9.0 - reach - closed
	assert_true(estimate.residual_gap >= still_to_close - rules.combatant(0).weapon.blade_radius - 1e-9, "the gap left is at least what top speed could not close (%.3f m)" % estimate.residual_gap)


## THREAT-001, HAND-CONTACT-001: a hand is damageable, so the threat is the
## earliest of the torso and either hand. Scanned out from close range, the
## first distance a target turned away (its hands behind it) is out of the
## horizon's reach — the torso alone out of reach — the same target facing the
## attacker, its hands out in front, is threatened inside the horizon. The
## slot-swapped scene reads the same estimate exactly.
func test_a_hand_in_reach_is_a_threat_when_the_torso_is_not() -> void:
	## ARRANGE
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	var distance := 1.4
	var turned := ThreatEstimate.new()
	while distance < 4.0:
		DuelFixture.place(target, distance, 0.0, 0.0)
		InitiativeModel.estimate(attacker, rules.combatant(0), target, rules.combatant(1), rules.combat, turned)
		if not turned.within_horizon:
			break
		distance += 0.01
	assert_false(turned.within_horizon, "fixture: turned away at %.2f m, the torso is out of reach" % distance)
	## PERTURB: the same target, facing the attacker, hands forward.
	DuelFixture.place(target, distance, 0.0, PI)
	## ACT
	var facing := InitiativeModel.estimate(attacker, rules.combatant(0), target, rules.combatant(1), rules.combat, ThreatEstimate.new())
	## ASSERT
	assert_true(facing.within_horizon, "its hands are in reach (%.3f s)" % facing.hit_time)
	assert_eq(facing.residual_gap, 0.0, "with nothing left over")
	## Mirror: the slots swapped, the same scene.
	DuelFixture.place(target, 0.0, 0.0, 0.0)
	DuelFixture.place(attacker, distance, 0.0, PI)
	var mirrored := InitiativeModel.estimate(target, rules.combatant(1), attacker, rules.combatant(0), rules.combat, ThreatEstimate.new())
	assert_eq(mirrored.within_horizon, facing.within_horizon, "the mirror is threatened too")
	assert_eq(mirrored.hit_time, facing.hit_time, "at exactly the same time")


## REVERSAL-DEBT-001 (THREAT-READINESS-001): readiness is the state, not the
## position. The same blade at the same angle, once turning back toward the
## line and once still flying away from it, threatens later when it must first
## arrest and reverse that momentum — whether it is above or under control
## speed. The mirrored scene reads exactly the same times.
func test_a_blade_turning_away_threatens_later_than_one_turning_back() -> void:
	var weapon := _rules.combatant(0).weapon
	for rate: float in [weapon.control_speed * 0.5, 6.0]:
		var times := {}
		for side: float in [1.0, -1.0]:
			for heading: String in ["back", "away"]:
				## ARRANGE: a's blade 60° off the line on `side`, b square in front
				## in a centred Long Guard, so the scene is its own mirror.
				var state := DuelFixture.state(_rules)
				var a := state.fighter(0)
				var b := state.fighter(1)
				DuelFixture.place(a, 0.0, 0.0, 0.0)
				DuelFixture.place(b, 1.4, 0.0, PI)
				b.weapon.angle = 0.0
				a.weapon.angle = side * deg_to_rad(60.0)
				WeaponSystem.update_stable_side(a.weapon, weapon)
				## PERTURB: turning back toward the line, or away from it.
				a.weapon.speed = -side * rate if heading == "back" else side * rate
				## ACT
				times["%+.0f %s" % [side, heading]] = InitiativeModel.estimate(a, _rules.combatant(0), b, _rules.combatant(1), _rules.combat, ThreatEstimate.new())
		## ASSERT
		var back: ThreatEstimate = times["+1 back"]
		var away: ThreatEstimate = times["+1 away"]
		assert_true(back.within_horizon, "fixture (%.1f rad/s): turning back threatens inside the horizon (%.3f s)" % [rate, back.hit_time])
		assert_true(away.within_horizon, "fixture (%.1f rad/s): so does turning away, eventually (%.3f s)" % [rate, away.hit_time])
		assert_true(away.hit_time > back.hit_time, "at %.1f rad/s the blade flying away threatens later (%.3f s > %.3f s)" % [rate, away.hit_time, back.hit_time])
		assert_eq((times["-1 back"] as ThreatEstimate).hit_time, back.hit_time, "the mirrored blade turning back reads the same time")
		assert_eq((times["-1 away"] as ThreatEstimate).hit_time, away.hit_time, "and turning away")


## THREAT-READINESS-001: the estimate cuts the way the duel would. A blade
## carried across the centre by its own momentum is committed to its new side
## (COMBAT-005) before it is back under control and can launch, so two states
## differing only in the side remembered *now* evolve identically in the duel
## — and must read identically here.
func test_the_threat_follows_the_side_the_blade_will_commit_to() -> void:
	var weapon := _rules.combatant(0).weapon
	var estimates: Array[ThreatEstimate] = []
	var settled: Array[PackedFloat64Array] = []
	for remembered: float in [1.0, -1.0]:
		## ARRANGE: a's blade just left of centre, crossing to the right far
		## faster than control speed; b far enough that nothing is met.
		var runner := SimRunner.create(_rules, 1)
		runner.skip_intro()
		var a := runner.state.fighter(0)
		var b := runner.state.fighter(1)
		DuelFixture.place(a, 0.0, 0.0, 0.0)
		DuelFixture.place(b, 2.6, 0.0, PI)
		a.weapon.angle = deg_to_rad(5.0)
		a.weapon.speed = -6.0
		## PERTURB: the side it remembers before the crossing.
		a.weapon.stable_side = remembered
		## ACT: the estimate now, then the duel itself until the blade is
		## back under control.
		estimates.append(InitiativeModel.estimate(a, _rules.combatant(0), b, _rules.combatant(1), _rules.combat, ThreatEstimate.new()))
		var ticks := 0
		while absf(a.weapon.speed) > weapon.control_speed and ticks < 60:
			runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
			ticks += 1
		settled.append(PackedFloat64Array([ticks, a.weapon.angle, a.weapon.stable_side]))
	## ASSERT
	assert_eq(settled[0], settled[1], "fixture: the duel evolves both identically")
	assert_true(settled[0][1] < -weapon.side_deadzone, "fixture: the blade is past the centre band (%.1f°) when it comes under control" % rad_to_deg(settled[0][1]))
	assert_eq(settled[0][2], -1.0, "fixture: and committed to its new side")
	assert_true(estimates[0].hit_time > 0.0, "the estimate is a real reading (%.3f s)" % estimates[0].hit_time)
	assert_eq(estimates[0].hit_time, estimates[1].hit_time, "whichever side it remembered before the crossing")
	assert_eq(estimates[0].residual_gap, estimates[1].residual_gap, "with the same residual")


## HAND-CONTACT-001: a hand wound is the ordinary damage model at the target's
## hand share. The same wound against a share of 1 differs only by that share:
## the same quality, and health falls by exactly the damage reported.
func test_a_hand_wound_is_the_ordinary_strike_at_the_hand_share() -> void:
	var wounds: Array[DuelEvent] = []
	var lost: Array[float] = []
	for share: float in [-1.0, 1.0]:
		## ARRANGE: fighter 0's blade square across fighter 1's off hand,
		## a centimetre into the disc, driving in at 3 m/s.
		var rules := DuelFixture.rules()
		if share > 0.0:
			## PERTURB: the whole wound, no hand share.
			rules.combatant(1).fighter.hand_damage_factor = share
		var state := DuelFixture.state(rules)
		var holder := state.fighter(1)
		DuelFixture.place(holder, 0.0, 0.0, 0.0)
		holder.weapon.angle = 0.0
		var held := WeaponKinematics.pose_of(holder, rules.combatant(1), BladePose.new())
		var grip := rules.combatant(1).weapon.offhand_grip_radius
		var nx := -held.uy
		var ny := held.ux
		var into := rules.combatant(1).fighter.hand_radius + rules.combatant(0).weapon.blade_radius - 0.01
		var direction := atan2(-ny, -nx)
		var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, rules.combatant(0), BladePose.new())
		var striker := state.fighter(0)
		DuelFixture.place(striker, held.point_x(grip) + nx * into - reach.point_x(rules.combatant(0).weapon.tip_radius), held.point_y(grip) + ny * into - reach.point_y(rules.combatant(0).weapon.tip_radius), direction)
		striker.weapon.angle = 0.0
		striker.vx = -nx * 3.0
		striker.vy = -ny * 3.0
		var before := holder.health
		## ACT
		var events: Array[DuelEvent] = []
		ContactResolver.wound_hand(state, rules, 0, grip, 0.5, 1, events)
		## ASSERT
		assert_eq(events.size(), 1, "fixture (share %s): one wound" % str(share))
		assert_eq(events[0].text(DuelEventKeys.REGION), DuelEventKeys.REGION_HAND, "on the hand")
		assert_true(holder.is_alive(), "never an instant kill")
		assert_true(striker.weapon.hand_struck, "the attack's hand episode is spent")
		wounds.append(events[0])
		lost.append(before - holder.health)
	var shipped := wounds[0].number(DuelEventKeys.DAMAGE)
	var whole := wounds[1].number(DuelEventKeys.DAMAGE)
	assert_true(whole > 0.0, "fixture: the blade wounds (%.4f)" % whole)
	assert_eq(wounds[0].number(DuelEventKeys.QUALITY), wounds[1].number(DuelEventKeys.QUALITY), "the same strike quality either way")
	assert_near(shipped, whole * DuelFixture.rules().combatant(1).fighter.hand_damage_factor, 1e-12, "the shipped wound is the hand share of the whole")
	assert_near(lost[0], shipped, 1e-12, "and health falls by exactly that")