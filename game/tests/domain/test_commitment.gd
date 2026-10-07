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


func test_commitment_spends_authority_not_speed() -> void:
	## PHYS-003. Commitment is allowed to govern how fast a fighter may change
	## velocity, and nothing else: what they are *asking* for is untouched.
	var definition := _rules.fighter
	var rows := [
		[CombatPhase.Id.CHARGING, 1.0],
		[CombatPhase.Id.ACTIVE_THREAT, 0.0],
		[CombatPhase.Id.ACTIVE_THREAT, 0.5],
		[CombatPhase.Id.ACTIVE_THREAT, 1.0],
		[CombatPhase.Id.OVERSWING, 1.0],
	]
	var previous := 2.0
	for row: Array in rows:
		var fighter := _fighter(row[0] as CombatPhase.Id, float(row[1]))
		var label := "%s C=%s" % [CombatPhase.label(fighter.weapon.phase), str(row[1])]
		assert_eq(CommitmentModel.translation_multiplier(fighter, definition), 1.0, "%s asks for its full speed" % label)
		var authority := CommitmentModel.move_authority(fighter, definition)
		assert_between(authority, definition.min_move_authority, 1.0, "%s authority stays in range" % label)
		assert_true(authority <= previous, "%s authority never rises as commitment does" % label)
		previous = authority
	assert_true(previous < 1.0, "a fully committed swing really did cost authority")


func test_a_committed_swing_keeps_the_stride_it_started_with() -> void:
	## The defining PHYS-003 property: becoming committed at full forward
	## speed must not brake the fighter. It only makes the stride expensive to
	## change — which the whiff-punish test below relies on.
	var definition := _rules.fighter
	var free := FighterState.new()
	free.weapon.reset(-_rules.weapon.guard_angle)
	for _i in 120:
		DuelFixture.spar(free, 0.0, 1.0, definition)
	var cruising := free.speed()
	assert_true(cruising > definition.max_speed * 0.9, "precondition: running at speed")
	var committed := _fighter(CombatPhase.Id.ACTIVE_THREAT, 1.0)
	committed.vx = free.vx
	committed.vy = free.vy
	DuelFixture.spar(committed, 0.0, 1.0, definition)
	assert_near(committed.speed(), cruising, 1e-9, "a fully committed fighter keeps the momentum they had")
	## And they cannot simply stop asking: releasing the stick barely slows them.
	var braking := _fighter(CombatPhase.Id.ACTIVE_THREAT, 1.0)
	braking.vx = free.vx
	braking.vy = free.vy
	DuelFixture.spar(braking, 0.0, 0.0, definition)
	var free_brake := FighterState.new()
	free_brake.weapon.reset(-_rules.weapon.guard_angle)
	free_brake.vx = free.vx
	free_brake.vy = free.vy
	DuelFixture.spar(free_brake, 0.0, 0.0, definition)
	assert_true(braking.speed() > free_brake.speed(), "committed braking is weaker than free braking")
	assert_true(braking.speed() < cruising, "but a committed fighter is still allowed to brake at all")


func test_turning_is_torque_against_existing_rotation() -> void:
	## PHYS-003. Falling authority must not clamp angular velocity down; it
	## reduces the torque available, so a body already rotating one way needs
	## time to arrest that rotation before it can reverse.
	var definition := _rules.fighter
	var free := FighterState.new()
	free.weapon.reset(-_rules.weapon.guard_angle)
	free.turn_rate = definition.turn_speed_max
	var committed := _fighter(CombatPhase.Id.ACTIVE_THREAT, 1.0)
	committed.turn_rate = definition.turn_speed_max
	var tracking := CommitmentModel.tracking_multiplier(committed, _opponent_behind(), definition)
	assert_true(tracking < 1.0, "precondition: a heavy swing really does cost tracking")
	## Both bodies are spinning counter-clockwise while the target sits
	## clockwise of their facing, so both are being asked to reverse.
	FacingSystem.step(free, 1.0, -1.0, 1.0, definition)
	FacingSystem.step(committed, 1.0, -1.0, tracking, definition)
	assert_true(free.turn_rate < definition.turn_speed_max, "precondition: the free body is already shedding rotation")
	assert_true(committed.turn_rate > free.turn_rate, "the committed body sheds its rotation more slowly")
	assert_true(committed.turn_rate > 0.0, "and one tick of low authority cannot reverse it")
	var reversal := 0
	while committed.turn_rate > 0.0 and reversal < 600:
		FacingSystem.step(committed, 1.0, -1.0, tracking, definition)
		reversal += 1
	assert_true(reversal > 1, "reversing a committed turn costs real time, it does not snap")
	assert_true(reversal < 600, "but the reversal does complete")


func _opponent_behind() -> FighterState:
	var opponent := FighterState.new()
	DuelFixture.place(opponent, -2.0, 0.0, 0.0)
	return opponent


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
