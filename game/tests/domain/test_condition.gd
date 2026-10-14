extends TestCase

## CONDITION: damage-driven physical capability (CONDITION-001). Damage does
## not change the laws of physics; it changes how much voluntary force, speed
## and tracking the fighter can produce within them — linearly, exactly 1 at
## full health, never below the floors, never rescaling momentum, and never
## delaying a command. There is no fatigue input (STAMINA-003).
##
## Implements: /spec/invariants.md#condition-001
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "CONDITION"
	_rules = DuelFixture.rules()


func _condition(health: float) -> ConditionState:
	return ConditionModel.compute(health, 100.0, _rules.combat, ConditionState.new())


func test_full_health_is_the_exact_identity() -> void:
	## ARRANGE + ACT
	var healthy := _condition(100.0)
	## ASSERT: bit-exact, so a healthy fighter's motors are untouched.
	assert_eq(healthy.force_scale, 1.0, "force scale is exactly 1")
	assert_eq(healthy.speed_scale, 1.0, "speed scale is exactly 1")
	assert_eq(healthy.tracking_scale, 1.0, "tracking scale is exactly 1")
	assert_eq(healthy.damage_fraction, 0.0, "and no damage is recorded")


func test_the_half_health_witness() -> void:
	## ARRANGE + ACT
	var half := _condition(50.0)
	## ASSERT: the authored laws at h = 0.5.
	assert_near(half.force_scale, 0.85, 1e-12, "force 0.70 + 0.30·0.5")
	assert_near(half.speed_scale, 0.925, 1e-12, "speed 0.85 + 0.15·0.5")
	assert_near(half.tracking_scale, 0.90, 1e-12, "tracking 0.80 + 0.20·0.5")


func test_each_scale_is_strictly_linear_in_damage() -> void:
	## ARRANGE: equal damage steps.
	var previous := _condition(100.0)
	var step_force := -1.0
	for health: float in [90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0]:
		## ACT
		var current := _condition(health)
		var delta := previous.force_scale - current.force_scale
		## ASSERT: constant decrements, and each scale moves in proportion.
		if step_force < 0.0:
			step_force = delta
		assert_near(delta, step_force, 1e-12, "an equal damage step costs the same force at %.0f health" % health)
		assert_near((previous.speed_scale - current.speed_scale) / delta, 0.15 / 0.30, 1e-9, "speed falls at half the force rate at %.0f" % health)
		assert_near((previous.tracking_scale - current.tracking_scale) / delta, 0.20 / 0.30, 1e-9, "tracking at two thirds of it at %.0f" % health)
		previous = current


func test_the_floors_are_approached_and_never_crossed() -> void:
	## ARRANGE + ACT
	var dead := _condition(0.0)
	var overkill := ConditionModel.compute(-40.0, 100.0, _rules.combat, ConditionState.new())
	var barely := _condition(0.001)
	## ASSERT
	assert_near(dead.force_scale, _rules.combat.condition_force_floor, 1e-15, "zero health is the force floor")
	assert_near(dead.speed_scale, _rules.combat.condition_speed_floor, 1e-15, "the speed floor")
	assert_near(dead.tracking_scale, _rules.combat.condition_tracking_floor, 1e-15, "the tracking floor")
	assert_eq(overkill.force_scale, dead.force_scale, "health below zero is clamped, never past the floor")
	assert_true(barely.force_scale > dead.force_scale and barely.speed_scale > dead.speed_scale and barely.tracking_scale > dead.tracking_scale, "any health left is above every floor")
	## PERTURB: a floor outside [0.5, 1] is invalid content.
	var broken := StandardDuelRules.combat_tuning()
	broken.reference_impulse = 1.0
	broken.reference_severity = 1.0
	broken.reference_thrust_severity = 1.0
	broken.reference_clash_energy = 1.0
	assert_true(broken.is_valid(), "fixture: the tuning is valid")
	broken.condition_force_floor = 0.3
	assert_false(broken.is_valid(), "a floor that could all but disable a fighter is refused")


## The injury does not touch momentum: on the tick after a wound the body and
## the blade still carry their speed, and only the actuator's authority to
## change it has shrunk.
func test_existing_momentum_is_never_rescaled() -> void:
	## ARRANGE: a fighter at full stride asking for full stride, healthy and
	## wounded.
	var healthy := FighterState.new()
	var wounded := FighterState.new()
	var definition := _rules.combatant(0).fighter
	for fighter: FighterState in [healthy, wounded]:
		DuelFixture.place(fighter, 0.0, 0.0, 0.0)
		fighter.vx = definition.max_speed
	var condition := _condition(20.0)
	## ACT
	MovementSystem.step(healthy, 0.0, 1.0, 0, definition)
	MovementSystem.step(wounded, 0.0, 1.0, 0, definition, condition)
	## ASSERT: the healthy fighter holds stride; the wounded one is asked for a
	## lower top speed and brakes toward it at its reduced authority — it does
	## not snap to it.
	var target := definition.max_speed * condition.speed_scale
	assert_near(healthy.vx, definition.max_speed, 1e-9, "fixture: the healthy stride holds")
	assert_true(wounded.vx > target, "the wounded body keeps its momentum, above the lower target (%.3f > %.3f m/s)" % [wounded.vx, target])
	var expected := definition.max_speed - definition.brake_accel() * condition.force_scale * SimulationTimebase.TICK_SECONDS
	assert_near(wounded.vx, expected, 1e-9, "losing exactly one tick of its reduced braking")


