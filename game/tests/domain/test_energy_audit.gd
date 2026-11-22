extends TestCase

## ENERGY-AUDIT: the weapon motor's work against the held sword's kinetic
## energy `K = ½·M_θ(θ)·θ̇²`, and what a clean hit actually delivers, on the
## reference duelist. Characterization of the current law, measured, not tuned:
## the motor integrates `M_θ·θ̈ = τ` (UNIFIED-MASS-001), which leaves the
## configuration term `½·M_θ′·θ̇²` of the generalized equation out, so along a
## track whose inertia changes, `K` changes by `Σ ½·ΔM_θ·θ̇²` that no torque
## did. The audit pins that ledger so the versioned fix (weapons plan) is
## measurable; it asserts no damage rule.
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "ENERGY-AUDIT"
	_rules = DuelFixture.rules()


## Steps an attack (`charged` holds to full charge first) through its swing
## and overswing; per tick the kinetic-energy change, the motor's work at the
## mid-step speed, and the configuration term at the new speed.
func _ledger(start: float, charged: bool) -> Dictionary:
	var spec := _rules.combatant(0)
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(start))
	var w := rig.fighter.weapon
	if charged:
		rig.press()
		while w.charge < 1.0 and rig.tick < 240:
			rig.step()
		rig.release()
	else:
		rig.step(true, true)
	var limit_inner := spec.weapon.guard_limit - _rules.combat.guard_limit_zone
	var out := {"dk": 0.0, "work": 0.0, "config": 0.0, "worst_tick_residual": 0.0, "peak_k": 0.0, "ticks": 0}
	for _i in 120:
		var theta0 := w.angle
		var omega0 := w.speed
		var m0 := WeaponKinematics.motor_inertia(spec, theta0)
		var phase0 := w.phase
		rig.step()
		var m1 := WeaponKinematics.motor_inertia(spec, w.angle)
		var swinging := CombatPhase.is_swinging(phase0) or phase0 == CombatPhase.Id.OVERSWING
		if swinging and absf(w.angle) < limit_inner and absf(theta0) < limit_inner:
			var dk := 0.5 * m1 * w.speed * w.speed - 0.5 * m0 * omega0 * omega0
			var work := w.motor_torque * 0.5 * (omega0 + w.speed) * SimulationTimebase.TICK_SECONDS
			var config := 0.5 * (m1 - m0) * w.speed * w.speed
			out["dk"] += dk
			out["work"] += work
			out["config"] += config
			out["ticks"] += 1
			out["worst_tick_residual"] = maxf(out["worst_tick_residual"], absf(dk - work - config))
			out["peak_k"] = maxf(out["peak_k"], 0.5 * m1 * w.speed * w.speed)
		if w.phase == CombatPhase.Id.NEUTRAL and _i > 5:
			break
	return out


func test_the_motor_ledger_is_work_plus_the_unmodelled_configuration_term() -> void:
	## ARRANGE: the inertia really changes along the track (the fixture the term needs).
	var spec := _rules.combatant(0)
	var m45 := WeaponKinematics.motor_inertia(spec, PI * 0.25)
	var m0 := WeaponKinematics.motor_inertia(spec, 0.0)
	assert_true(absf(m45 - m0) > 0.2, "fixture: M_θ varies along the track (%.3f at 45° vs %.3f at 0°)" % [m45, m0])
	for case: Array in [["tap from Ready", -45.0, false], ["tap from the centre", 0.0, false], ["full charge", -45.0, true]]:
		## ACT
		var ledger := _ledger(float(case[1]), bool(case[2]))
		## ASSERT: tick by tick, ΔK = motor work + ½·ΔM_θ·θ̇² exactly (the law as
		## integrated), so nothing else — no hidden impulse, no speed assignment —
		## moves the blade's energy in free flight.
		assert_true(ledger["ticks"] > 4, "fixture: %s has free-flight ticks to audit (%d)" % [case[0], ledger["ticks"]])
		assert_true(ledger["worst_tick_residual"] < 1e-9, "%s: every tick reconciles (worst %.2e J)" % [case[0], ledger["worst_tick_residual"]])
		## The configuration term is the measured gap a generalized law would close:
		## pinned in a band so its versioned fix shows up here.
		assert_between(absf(ledger["config"]) / ledger["peak_k"], 0.0, 0.25, "%s: the unmodelled term is %.1f J of a %.1f J peak" % [case[0], ledger["config"], ledger["peak_k"]])
	## PERTURB: a full charge sweeps more of the inertia profile at more speed,
	## so its unmodelled term is larger than a Ready tap's.
	var tap := _ledger(-45.0, false)
	var full := _ledger(-45.0, true)
	assert_true(absf(full["config"]) > absf(tap["config"]), "full charge %.1f J > Ready tap %.1f J" % [full["config"], tap["config"]])


