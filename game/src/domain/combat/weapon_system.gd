class_name WeaponSystem
extends RefCounted

## The one-button weapon language and the sword motor
## (COMBAT §12–§22, §41, §56, §64).
##
## Tap (release before the threshold) launches a 0% charge 90° cut. Holding
## past the threshold charges and physically retracts the blade; release
## launches from the actual retracted angle with arc 90° + 90° × C. Swing
## direction comes from which side of the facing the blade is on — never a
## combo index. The motor accelerates toward the swing, brakes into an
## overswing, and the sword then rests wherever it stopped.
##
## Implements: /spec/invariants.md#combat-001
## See also: /docs/concepts/combat.md

## Swing progress (0 → 1 along the arc) at which each active phase begins.
const PROGRESS_EARLY := 0.15
const PROGRESS_THREAT := 0.4
const PROGRESS_LATE := 0.8
## Bind holds the blades still quickly.
const BIND_DAMPING_SCALE := 4.0


static func can_start_attack(fighter: FighterState, weapon: WeaponDefinition) -> bool:
	return (
		fighter.weapon.phase == CombatPhase.Id.NEUTRAL
		and absf(fighter.weapon.speed) <= weapon.control_speed
		and fighter.press_tick < 0
	)


## Right side (angle <= 0) sweeps counter-clockwise; left side sweeps clockwise.
static func swing_direction(angle: float) -> float:
	return 1.0 if angle <= 0.0 else -1.0