## Force on every motor, speed on every target, tracking on the heading cap.
func test_a_wounded_fighter_drives_every_motor_weaker() -> void:
	## ARRANGE
	var definition := _rules.combatant(0).fighter
	var condition := _condition(25.0)
	## ACT + ASSERT: footwork, one tick and then to top speed.
	var walk_healthy := FighterState.new()
	var walk_wounded := FighterState.new()
	_spar(walk_healthy, definition, null, 0)
	_spar(walk_wounded, definition, condition, 0)
	assert_near(walk_wounded.speed() / walk_healthy.speed(), condition.force_scale, 1e-9, "footwork accelerates at the force scale")
	for tick in 240:
		_spar(walk_healthy, definition, null, tick + 1)
		_spar(walk_wounded, definition, condition, tick + 1)
	assert_near(walk_wounded.speed() / walk_healthy.speed(), condition.speed_scale, 1e-6, "and tops out at the speed scale")
	## Heading: a target a quarter turn away, so the rate cap binds.
	var peak_healthy := _peak_turn_rate(definition, null)
	var peak_wounded := _peak_turn_rate(definition, condition)
	assert_near(peak_healthy, definition.turn_speed_max, 1e-9, "fixture: the healthy heading reaches its cap")
	assert_near(peak_wounded, definition.turn_speed_max * condition.tracking_scale, 1e-9, "the wounded heading rate is capped at the tracking scale")
	## Weapon: a full charge released from rest.
	var swing_healthy := _swing(null)
	var swing_wounded := _swing(condition)
	assert_near(swing_wounded[0] / swing_healthy[0], condition.force_scale, 1e-9, "the swing accelerates at the force scale")
	assert_near(swing_wounded[1] / swing_healthy[1], condition.speed_scale, 1e-6, "and its peak is the speed scale")


## One tick of forward footwork down the fighter's heading (as `DuelFixture.spar`),
## under `condition`.
func _spar(fighter: FighterState, definition: FighterDefinition, condition: ConditionState, tick: int) -> void:
	MovementSystem.step(fighter, 0.0, 1.0, tick, definition, condition)


## The fastest the heading turns toward a target a quarter turn away.
func _peak_turn_rate(definition: FighterDefinition, condition: ConditionState) -> float:
	var fighter := FighterState.new()
	var peak := 0.0
	for _tick in 30:
		FacingSystem.step(fighter, 0.0, -4.0, 1.0, definition, condition)
		peak = maxf(peak, absf(fighter.turn_rate))
	return peak


## [first tick's speed, peak speed] of a full-charge swing from the load.
func _swing(condition: ConditionState) -> PackedFloat64Array:
	var spec := _rules.combatant(0)
	var fighter := FighterState.new()
	fighter.health = spec.fighter.max_health
	var w := fighter.weapon
	w.reset(-spec.weapon.guard_angle - spec.weapon.windback_span())
	w.phase = CombatPhase.Id.LAUNCH
	w.swing_dir = 1.0
	w.swing_charge = 1.0
	w.launch_preparation = 1.0
	w.swing_start = w.angle
	w.swing_end = spec.weapon.guard_limit
	var events: Array[DuelEvent] = []
	WeaponSystem.step(fighter, _rules, 0, events, condition)
	var first := absf(w.speed)
	var peak := first
	for tick in 120:
		if not CombatPhase.is_swinging(w.phase):
			break
		WeaponSystem.step(fighter, _rules, tick + 1, events, condition)
		peak = maxf(peak, absf(w.speed))
	return PackedFloat64Array([first, peak])


## The whole duel: the same commands from a healthy and a badly wounded
## fighter. The wounded one is weaker in everything — and every command still
## takes effect on the same tick.
func test_every_command_still_lands_on_its_tick() -> void:
	## ARRANGE
	var healthy := _scripted(100.0)
	var wounded := _scripted(20.0)
	## ASSERT: same ticks for every input edge.
	for type: StringName in [DuelEventTypes.ATTACK_STARTED, DuelEventTypes.CHARGE_STARTED, DuelEventTypes.ATTACK_RELEASED, DuelEventTypes.BURST_STARTED]:
		var a := healthy.first(type)
		var b := wounded.first(type)
		assert_true(a != null and b != null, "fixture: both fighters produced %s" % type)
		if a != null and b != null:
			assert_eq(b.tick, a.tick, "%s lands on the same tick wounded" % type)
	assert_true(healthy.is_sound() and wounded.is_sound(), "both duels stay legal")