func test_a_clean_hit_delivers_what_its_speed_earns_and_never_more() -> void:
	## ARRANGE: the reference configuration (Long Guard, the centre of percussion,
	## square to the blade, a standing reference body), only the swing speed varies.
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var radius := ContactMechanics.percussion_radius(weapon)
	var lever := WeaponKinematics.lever(FighterState.new(), pose, pose.point_x(radius), pose.point_y(radius), -pose.uy, pose.ux)
	var inverse_mass := ContactMechanics.reference_inverse_mass(spec, spec)
	var pair := _rules.sword_body_pair(0)
	assert_between(lever, 0.70, 0.80, "fixture: the centre of percussion's lever from Long Guard (%.3f m)" % lever)
	var energies := {}
	for case: Array in [["centre tap", weapon.achievable_swing_speed(0.0, 0.0)], ["prepared tap", weapon.achievable_swing_speed(0.0, 1.0)], ["half charge", weapon.achievable_swing_speed(0.5, 1.0)], ["full charge", weapon.achievable_swing_speed(1.0, 1.0)]]:
		## ACT
		var omega: float = case[1]
		var closing := lever * omega
		var e := pair.restitution_at(closing)
		var dissipated := ContactMechanics.dissipated_energy(closing, inverse_mass, e)
		var swing_k := 0.5 * WeaponKinematics.motor_inertia(spec, 0.0) * omega * omega
		energies[case[0]] = dissipated
		## ASSERT: the hit takes no more than the swing carried (no energy made at contact).
		assert_true(dissipated <= swing_k + 1e-9, "%s: %.1f J delivered of %.1f J carried" % [case[0], dissipated, swing_k])
	var wound := _rules.combat.reference_severity
	assert_between(energies["prepared tap"] / wound, 0.9, 1.3, "a clean prepared tap is about one reference-quality wound (%.2f)" % (energies["prepared tap"] / wound))
	assert_between(energies["centre tap"] / wound, 0.2, 0.5, "a centre tap is a light wound (%.2f)" % (energies["centre tap"] / wound))
	assert_between(energies["half charge"] / wound, 1.8, 2.3, "a clean half charge is about the catastrophic reference (%.2f)" % (energies["half charge"] / wound))
	## PERTURB: energy goes as the square of speed — the full charge is decisive
	## without any charge multiplier.
	var ratio: float = energies["full charge"] / energies["prepared tap"]
	var speed_ratio := weapon.achievable_swing_speed(1.0, 1.0) / weapon.achievable_swing_speed(0.0, 1.0)
	assert_near(ratio, speed_ratio * speed_ratio, 0.05 * speed_ratio * speed_ratio, "full / prepared = (18 / 10.5)² ≈ %.2f (measured %.2f)" % [speed_ratio * speed_ratio, ratio])
	assert_true(energies["full charge"] > StandardDuelRules.REFERENCE_STRIKE_ENERGY_J, "a clean full charge exceeds the catastrophic reference (%.1f J)" % energies["full charge"])
