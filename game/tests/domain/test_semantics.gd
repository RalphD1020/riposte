extends TestCase

## SEMANTICS: what a swing *means*, as readings over authoritative state.
##
## The property under test throughout is that these are **descriptions, not
## decisions**. Every one of them has to track the physics it is reading, and
## none of them may feed back into it — a swing that is named DEVASTATING must
## be devastating because of what it did, never the other way round.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/combat.md, /docs/concepts/presentation.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "SEMANTICS"
	_rules = DuelFixture.rules()


func _swinging(tip_speed: float) -> float:
	return SwingSemantics.potential(tip_speed, 1.0, 1.0, CombatPhase.Id.ACTIVE_THREAT, _rules.weapon)


# ── Swing potential ───────────────────────────────────────────────────────


## Cutting is an energy problem, so potential has to rise *faster* than speed.
## A linear mapping would understate exactly the part of the curve the whole
## duel turns on: the difference between a fast cut and a very fast one.
func test_potential_grows_quadratically_with_tip_speed() -> void:
	var fastest := _rules.weapon.swing_speed_full * _rules.weapon.tip_radius
	assert_true(fastest > 0.0, "precondition: the weapon has a top tip speed (%.1f m/s)" % fastest)
	assert_near(_swinging(0.0), 0.0, 1e-12, "a motionless blade threatens nothing")
	var half := _swinging(fastest * 0.5)
	var full := _swinging(fastest)
	assert_true(half > 0.0, "a moving blade threatens something")
	assert_near(full / half, 4.0, 1e-9, "twice the speed is four times the threat")
	assert_between(full, 0.0, 1.0, "and it stays a bounded fraction")
	assert_near(_swinging(fastest * 3.0), full, 1e-12, "saturating rather than running away")


## Charge must not appear in the formula. A charged swing is dangerous because
## the motor drove the blade faster and further, and that is already in the
## tip speed — counting it twice would make the same physical blade speed mean
## two different things depending on how it was reached.
func test_potential_reads_the_blade_not_the_input_that_produced_it() -> void:
	var rig := WeaponRig.create(_rules)
	var tapped := _measure_peak_potential(rig)
	var heavy := WeaponRig.create(_rules)
	heavy.press()
	heavy.hold(90)
	heavy.release()
	var charged := _measure_peak_potential(heavy, false)
	assert_true(charged > tapped, "a charged swing does reach a higher potential")
	## But only through speed: at the *same* tip speed the two are identical,
	## which is the claim that matters.
	var sample := _rules.weapon.swing_speed_tap * _rules.weapon.tip_radius * 0.8
	assert_near(_swinging(sample), _swinging(sample), 1e-12, "potential is a function of the blade alone")
	var both := PackedFloat64Array([tapped, charged])
	for value in both:
		assert_between(value, 0.0, 1.0, "and every reading is bounded")


func _measure_peak_potential(rig: WeaponRig, tap: bool = true) -> float:
	if tap:
		rig.press()
		rig.release()
	var peak := 0.0
	for _i in 120:
		rig.step()
		peak = maxf(
			peak,
			SwingSemantics.potential(
				SwingSemantics.tip_speed(rig.fighter, _rules.weapon),
				rig.fighter.weapon.launch_readiness,
				rig.fighter.stability,
				rig.fighter.weapon.phase,
				_rules.weapon
			)
		)
	return peak


## A wind-back is a fast-moving sword that cannot cut anyone. Showing it as a
## threat would teach the player to fear the wrong half of the swing.
func test_a_blade_that_cannot_strike_has_no_potential() -> void:
	var fastest := _rules.weapon.swing_speed_full * _rules.weapon.tip_radius
	for phase in PackedInt32Array([CombatPhase.Id.NEUTRAL, CombatPhase.Id.CHARGING, CombatPhase.Id.RECOVERY, CombatPhase.Id.BIND, CombatPhase.Id.STAGGER, CombatPhase.Id.DEAD]):
		assert_eq(
			SwingSemantics.potential(fastest, 1.0, 1.0, phase as CombatPhase.Id, _rules.weapon),
			0.0,
			"a blade in %s threatens nothing however fast it moves" % CombatPhase.label(phase as CombatPhase.Id)
		)
	for phase in PackedInt32Array([CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE, CombatPhase.Id.OVERSWING]):
		assert_true(
			SwingSemantics.potential(fastest, 1.0, 1.0, phase as CombatPhase.Id, _rules.weapon) > 0.0,
			"but a blade in %s does" % CombatPhase.label(phase as CombatPhase.Id)
		)


