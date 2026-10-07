class_name WeaponSystem
extends RefCounted

## The one-button weapon language and the sword motor
## (COMBAT §12–§22, §41, §56, §64).
##
## Tap (release before the threshold) launches a 0% charge 90° cut *from
## wherever the blade actually is*: +45° → -45°, +20° → -70°, +135° → +45°.
## It is never "move to the opposite guard". Holding past the threshold winds
## the blade physically away from the swing, and charge is the wind-back it
## *earns* — degrees of outward travel past the canonical guard, or past where
## the hold began if the blade was already further out. Charge is never a
## timer: a blade that cannot travel cannot charge, however long it is held.
## Release launches from the actual retracted angle with arc 90° + earned
## wind-back. The motor accelerates toward the swing, brakes into an
## overswing, and the sword then rests wherever it stopped — nothing
## recentres it.
##
## ±45° are canonical *reference* guards, not mandatory resting positions. The
## blade may legitimately sit anywhere in its 270° coverage, and non-canonical
## is not uniformly worse: inside ±45° the blade is under-loaded (quick to
## threat, low motor authority), outside it is over-displaced (full authority,
## but a longer arc before it threatens). Both fall out of `launch_readiness`
## and arc; neither is special-cased.
##
## Swing direction comes from the side the blade is *committed* to, never a
## combo index and never the raw sign of the angle.
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


## The valid attack direction: away from the side the blade is committed to.
## A blade on the right sweeps counter-clockwise, one on the left clockwise.
## Derived from remembered side rather than the live sign of the angle, so a
## blade resting within the centre deadzone keeps swinging the way it last
## meant to instead of alternating on floating-point noise.
static func swing_direction(weapon: WeaponState) -> float:
	return -weapon.stable_side


## Remember which side the blade is on once it is clear of the centre band.
## Inside the deadzone the previous commitment stands.
static func update_stable_side(weapon: WeaponState, definition: WeaponDefinition) -> void:
	if absf(weapon.angle) <= definition.side_deadzone:
		return
	weapon.stable_side = 1.0 if weapon.angle > 0.0 else -1.0


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
		_clear_charge(weapon)
		enter_recovery(weapon, rules.weapon.recovery_base_ticks)
	if had_attack:
		events.append(DuelEvent.create(DuelEventTypes.ATTACK_CANCELED, tick, fighter.slot))


## Advance the weapon one tick: buffered press, tap/charge threshold, motor,
## guard limit, phase progression, and commitment. `capability` scales the
## weapon torque (PHYS-003). If `scratch` is provided, writes motor exertion
## (actual torque × angular velocity work + utilization) into it.
static func step(fighter: FighterState, opponent: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent], capability: float = 1.0, scratch: FighterTickScratch = null) -> void:
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
		_clear_charge(weapon)
		events.append(DuelEvent.create(DuelEventTypes.CHARGE_STARTED, tick, fighter.slot, DuelEvent.NONE, {DuelEventKeys.DIRECTION: weapon.swing_dir}))
	_drive_motor(weapon, definition, rules.fighter.weapon_torque_scale * capability, scratch)
	if weapon.phase == CombatPhase.Id.CHARGING:
		_accrue_windback(weapon, definition)
	update_stable_side(weapon, definition)
	_advance_phase(fighter, opponent, rules, tick, events)
	weapon.commitment = CommitmentModel.commitment(weapon, definition)


## Interrupt the weapon: stagger after a strong body hit (COMBAT §55).
static func stagger(fighter: FighterState, ticks: int) -> void:
	fighter.clear_attack_input()
	_clear_charge(fighter.weapon)
	fighter.weapon.set_phase(CombatPhase.Id.STAGGER)
	fighter.stagger_left = maxi(ticks, 1)


## Kill a fighter at tick fraction `lethal_fraction`. The time is taken rather
## than assumed, because a trade is decided by whose blade arrived first and
## both blows can land inside one tick (COMBAT §58).
static func kill(fighter: FighterState, lethal_fraction: float) -> void:
	fighter.clear_attack_input()
	_clear_charge(fighter.weapon)
	fighter.weapon.set_phase(CombatPhase.Id.DEAD)
	fighter.stagger_left = 0
	fighter.gesture.reset()
	fighter.lethal_fraction = maxf(lethal_fraction, 0.0)


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
	weapon.swing_dir = swing_direction(weapon)
	weapon.hold_start_angle = weapon.angle
	weapon.earned_windback = 0.0
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
	_clear_charge(weapon)
	## Preparation is read once, from where the blade actually is at release.
	weapon.launch_readiness = definition.readiness(weapon.angle)
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


