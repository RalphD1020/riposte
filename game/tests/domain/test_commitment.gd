extends TestCase

## COMMIT: power creates positional debt (COMBAT §20–§21, §56, §62).
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "COMMIT"
	_rules = DuelFixture.rules()


func _fighter(phase: CombatPhase.Id, charge: float) -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(-_rules.weapon.guard_angle)
	DuelFixture.commit(fighter, phase, charge, _rules.weapon)
	return fighter


func test_commitment_rises_with_charge() -> void:
	var tap := _fighter(CombatPhase.Id.ACTIVE_THREAT, 0.0).weapon.commitment
	var medium := _fighter(CombatPhase.Id.ACTIVE_THREAT, 0.5).weapon.commitment
	var heavy := _fighter(CombatPhase.Id.ACTIVE_THREAT, 1.0).weapon.commitment
	assert_true(tap > 0.0, "even a tap commits")
	assert_true(tap < medium and medium < heavy, "K rises with charge")
	assert_near(heavy, 1.0, 1e-12, "full charge peaks at K = 1")
	assert_eq(_fighter(CombatPhase.Id.NEUTRAL, 0.0).weapon.commitment, 0.0, "neutral is uncommitted")


func test_commitment_rises_through_a_swing() -> void:
	var rig := WeaponRig.create(_rules)
	rig.attack(70)
	var previous := -1.0
	var dropped := false
	while CombatPhase.is_striking(rig.fighter.weapon.phase):
		dropped = dropped or rig.fighter.weapon.commitment < previous
		previous = rig.fighter.weapon.commitment
		rig.step()
	assert_false(dropped, "K never falls while the blade is striking")
	assert_near(previous, 1.0, 1e-12, "heavy swing ends fully committed")


func test_recovery_restores_control_gradually() -> void:
	var rig := WeaponRig.create(_rules)
	rig.attack(70)
	assert_true(rig.step_until_phase(CombatPhase.Id.RECOVERY), "reached recovery")
	var previous := rig.fighter.weapon.commitment
	var rose := false
	while rig.fighter.weapon.phase == CombatPhase.Id.RECOVERY:
		rig.step()
		rose = rose or rig.fighter.weapon.commitment > previous
		previous = rig.fighter.weapon.commitment
	assert_false(rose, "K only falls during recovery")
	assert_eq(rig.fighter.weapon.commitment, 0.0, "back to uncommitted")
	assert_eq(CommitmentModel.tracking_multiplier(rig.fighter, rig.opponent, _rules.fighter), 1.0, "full tracking restored")


func test_footwork_matches_the_movement_table() -> void:
	var definition := _rules.fighter
	var rows := [
		[CombatPhase.Id.CHARGING, 1.0, 0.9, 1.0, 0.8, 0.9],
		[CombatPhase.Id.ACTIVE_THREAT, 0.0, 0.8, 0.9, 0.6, 0.75],
		[CombatPhase.Id.ACTIVE_THREAT, 0.5, 0.7, 0.85, 0.45, 0.65],
		[CombatPhase.Id.ACTIVE_THREAT, 1.0, 0.6, 0.8, 0.3, 0.5],
		[CombatPhase.Id.OVERSWING, 1.0, 0.6, 0.8, 0.3, 0.5],
	]
	for row: Array in rows:
		var fighter := _fighter(row[0] as CombatPhase.Id, float(row[1]))
		var label := "%s C=%s" % [CombatPhase.label(fighter.weapon.phase), str(row[1])]
		assert_between(CommitmentModel.translation_multiplier(fighter, definition), float(row[2]), float(row[3]), "%s translation" % label)
		assert_between(CommitmentModel.accel_multiplier(fighter, definition), float(row[4]), float(row[5]), "%s acceleration" % label)


func test_recovery_is_computed_from_what_happened() -> void:
	var calm := _fighter(CombatPhase.Id.OVERSWING, 0.5)
	var opponent := FighterState.new()
	DuelFixture.place(opponent, 2.0, 0.0, PI)
	WeaponSystem.begin_recovery(calm, opponent, _rules, 0.0)
	var displaced := _fighter(CombatPhase.Id.OVERSWING, 0.5)
	WeaponSystem.begin_recovery(displaced, opponent, _rules, 8.0)
	var turned := _fighter(CombatPhase.Id.OVERSWING, 0.5)
	turned.facing = PI * 0.75
	WeaponSystem.begin_recovery(turned, opponent, _rules, 0.0)
	assert_true(displaced.weapon.recovery_ticks > calm.weapon.recovery_ticks, "weapon displacement lengthens recovery")
	assert_true(turned.weapon.recovery_ticks > calm.weapon.recovery_ticks, "facing error lengthens recovery")
	assert_true(calm.weapon.recovery_ticks <= _rules.weapon.recovery_max_ticks, "bounded by the cap")