## Consume one tick of attack edges. Edge order follows the held state: a
## held button releases before it can press again; a free button presses
## before it can release (a tap inside one tick). A press while already held
## and a release while free are stale duplicates and are ignored.
static func apply_input(fighter: FighterState, command: PlayerCommand, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	if fighter.weapon.phase == CombatPhase.Id.DEAD:
		fighter.clear_attack_input()
		return
	if command.attack_cancel:
		cancel(fighter, rules, tick, events)
		return
	if fighter.attack_held:
		if command.attack_released:
			_on_release(fighter, rules, tick, events)
			if command.attack_pressed:
				_on_press(fighter, rules, tick, events)
	elif command.attack_pressed:
		_on_press(fighter, rules, tick, events)
		if command.attack_released:
			_on_release(fighter, rules, tick, events)


## Input interruption (focus loss, touch cancel): a charge is dropped into a
## short recovery instead of producing an accidental attack (UX §62).
static func cancel(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := fighter.weapon
	var had_attack := fighter.press_tick >= 0 or fighter.buffered_press_tick >= 0 or weapon.phase == CombatPhase.Id.CHARGING
	fighter.clear_attack_input()
	if weapon.phase == CombatPhase.Id.CHARGING:
		weapon.charge = 0.0
		enter_recovery(weapon, rules.weapon.recovery_base_ticks)
	if had_attack:
		events.append(DuelEvent.create(DuelEventTypes.ATTACK_CANCELED, tick, fighter.slot))


## Advance the weapon one tick: buffered press, tap/charge threshold, motor,
## guard limit, phase progression, and commitment.
static func step(fighter: FighterState, opponent: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := fighter.weapon
	var definition := rules.weapon
	weapon.phase_ticks += 1
	_promote_buffer(fighter, rules, tick, events)
	if (
		fighter.press_tick >= 0
		and fighter.attack_held
		and weapon.phase == CombatPhase.Id.NEUTRAL
		and tick - fighter.press_tick >= definition.tap_threshold_ticks
	):
		weapon.set_phase(CombatPhase.Id.CHARGING)
		weapon.charge = 0.0
		events.append(DuelEvent.create(DuelEventTypes.CHARGE_STARTED, tick, fighter.slot, DuelEvent.NONE, {DuelEventKeys.DIRECTION: weapon.swing_dir}))
	if weapon.phase == CombatPhase.Id.CHARGING:
		var charged_ticks := tick - fighter.press_tick - definition.tap_threshold_ticks
		weapon.charge = SimMath.clamp01(float(charged_ticks) / float(definition.charge_ticks))
	_drive_motor(weapon, definition)
	_advance_phase(fighter, opponent, rules, tick, events)
	weapon.commitment = CommitmentModel.commitment(weapon, definition)


## Interrupt the weapon: stagger after a strong body hit (COMBAT §55).
static func stagger(fighter: FighterState, ticks: int) -> void:
	fighter.clear_attack_input()
	fighter.weapon.charge = 0.0
	fighter.weapon.set_phase(CombatPhase.Id.STAGGER)
	fighter.stagger_left = maxi(ticks, 1)


static func kill(fighter: FighterState) -> void:
	fighter.clear_attack_input()
	fighter.weapon.charge = 0.0
	fighter.weapon.set_phase(CombatPhase.Id.DEAD)
	fighter.stagger_left = 0


## End a swing early (deflection, bind loss, clean body hit) into recovery.
## Recovery is computed from what actually happened (COMBAT §56–§57).
static func begin_recovery(fighter: FighterState, opponent: FighterState, rules: DuelRules, displacement_speed: float) -> void:
	var weapon := fighter.weapon
	var definition := rules.weapon
	var overswing := maxf(0.0, (weapon.angle - weapon.swing_end) * weapon.swing_dir)
	var facing_error := absf(DuelGeometry.facing_error(fighter, opponent))
	var ticks := (
		float(definition.recovery_base_ticks)
		+ definition.recovery_commit_ticks * weapon.commitment
		+ definition.recovery_overswing_ticks_per_rad * overswing
		+ definition.recovery_displacement_ticks_per_speed * displacement_speed
		+ definition.recovery_facing_ticks_per_rad * facing_error
		+ definition.recovery_balance_ticks * (1.0 - fighter.stability)
	)
	weapon.recovery_commitment = weapon.commitment
	enter_recovery(weapon, clampi(roundi(ticks), 1, definition.recovery_max_ticks))


## Fixed-length recovery (canceled charge, lost bind).
static func enter_recovery(weapon: WeaponState, ticks: int) -> void:
	weapon.recovery_ticks = maxi(ticks, 1)
	weapon.recovery_left = weapon.recovery_ticks
	weapon.set_phase(CombatPhase.Id.RECOVERY)


static func _on_press(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	fighter.attack_held = true
	if can_start_attack(fighter, rules.weapon):
		_begin_press(fighter, tick, events)
	else:
		fighter.buffered_press_tick = tick
		fighter.buffered_release = false


static func _on_release(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	fighter.attack_held = false
	if fighter.press_tick >= 0:
		var weapon := fighter.weapon
		if weapon.phase == CombatPhase.Id.CHARGING:
			_launch(fighter, rules, weapon.charge, tick, events)
		elif weapon.phase == CombatPhase.Id.NEUTRAL:
			_launch(fighter, rules, 0.0, tick, events)
		fighter.press_tick = -1
	elif fighter.buffered_press_tick >= 0:
		fighter.buffered_release = true


static func _begin_press(fighter: FighterState, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := fighter.weapon
	fighter.press_tick = tick
	fighter.buffered_press_tick = -1
	weapon.swing_dir = swing_direction(weapon.angle)
	weapon.windup_base = weapon.angle
	events.append(DuelEvent.create(DuelEventTypes.ATTACK_STARTED, tick, fighter.slot, DuelEvent.NONE, {DuelEventKeys.DIRECTION: weapon.swing_dir}))


## Promote a press made shortly before the weapon became controllable.
static func _promote_buffer(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	if fighter.buffered_press_tick < 0:
		return
	if tick - fighter.buffered_press_tick > rules.weapon.buffer_ticks:
		fighter.buffered_press_tick = -1
		fighter.buffered_release = false
		return
	if not can_start_attack(fighter, rules.weapon):
		return
	var released := fighter.buffered_release
	_begin_press(fighter, tick, events)
	fighter.buffered_release = false
	if released:
		_launch(fighter, rules, 0.0, tick, events)
		fighter.press_tick = -1


static func _launch(fighter: FighterState, rules: DuelRules, charge: float, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := fighter.weapon
	var definition := rules.weapon
	weapon.swing_charge = charge
	weapon.charge = 0.0
	weapon.swing_start = weapon.angle
	weapon.swing_end = clampf(weapon.angle + weapon.swing_dir * definition.arc(charge), -definition.guard_limit, definition.guard_limit)
	weapon.swing_hit = false
	weapon.swing_contact = false
	weapon.set_phase(CombatPhase.Id.LAUNCH)
	events.append(DuelEvent.create(DuelEventTypes.ATTACK_RELEASED, tick, fighter.slot, DuelEvent.NONE, {
		DuelEventKeys.CHARGE: charge,
		DuelEventKeys.ARC: absf(weapon.swing_end - weapon.swing_start),
		DuelEventKeys.DIRECTION: weapon.swing_dir,
	}))


static func _drive_motor(weapon: WeaponState, definition: WeaponDefinition) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	match weapon.phase:
		CombatPhase.Id.CHARGING:
			var target := clampf(
				weapon.windup_base - weapon.swing_dir * definition.windup_angle(weapon.charge),
				-definition.guard_limit,
				definition.guard_limit
			)
			var desired := clampf(definition.windup_gain * (target - weapon.angle), -definition.windup_speed, definition.windup_speed)
			weapon.speed = SimMath.approach(weapon.speed, desired, definition.windup_accel * dt)
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			var charge := weapon.swing_charge
			weapon.speed = SimMath.approach(weapon.speed, weapon.swing_dir * definition.swing_speed(charge), definition.swing_accel(charge) * dt)
		CombatPhase.Id.OVERSWING:
			weapon.speed = SimMath.approach(weapon.speed, 0.0, definition.brake_accel(weapon.swing_charge) * dt)
		CombatPhase.Id.BIND:
			weapon.speed = SimMath.approach(weapon.speed, 0.0, definition.hold_damping * BIND_DAMPING_SCALE * dt)
		_:
			weapon.speed = SimMath.approach(weapon.speed, 0.0, definition.hold_damping * dt)
	weapon.angle += weapon.speed * dt
	if weapon.angle > definition.guard_limit:
		weapon.angle = definition.guard_limit
		weapon.speed = minf(weapon.speed, 0.0)
	elif weapon.angle < -definition.guard_limit:
		weapon.angle = -definition.guard_limit
		weapon.speed = maxf(weapon.speed, 0.0)


static func _advance_phase(fighter: FighterState, opponent: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := fighter.weapon
	match weapon.phase:
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			var next := _phase_for_progress(_swing_progress(weapon))
			var blocked := absf(weapon.speed) <= SimMath.EPSILON and weapon.phase_ticks > 1
			if next == CombatPhase.Id.OVERSWING or blocked:
				weapon.set_phase(CombatPhase.Id.OVERSWING)
			elif next > weapon.phase:
				weapon.set_phase(next)
		CombatPhase.Id.OVERSWING:
			if weapon.speed * weapon.swing_dir <= 0.0:
				if not weapon.swing_contact:
					events.append(DuelEvent.create(DuelEventTypes.ATTACK_WHIFFED, tick, fighter.slot, DuelEvent.NONE, {DuelEventKeys.CHARGE: weapon.swing_charge}))
				weapon.speed = 0.0
				begin_recovery(fighter, opponent, rules, 0.0)
		CombatPhase.Id.RECOVERY:
			weapon.recovery_left -= 1
			if weapon.recovery_left <= 0:
				weapon.set_phase(CombatPhase.Id.NEUTRAL)
		CombatPhase.Id.STAGGER:
			fighter.stagger_left -= 1
			if fighter.stagger_left <= 0:
				weapon.set_phase(CombatPhase.Id.NEUTRAL)


static func _swing_progress(weapon: WeaponState) -> float:
	var arc := (weapon.swing_end - weapon.swing_start) * weapon.swing_dir
	if arc <= SimMath.EPSILON:
		return 1.0
	return (weapon.angle - weapon.swing_start) * weapon.swing_dir / arc


static func _phase_for_progress(progress: float) -> CombatPhase.Id:
	if progress >= 1.0:
		return CombatPhase.Id.OVERSWING
	if progress >= PROGRESS_LATE:
		return CombatPhase.Id.ACTIVE_LATE
	if progress >= PROGRESS_THREAT:
		return CombatPhase.Id.ACTIVE_THREAT
	if progress >= PROGRESS_EARLY:
		return CombatPhase.Id.ACTIVE_EARLY
	return CombatPhase.Id.LAUNCH
