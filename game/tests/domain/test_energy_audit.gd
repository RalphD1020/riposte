extends TestCase

## ENERGY-AUDIT: the weapon motor's work against the held sword's kinetic
## energy `K = ½·M_θ(θ)·θ̇²`, and what a clean hit actually delivers, on the
## reference duelist. The coordinate obeys the generalized equation
## `M_θ·θ̈ + ½·M_θ′·θ̇² = τ` (UNIFIED-MASS-001): each tick a torque-free step
## that conserves `K` (`WeaponSystem.inertial_speed`), then the motor's torque
## through the inertia where that step left the blade
## (`WeaponSystem.kick_inertia`), so in free flight `K` changes by the motor's
## work up to the 60 Hz step's own error terms. Earlier rules left the
## configuration term out and this audit pinned that gap. It asserts no damage
## rule.
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
	var dt := SimulationTimebase.TICK_SECONDS
	var slope := _steepest_inertia(spec)
	var out := {"dk": 0.0, "work": 0.0, "work_abs": 0.0, "residual_abs": 0.0, "residual_signed": 0.0, "worst_excess": -INF, "peak_k": 0.0, "ticks": 0}
	for _i in 120:
		var theta0 := w.angle
		var omega0 := w.speed
		var m0 := WeaponKinematics.motor_inertia(spec, theta0)
		var carried := WeaponSystem.inertial_speed(spec, theta0, omega0, BladePose.new())
		var phase0 := w.phase
		rig.step()
		var m1 := WeaponKinematics.motor_inertia(spec, w.angle)
		var swinging := CombatPhase.is_swinging(phase0) or phase0 == CombatPhase.Id.OVERSWING
		if swinging and absf(w.angle) < limit_inner and absf(theta0) < limit_inner:
			var k0 := 0.5 * m0 * omega0 * omega0
			var k1 := 0.5 * m1 * w.speed * w.speed
			var work := w.motor_torque * 0.5 * (carried + w.speed) * dt
			var residual := absf(k1 - k0 - work)
			## The step's own error terms: the torque-free step's (under 1 % of the energy, RULES), and the drift-kick
			## splitting's — the kick moves the end of the tick by Δθ̇·dt from where the drift sampled the inertia, which
			## changes ½·M_θ·θ̇² there by at most ½·max|M_θ′|·|Δθ̇|·dt·θ̇².
			var kick := absf(w.speed - carried)
			var bound := 0.01 * maxf(k0, k1) + 0.5 * slope * kick * dt * maxf(carried * carried, w.speed * w.speed)
			out["dk"] += k1 - k0
			out["work"] += work
			out["work_abs"] += absf(work)
			out["residual_abs"] += residual
			out["residual_signed"] += k1 - k0 - work
			out["worst_excess"] = maxf(out["worst_excess"], residual - bound)
			out["ticks"] += 1
			out["peak_k"] = maxf(out["peak_k"], k1)
		if w.phase == CombatPhase.Id.NEUTRAL and _i > 5:
			break
	return out


## The steepest |dM_θ/dθ| along the track, from half-degree samples (a slight underestimate between samples is covered by
## the step's own 1 % allowance).
func _steepest_inertia(spec: CombatantPhysicsSpec) -> float:
	var step := deg_to_rad(0.5)
	var steepest := 0.0
	var previous := WeaponKinematics.motor_inertia(spec, 0.0)
	for i in range(1, 271):
		var here := WeaponKinematics.motor_inertia(spec, step * float(i))
		steepest = maxf(steepest, absf(here - previous) / step)
		previous = here
	return steepest


func test_the_motor_ledger_is_the_work_and_the_configuration_term_is_modelled() -> void:
	## ARRANGE: the inertia really changes along the track (the fixture the term needs).
	var spec := _rules.combatant(0)
	var m45 := WeaponKinematics.motor_inertia(spec, PI * 0.25)
	var m0 := WeaponKinematics.motor_inertia(spec, 0.0)
	assert_true(absf(m45 - m0) > 0.2, "fixture: M_θ varies along the track (%.3f at 45° vs %.3f at 0°)" % [m45, m0])
	for case: Array in [["tap from Ready", -45.0, false], ["tap from the centre", 0.0, false], ["full charge", -45.0, true]]:
		## ACT
		var ledger := _ledger(float(case[1]), bool(case[2]))
		## ASSERT: in free flight every tick's ΔK is the motor's work (its torque over the speeds it acted between) up to
		## the step's own error terms — no torque-free energy change, no hidden impulse, no speed assignment. Soft-limit and
		## contact ticks are outside this ledger (excluded above) and are attributed separately. The residual is the
		## drift-kick splitting's first-order error: it falls with the tick (8.7 / 3.3 / 1.5 / 0.3 % of the work at 60 / 120 /
		## 240 / 960 Hz on a constant-torque drive); the signed and absolute totals are reported with the gate.
		assert_true(ledger["ticks"] > 4, "fixture: %s has free-flight ticks to audit (%d)" % [case[0], ledger["ticks"]])
		assert_true(ledger["worst_excess"] <= 0.0, "%s: every tick reconciles within the step's error terms (worst excess %.3f J; signed total %+.2f J, absolute %.2f J of %.1f J work)" % [case[0], ledger["worst_excess"], ledger["residual_signed"], ledger["residual_abs"], ledger["work_abs"]])
		assert_true(ledger["residual_abs"] < 0.25 * ledger["work_abs"], "%s: the unreconciled energy is a small share of the work done (%.1f of %.1f J)" % [case[0], ledger["residual_abs"], ledger["work_abs"]])


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
