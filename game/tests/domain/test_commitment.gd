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
	fighter.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	DuelFixture.commit(fighter, phase, charge, _rules.combatant(0).weapon)
	return fighter


## The same, with the blade at the speed its attack actually reaches: the
## directional commitment reads momentum, so a stationary blade commits
## nothing (DIRECTIONAL-COMMIT-001).
func _moving(phase: CombatPhase.Id, charge: float) -> FighterState:
	var fighter := _fighter(phase, charge)
	fighter.weapon.launch_preparation = 1.0
	fighter.weapon.speed = _rules.combatant(0).weapon.achievable_swing_speed(charge, 1.0) if CombatPhase.is_striking(phase) else 0.0
	return fighter


## The turn authority the duel gives ighter this tick, healthy.
func _authority(fighter: FighterState) -> float:
	return CommitmentModel.turn_torque_share(fighter, _rules.combatant(0), ConditionState.new(), _rules.combat)


func test_commitment_rises_with_charge() -> void:
	var tap := _fighter(CombatPhase.Id.ACTIVE_THREAT, 0.0).weapon.commitment
	var medium := _fighter(CombatPhase.Id.ACTIVE_THREAT, 0.5).weapon.commitment
	var heavy := _fighter(CombatPhase.Id.ACTIVE_THREAT, 1.0).weapon.commitment
	assert_true(tap > 0.0, "even a tap commits")
	assert_true(tap < medium and medium < heavy, "K rises with charge")
	assert_near(heavy, 1.0, 1e-12, "full charge peaks at K = 1")
	assert_eq(_fighter(CombatPhase.Id.NEUTRAL, 0.0).weapon.commitment, 0.0, "neutral is uncommitted")


## v36: one continuous, mirrored commitment. The same physical swing state
## commits the same whichever striking phase label it carries (no step at a
## phase boundary); a charge hands into its launch without a jump; a mirrored
## state commits identically; and a blade that has barely travelled and is
## standing still is easier to redirect than one well into a fast cut.
func test_commitment_is_one_continuous_mirrored_reading_of_the_swing() -> void:
	var weapon := WeaponState.new()
	weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	weapon.swing_charge = 0.6
	weapon.charge = 0.6
	weapon.swing_dir = 1.0
	weapon.swing_start = -1.2
	weapon.swing_end = 1.2
	weapon.angle = -0.9
	weapon.speed = 6.0
	var values := PackedFloat64Array()
	for phase: CombatPhase.Id in [CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE]:
		weapon.phase = phase
		values.append(CommitmentModel.commitment(weapon, _rules.combatant(0).weapon))
	for index in range(1, values.size()):
		assert_eq(values[index], values[0], "phase %d: the same swing state commits the same (no phase step)" % index)
	var mirrored := WeaponState.new()
	mirrored.reset(_rules.combatant(0).weapon.guard_angle)
	mirrored.phase = CombatPhase.Id.ACTIVE_THREAT
	mirrored.swing_charge = 0.6
	mirrored.swing_dir = -1.0
	mirrored.swing_start = 1.2
	mirrored.swing_end = -1.2
	mirrored.angle = 0.9
	mirrored.speed = -6.0
	assert_eq(CommitmentModel.commitment(mirrored, _rules.combatant(0).weapon), values[0], "a mirrored swing commits identically")
	weapon.phase = CombatPhase.Id.CHARGING
	var charging := CommitmentModel.commitment(weapon, _rules.combatant(0).weapon)
	weapon.phase = CombatPhase.Id.LAUNCH
	weapon.angle = weapon.swing_start
	weapon.speed = 0.0
	assert_near(CommitmentModel.commitment(weapon, _rules.combatant(0).weapon), charging, 1e-12, "a charge hands into its launch without a jump")
	var stopped := CommitmentModel.commitment(weapon, _rules.combatant(0).weapon)
	weapon.angle = 0.2
	weapon.speed = _rules.combatant(0).weapon.swing_speed_full
	var driving := CommitmentModel.commitment(weapon, _rules.combatant(0).weapon)
	assert_true(stopped < driving, "a blade standing at its start is easier to redirect than one driving through the cut (%.3f < %.3f)" % [stopped, driving])


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
	var weapon := rig.fighter.weapon
	assert_true(absf(weapon.speed) <= _rules.combatant(0).weapon.control_speed, "recovery ended with the blade under control")
	var at_exit := _authority(rig.fighter)
	assert_true(at_exit > _rules.combat.commit_turn_torque_floor and at_exit <= 1.0, "exit authority stays inside the turn share (%.6f)" % at_exit)
	## Full authority is a stopped blade, not the recovery-exit tick. The
	## return may still be moving inside control speed, and that speed is
	## redirect debt (DIRECTIONAL-COMMIT-001). Zeroing it is the documented
	## terminal condition; the exit value itself is not a golden number.
	var leftover := weapon.speed
	weapon.speed = 0.0
	weapon.motor_torque = 0.0
	assert_eq(_authority(rig.fighter), 1.0, "a stopped blade has full tracking")
	if at_exit < 1.0:
		assert_true(absf(leftover) > 0.0, "any shortfall at exit is leftover blade speed")


## Ticks a combat heading needs to come within `tolerance` of a target bearing
## `offset` radians away, at a fixed turn authority (HEADING-001).
func _ticks_to_acquire(authority: float, offset: float, tolerance: float = deg_to_rad(2.0)) -> int:
	var fighter := FighterState.new()
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	for tick in 600:
		if absf(SimMath.wrap_angle(offset - fighter.facing)) <= tolerance:
			return tick
		FacingSystem.step(fighter, cos(offset) * 4.0, sin(offset) * 4.0, authority, _rules.combatant(0).fighter)
	return 600