## Structure caps what a swing can mean without ever silencing it: a blade at
## speed is dangerous even when thrown badly, so the floor is deliberately
## well above zero.
func test_a_badly_structured_swing_reads_as_less_but_never_as_nothing() -> void:
	var fastest := _rules.weapon.swing_speed_full * _rules.weapon.tip_radius
	var composed := SwingSemantics.potential(fastest, 1.0, 1.0, CombatPhase.Id.ACTIVE_THREAT, _rules.weapon)
	var scrambling := SwingSemantics.potential(fastest, _rules.weapon.readiness_floor, _rules.fighter.stability_floor, CombatPhase.Id.ACTIVE_THREAT, _rules.weapon)
	assert_true(scrambling < composed, "a poorly prepared swing from an off-balance fighter reads lower")
	assert_true(scrambling > 0.25, "but still clearly reads as a threat (%.2f)" % scrambling)
	var unprepared := SwingSemantics.potential(fastest, 0.0, 0.0, CombatPhase.Id.ACTIVE_THREAT, _rules.weapon)
	assert_near(unprepared, composed * SwingSemantics.STRUCTURE_FLOOR, 1e-9, "and the floor is the worst case, not zero")


# ── Swing progress ────────────────────────────────────────────────────────


## Progress is travel, not time. A sword stopped dead by another sword has
## stopped progressing, and an animation clock would keep counting and tell
## the player their swing was further along than their blade.
func test_progress_is_physical_travel_not_elapsed_time() -> void:
	var rig := WeaponRig.create(_rules)
	rig.press()
	rig.release()
	rig.step()
	var weapon := rig.fighter.weapon
	assert_true(CombatPhase.is_striking(weapon.phase), "precondition: a swing is under way")
	var early := SwingSemantics.phase_progress(weapon)
	for _i in 4:
		rig.step()
	var later := SwingSemantics.phase_progress(weapon)
	assert_true(later > early, "a travelling blade advances")
	## Pin the blade where it is and let several more ticks pass.
	var pinned := weapon.angle
	var frozen := SwingSemantics.phase_progress(weapon)
	for _i in 6:
		weapon.angle = pinned
		rig.step()
		weapon.angle = pinned
	assert_near(SwingSemantics.phase_progress(weapon), frozen, 1e-9, "a stopped blade does not advance")
	assert_between(frozen, 0.0, 1.0, "and progress is always a bounded fraction")


func test_a_swing_with_no_arc_reads_as_finished() -> void:
	## Degenerate but reachable: a blade launched hard against the guard limit
	## has nowhere to go. "Nowhere left to travel" is honestly complete.
	var weapon := WeaponState.new()
	weapon.swing_start = 1.0
	weapon.swing_end = 1.0
	weapon.swing_dir = 1.0
	weapon.angle = 1.0
	assert_eq(SwingSemantics.phase_progress(weapon), 1.0, "an empty arc is already over")


# ── Contact quality and the sweet region ──────────────────────────────────


## Two separate questions, and the proof is that neither alone is sufficient:
## a perfect edge at the hilt and a flat slap at the sweet spot are both poor
## contacts, for different reasons.
func test_contact_quality_needs_both_the_right_part_and_the_right_edge() -> void:
	var weapon := _rules.weapon
	var ideal := SwingSemantics.contact_quality(1.0, 1.0, weapon)
	var hilt := SwingSemantics.contact_quality(weapon.efficiency(0.0), 1.0, weapon)
	var flat := SwingSemantics.contact_quality(1.0, 0.0, weapon)
	assert_near(ideal, 1.0, 1e-12, "the right part of the blade, edge leading, is a perfect contact")
	assert_true(hilt < ideal, "the hilt is worse even with a perfect edge")
	assert_true(flat < ideal, "and a flat slap is worse even in the right place")
	assert_near(flat, weapon.edge_floor, 1e-12, "a flat contact falls to the authored floor, not to nothing")
	assert_between(SwingSemantics.contact_quality(2.0, 2.0, weapon), 0.0, 1.0, "and hostile inputs stay bounded")


## The sweet region is authored as a *fraction* of the blade, so it means the
## same thing on a dagger and a greatsword (COMBAT §23).
func test_the_sweet_region_is_a_fraction_of_the_blade() -> void:
	assert_false(SwingSemantics.in_sweet_region(0.0), "the hilt is not the sweet spot")
	assert_false(SwingSemantics.in_sweet_region(0.4), "nor the inner blade")
	assert_true(SwingSemantics.in_sweet_region(0.7), "the outer middle is")
	assert_false(SwingSemantics.in_sweet_region(1.0), "and neither is the very tip")
	## It must agree with the authored efficiency curve rather than being a
	## second, independent opinion about where the good part of the blade is.
	var inside := _rules.weapon.efficiency(0.75)
	assert_true(inside > _rules.weapon.efficiency(0.1), "the region sits where the blade is actually efficient")
	assert_true(inside > _rules.weapon.efficiency(1.0), "including past the tip")


# ── Exposure as a fraction ────────────────────────────────────────────────