func _scripted(health: float) -> SimRunner:
	var runner := SimRunner.create(_rules, 4)
	runner.skip_intro()
	runner.state.fighter(0).health = health
	for _i in 12:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, -1.0), PlayerCommand.idle(runner.state.tick))
	## A charged cut: press, hold past the tap threshold, release.
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true), PlayerCommand.idle(runner.state.tick))
	for _i in 30:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0), PlayerCommand.idle(runner.state.tick))
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(runner.state.tick))
	## A back dash: two taps through neutral.
	for burst: float in [-1.0, 0.0, -1.0]:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, burst), PlayerCommand.idle(runner.state.tick))
	runner.idle(20)
	return runner


## STAMINA-003: there is no fatigue resource. Condition is the one capability
## reading, and nothing in authoritative state could carry a hidden second one
## for a motor, the hash or the CPU to read.
func test_no_fatigue_resource_exists() -> void:
	## ARRANGE + ACT: a fresh duel's fighter and its rules.
	var state := DuelFixture.state(_rules)
	var fighter := state.fighter(0)
	assert_true(fighter.health > 0.0, "fixture: a live fighter")
	## ASSERT
	for name: String in ["stamina", "fatigue", "exertion"]:
		assert_false(name in fighter, "the fighter carries no %s" % name)
		assert_false(("base_" + name) in _rules.combatant(0).fighter, "and no fighter defines a %s pool" % name)
	assert_false("contact_shock" in FighterTickScratch.new(), "no tick ledger accrues one either")

## Condition never touches the body's or the weapon's physical profile.
func test_condition_never_changes_mass_inertia_or_geometry() -> void:
	## ARRANGE
	var spec := _rules.combatant(0)
	var before := spec.fingerprint()
	var inertia := WeaponKinematics.motor_inertia(spec, 0.3)
	## ACT: a wounded fighter fights a few hundred ticks.
	var runner := SimRunner.create(_rules, 11)
	runner.skip_intro()
	runner.state.fighter(0).health = 15.0
	runner.run(Pilot.wander(11, 1), Pilot.wander(11, 2), 300)
	## ASSERT
	assert_eq(spec.fingerprint(), before, "the resolved content is untouched")
	assert_eq(WeaponKinematics.motor_inertia(spec, 0.3), inertia, "the weapon's inertia is the same")
	assert_true(runner.is_sound(), "and the wounded duel is legal (%s)" % runner.violation_summary())


## FighterCondition: the coarse band a damage total reads as (moved from the
## retired stamina suite, STAMINA-003).
func test_condition_full_health_is_healthy() -> void:
	assert_eq(FighterCondition.classify(100.0, 100.0), FighterCondition.Id.HEALTHY, "full health → HEALTHY")


func test_condition_zero_health_is_critical() -> void:
	assert_eq(FighterCondition.classify(0.0, 100.0), FighterCondition.Id.CRITICAL, "zero health → CRITICAL")


func test_condition_classification_is_monotone() -> void:
	var previous := FighterCondition.classify(100.0, 100.0)
	for i in range(99, -1, -1):
		var health := float(i)
		var current := FighterCondition.classify(health, 100.0)
		assert_true(current >= previous, "condition non-decreasing severity at health %s" % str(health))
		previous = current


func test_condition_thresholds() -> void:
	assert_eq(FighterCondition.classify(76.0, 100.0), FighterCondition.Id.HEALTHY, "76% → HEALTHY")
	assert_eq(FighterCondition.classify(75.0, 100.0), FighterCondition.Id.HURT, "75% → HURT")
	assert_eq(FighterCondition.classify(51.0, 100.0), FighterCondition.Id.HURT, "51% → HURT")
	assert_eq(FighterCondition.classify(50.0, 100.0), FighterCondition.Id.WOUNDED, "50% → WOUNDED")
	assert_eq(FighterCondition.classify(26.0, 100.0), FighterCondition.Id.WOUNDED, "26% → WOUNDED")
	assert_eq(FighterCondition.classify(25.0, 100.0), FighterCondition.Id.CRITICAL, "25% → CRITICAL")
	assert_eq(FighterCondition.classify(1.0, 100.0), FighterCondition.Id.CRITICAL, "1% → CRITICAL")


func test_condition_degenerate_max_health() -> void:
	assert_eq(FighterCondition.classify(0.0, 0.0), FighterCondition.Id.CRITICAL, "zero max_health → CRITICAL")


func test_condition_labels() -> void:
	assert_eq(FighterCondition.label(FighterCondition.Id.HEALTHY), "HEALTHY", "label HEALTHY")
	assert_eq(FighterCondition.label(FighterCondition.Id.HURT), "HURT", "label HURT")
	assert_eq(FighterCondition.label(FighterCondition.Id.WOUNDED), "WOUNDED", "label WOUNDED")
	assert_eq(FighterCondition.label(FighterCondition.Id.CRITICAL), "CRITICAL", "label CRITICAL")