## The combat heading catches the target bearing at the authority commitment
## leaves: quickly in neutral, slower through a tap at speed, far slower
## through a full-charge cut at speed — so a side-step can out-angle a
## committed attack while a light one keeps tracking (HEADING-001,
## DIRECTIONAL-COMMIT-001). Pure geometry: no angle bonus.
func test_commitment_slows_the_heading_catching_its_target() -> void:
	var neutral := _moving(CombatPhase.Id.NEUTRAL, 0.0)
	var light := _moving(CombatPhase.Id.ACTIVE_THREAT, 0.0)
	var heavy := _moving(CombatPhase.Id.ACTIVE_THREAT, 1.0)
	var free := _authority(neutral)
	var light_authority := _authority(light)
	var heavy_authority := _authority(heavy)
	assert_eq(free, 1.0, "neutral keeps full turning authority")
	assert_true(heavy_authority < light_authority and light_authority < free, "a full-charge cut tracks worse than a tap, which tracks worse than neutral (%.2f < %.2f < 1)" % [heavy_authority, light_authority])
	var side_step := deg_to_rad(25.0)
	var neutral_ticks := _ticks_to_acquire(free, side_step)
	var heavy_ticks := _ticks_to_acquire(heavy_authority, side_step)
	assert_true(heavy_ticks > neutral_ticks, "a 25° side-step stays outside a committed heading longer (%d vs %d ticks)" % [heavy_ticks, neutral_ticks])


## A forward dash keeps its launch heading through the drive, then hands
## authority back continuously through its recovery (MOVE-002, HEADING-001).
func test_a_forward_dash_holds_its_heading_then_recovers_tracking_smoothly() -> void:
	var fighter := _fighter(CombatPhase.Id.NEUTRAL, 0.0)
	assert_eq(_authority(fighter), 1.0, "fixture: free before the dash")
	fighter.gesture.mode = MovementGestureState.Mode.BURST
	fighter.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	fighter.gesture.burst_ticks_remaining = 6
	assert_eq(_authority(fighter), 0.0, "no turning through the committed drive")
	fighter.gesture.end_burst_into_recovery(10)
	var previous := 0.0
	var smooth := true
	while fighter.gesture.is_recovering():
		var authority := _authority(fighter)
		smooth = smooth and authority >= previous and authority - previous <= 0.2 + 1e-9
		previous = authority
		fighter.gesture.recovery_ticks_remaining -= 1
		if fighter.gesture.recovery_ticks_remaining <= 0:
			fighter.gesture.mode = MovementGestureState.Mode.NORMAL
	assert_true(smooth, "authority climbs back in small steps, never a snap")
	## This fighter is planted: no forward speed, no blade speed. Gesture
	## recovery therefore ends at full turn authority. A body that is still
	## moving keeps its forward redirect debt (DIRECTIONAL-COMMIT-001); that
	## debt is not a weapon-settling delay and is not this assertion.
	assert_eq(_authority(fighter), 1.0, "and is whole again after recovery")


func test_commitment_spends_authority_not_speed() -> void:
	## PHYS-003. Commitment is allowed to govern how fast a fighter may change
	## velocity, and nothing else: what they are *asking* for is untouched.
	var definition := _rules.combatant(0).fighter
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
	var definition := _rules.combatant(0).fighter
	var free := FighterState.new()
	free.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
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
	free_brake.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	free_brake.vx = free.vx
	free_brake.vy = free.vy
	DuelFixture.spar(free_brake, 0.0, 0.0, definition)
	assert_true(braking.speed() > free_brake.speed(), "committed braking is weaker than free braking")
	assert_true(braking.speed() < cruising, "but a committed fighter is still allowed to brake at all")


func test_turning_is_torque_against_existing_rotation() -> void:
	## PHYS-003. Falling authority must not clamp angular velocity down; it
	## reduces the torque available, so a body already rotating one way needs
	## time to arrest that rotation before it can reverse.
	var definition := _rules.combatant(0).fighter
	var free := FighterState.new()
	free.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	free.turn_rate = definition.turn_speed_max
	var committed := _moving(CombatPhase.Id.ACTIVE_THREAT, 1.0)
	committed.turn_rate = definition.turn_speed_max
	var tracking := _authority(committed)
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


## RECOVERY-001: recovery carries the commitment the blade had and decays it
## with the gate; facing error adds no recovery time of its own.
func test_recovery_carries_the_commitment_it_entered_with() -> void:
	var calm := _fighter(CombatPhase.Id.OVERSWING, 0.5)
	var entered := calm.weapon.commitment
	WeaponSystem.begin_recovery(calm, _rules)
	var turned := _fighter(CombatPhase.Id.OVERSWING, 0.5)
	turned.facing = PI * 0.75
	WeaponSystem.begin_recovery(turned, _rules)
	assert_true(entered > 0.0, "fixture: the overswing was committed")
	assert_eq(calm.weapon.recovery_commitment, entered, "recovery remembers the commitment it entered with")
	assert_eq(turned.weapon.recovery_ticks, calm.weapon.recovery_ticks, "facing error adds no recovery ticks")
	assert_eq(calm.weapon.recovery_ticks, _rules.combat.recovery_min_ticks, "the floor is the universal one")