static func _drive_motor(weapon: WeaponState, definition: WeaponDefinition, drive: float, scratch: FighterTickScratch = null) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var old_speed := weapon.speed
	var phase_accel := 0.0
	match weapon.phase:
		CombatPhase.Id.CHARGING:
			phase_accel = definition.windup_accel(drive)
			weapon.speed = SimMath.approach(weapon.speed, -weapon.swing_dir * definition.windup_speed, phase_accel * dt)
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			var charge := weapon.swing_charge
			var ceiling := definition.achievable_swing_speed(charge, weapon.launch_readiness)
			phase_accel = definition.swing_accel(charge, drive)
			weapon.speed = SimMath.approach(weapon.speed, weapon.swing_dir * ceiling, phase_accel * dt)
		CombatPhase.Id.OVERSWING:
			phase_accel = definition.brake_accel(weapon.swing_charge, drive)
			weapon.speed = SimMath.approach(weapon.speed, 0.0, phase_accel * dt)
		CombatPhase.Id.BIND:
			phase_accel = definition.hold_accel(drive) * BIND_DAMPING_SCALE
			weapon.speed = SimMath.approach(weapon.speed, 0.0, phase_accel * dt)
		_:
			phase_accel = definition.hold_accel(drive)
			weapon.speed = SimMath.approach(weapon.speed, 0.0, phase_accel * dt)
	if scratch != null:
		_record_weapon_exertion(scratch, definition, old_speed, weapon.speed, phase_accel, dt)
	weapon.angle += weapon.speed * dt
	if weapon.angle > definition.guard_limit:
		weapon.angle = definition.guard_limit
		weapon.speed = minf(weapon.speed, 0.0)
	elif weapon.angle < -definition.guard_limit:
		weapon.angle = -definition.guard_limit
		weapon.speed = maxf(weapon.speed, 0.0)


## Close the current hold's charge account. A hold that ends without launching
## leaves nothing behind for the next one to inherit.
static func _clear_charge(weapon: WeaponState) -> void:
	weapon.charge = 0.0
	weapon.earned_windback = 0.0


## Credit the hold with the outward travel it has achieved past its baseline.
##
## Three properties the duel depends on, all of them falling out of these few
## lines rather than out of special cases:
##
## - A blade flung outward by a collision is not charge. The baseline is the
##   further of the canonical guard and where the hold started, so inheriting
##   +100° and releasing immediately earns nothing.
## - Restoring an under-prepared blade is not charge either. From +20° the
##   baseline is still the guard, so the first 25° of travel buys nothing.
## - Charge cannot be won faster than the motor could win it. Per tick the
##   credit grows by at most one tick of wind-back, so a violent impulse
##   cannot convert itself into instant full charge, and a blade pinned by an
##   opposing bind earns nothing at all because it is not moving.
##
## Credit saturates at the span that buys full charge, so `earned_windback` and
## `charge` always describe the same swing: arc = min_arc + earned wind-back.
static func _accrue_windback(weapon: WeaponState, definition: WeaponDefinition) -> void:
	var excursion := absf(weapon.angle) - definition.windback_baseline(weapon.hold_start_angle)
	var motor_cap := weapon.earned_windback + definition.windup_speed * SimulationTimebase.TICK_SECONDS
	## `windup_speed` is the motor's own ceiling, so one tick of it is the most
	## wind-back a tick can honestly represent.
	var credited := maxf(weapon.earned_windback, minf(excursion, motor_cap))
	weapon.earned_windback = minf(credited, definition.windback_span())
	weapon.charge = definition.earned_charge(weapon.earned_windback)


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


## Record the weapon motor's actual physical exertion into the tick scratch.
## Dynamic work = τ_applied × ω_mid × dt (positive part drives, negative brakes).
## Utilization = how much of the motor's capacity was demanded (isometric/static).
## Computed from the motor's own output — never reconstructed from Δv later.
static func _record_weapon_exertion(scratch: FighterTickScratch, definition: WeaponDefinition, old_speed: float, new_speed: float, phase_accel: float, dt: float) -> void:
	var inertia := definition.moment_of_inertia()
	var actual_alpha := (new_speed - old_speed) / dt
	var applied_torque := inertia * actual_alpha
	var mid_omega := (old_speed + new_speed) * 0.5
	var power := applied_torque * mid_omega
	scratch.weapon_positive_work += maxf(power * dt, 0.0)
	scratch.weapon_braking_work += maxf(-power * dt, 0.0)
	var max_change := phase_accel * dt
	scratch.weapon_utilization = SimMath.clamp01(absf(new_speed - old_speed) / max_change) if max_change > SimMath.EPSILON else 0.0