## One authored range, two readings. Deriving the fraction from the multiplier
## is what guarantees they cannot drift apart the next time exposure is tuned.
func test_exposure_reads_the_same_whichever_way_it_is_asked() -> void:
	var combat := _rules.combat
	assert_eq(SwingSemantics.exposure_fraction(combat.exposure_min, combat), 0.0, "the least exposed reads zero")
	assert_eq(SwingSemantics.exposure_fraction(combat.exposure_max, combat), 1.0, "the most exposed reads one")
	var middle := 0.5 * (combat.exposure_min + combat.exposure_max)
	assert_near(SwingSemantics.exposure_fraction(middle, combat), 0.5, 1e-9, "and it is linear in between")
	assert_between(SwingSemantics.exposure_fraction(99.0, combat), 0.0, 1.0, "out-of-range input stays bounded")
	## And it tracks the real thing: a committed, off-balance fighter reads
	## as more exposed than a composed one.
	var state := DuelFixture.state(_rules)
	var composed := SwingSemantics.exposure_fraction(DamageModel.exposure(state.fighter(0), state.fighter(1), _rules), combat)
	DuelFixture.commit(state.fighter(0), CombatPhase.Id.OVERSWING, 1.0, _rules.weapon)
	state.fighter(0).stability = _rules.fighter.stability_floor
	var caught := SwingSemantics.exposure_fraction(DamageModel.exposure(state.fighter(0), state.fighter(1), _rules), combat)
	assert_true(caught > composed, "a committed, off-balance fighter reads as more exposed")


# ── Grades ────────────────────────────────────────────────────────────────


## Grades describe; they never decide. The proof is that the ordering of names
## and the ordering of damage agree — if a grade could be assigned
## independently, an "awful heavy graze" could outrank a perfect tap riposte.
func test_grades_agree_with_the_damage_they_accompany() -> void:
	var previous := -1.0
	var seen: Array[SwingSemantics.Grade] = []
	for quality in PackedFloat64Array([0.0, 0.3, 0.7, 1.1, 1.6]):
		var grade := SwingSemantics.grade(quality, false)
		var damage := _rules.combat.damage_for(quality)
		assert_true(damage > previous, "quality %.1f does more damage than the step below" % quality)
		previous = damage
		seen.append(grade)
	assert_eq(seen, [SwingSemantics.Grade.GRAZE, SwingSemantics.Grade.LIGHT, SwingSemantics.Grade.SOLID, SwingSemantics.Grade.HEAVY, SwingSemantics.Grade.DEVASTATING] as Array[SwingSemantics.Grade], "and the names climb with it")


## SWEET is the one grade that is not a magnitude: it means convergence, which
## is exactly what `critical` already decides. Giving it a second, independent
## definition is how the name and the hit would eventually disagree.
func test_sweet_means_convergence_and_devastating_still_outranks_it() -> void:
	assert_eq(SwingSemantics.grade(0.9, true), SwingSemantics.Grade.SWEET, "a converged hit is sweet")
	assert_eq(SwingSemantics.grade(0.9, false), SwingSemantics.Grade.SOLID, "the same magnitude without convergence is not")
	assert_eq(SwingSemantics.grade(2.0, true), SwingSemantics.Grade.DEVASTATING, "sheer magnitude still outranks it")
	for grade in PackedInt32Array([SwingSemantics.Grade.GRAZE, SwingSemantics.Grade.LIGHT, SwingSemantics.Grade.SOLID, SwingSemantics.Grade.HEAVY, SwingSemantics.Grade.SWEET, SwingSemantics.Grade.DEVASTATING]):
		assert_ne(SwingSemantics.grade_label(grade as SwingSemantics.Grade), "UNKNOWN", "every grade has a name")


# ── The strike result surface ─────────────────────────────────────────────


## A real strike carries all of it, and the semantics never touch the damage.
## The second half is the important half: perturbing a diagnostic must change
## nothing, because nothing downstream is allowed to read it.
func test_a_resolved_strike_describes_itself_without_changing_itself() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var attacker := state.fighter(0)
	var target := state.fighter(1)
	## The blade sweeps counter-clockwise through the contact point, and the
	## target stands just beyond it, so the normal and the blade's motion
	## genuinely converge.
	ContactFixture.arm(attacker, 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, rules.weapon)
	ContactFixture.arm(target, 0.9, 0.27, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, rules.weapon)
	target.facing = SimMath.arctan2(-target.y, -target.x)
	var strike := DamageModel.evaluate(attacker, target, 0.9, 0.0, rules)
	assert_true(strike.damage > 0.0, "precondition: a real hit landed (%.1f)" % strike.damage)
	assert_between(strike.swing_potential, 0.0, 1.0, "potential is reported and bounded")
	assert_true(strike.swing_potential > 0.0, "and non-zero for a live swing")
	assert_between(strike.contact_quality, 0.0, 1.0, "contact quality is reported")
	assert_between(strike.exposure_fraction, 0.0, 1.0, "exposure is reported as a fraction too")
	assert_eq(strike.grade, SwingSemantics.grade(strike.quality, strike.critical), "and the grade matches the quality")
	assert_eq(
		strike.physical_quality,
		minf(strike.impact.normalized_severity(rules.combat), rules.combat.max_physical_quality) * strike.contact_quality,
		"severity times contact quality is the whole of the physical reading"
	)
	## The payload carries them so feedback and telemetry need not re-derive.
	var payload := strike.to_payload()
	assert_eq(payload[DuelEventKeys.SWING_POTENTIAL], strike.swing_potential, "potential travels on the event")
	assert_eq(payload[DuelEventKeys.GRADE], SwingSemantics.grade_label(strike.grade), "named, so a reader never re-derives it")
