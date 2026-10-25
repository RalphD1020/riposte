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
## overswing, and once the blade is back under control a guard return carries
## it to the committed guard (GUARD-RETURN-001). Nothing snaps it there.
##
## ±45° are the resting targets of that return, on the committed side. The
## blade may legitimately sit anywhere in its 270° coverage while it is
## swinging, staggered or giving way to an attack, and non-canonical is not
## uniformly worse: inside ±45° the blade is under-loaded (quick to threat,
## low motor authority), outside it is over-displaced (full authority, but a
## longer arc before it threatens). Both fall out of `launch_preparation` and
## arc; neither is special-cased.
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
## Short of the limit, still the stop. One ulp of `angle + ω·dt` is about
## 1e-15 rad here; 1e-9 rad is the trigonometry bound (`SimMath`, about a
## nanometre at the tip) and far below a pose the mirror oracle can tell
## apart. Not a gameplay slack. Kept while the changed duels are traced;
## narrowing it to recover an older hash is not a reason.
const STOP_ARRIVAL_RAD := 1.0e-9
## After the recovery floor, a queued tap may still be waiting on the brake.
## Two ticks covers the step that notices the coast and the step that opens
## the window. It is not a memory of the click. A bind that keeps the blade
## fast past the healthy brake from the speed at that moment drops the tap.
const TAP_COAST_SLACK := 2


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
		## The wound-back blade is arrested by the brake of the charge it carried.
		weapon.swing_charge = weapon.charge
		_clear_charge(weapon)
		enter_recovery(weapon, rules.combat.recovery_min_ticks)
	if had_attack:
		events.append(DuelEvent.create(DuelEventTypes.ATTACK_CANCELED, tick, fighter.slot))


## Advance the weapon one tick: buffered press, tap/charge threshold, motor,
## guard limit, phase progression, and commitment. `condition` is the
## fighter's frozen condition this tick (CONDITION-001): its force scale
## reduces every weapon torque, its speed scale the swing and wind-back target
## speeds; null is the healthy identity. The blade's speed is never rescaled
## (PHYS-003). `scratch` lends the reused motor pose. `return_scale` multiplies
## the guard return (persistent steel and impact authority). `diagnostics`
## counts a hard-stop fallback; null counts nothing.
static func step(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent], condition: ConditionState = null, scratch: FighterTickScratch = null, return_scale: float = 1.0, diagnostics: ContactDiagnostics = null) -> void:
	var weapon := fighter.weapon
	var definition := rules.spec_of(fighter).weapon
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
	var spec := rules.spec_of(fighter)
	var inertia := WeaponKinematics.motor_inertia(spec, weapon.angle, scratch.motor_pose if scratch != null else null)
	var speed_scale := condition.speed_scale if condition != null else 1.0
	## Two drives, named at the boundary (STAMINA-004). `base_drive` is the
	## damage term and feeds the neutral hold and the guard return. Fatigue
	## multiplies it once, into `fatigue_scaled_drive`, which feeds swing,
	## wind-up, brake and the stagger hold, and the soft zone's share of wind-up.
	## A weaker brake removes less speed in a tick. It does not change a speed
	## ceiling, command timing, or the return target.
	var damage_force := condition.damage_force_scale if condition != null else 1.0
	var fatigue := condition.fatigue_scale if condition != null else 1.0
	var base_drive := spec.fighter.weapon_torque_scale * damage_force
	var fatigue_scaled_drive := base_drive * fatigue
	if _drive_motor(weapon, definition, fatigue_scaled_drive, base_drive, speed_scale, inertia, rules.combat, return_scale, fighter.attack_held) and diagnostics != null:
		diagnostics.guard_hard_stop_hits += 1
	## A held charge earns credit only while stamina remains (STAMINA-004); at
	## zero it stops accumulating and is never released for the player.
	if weapon.phase == CombatPhase.Id.CHARGING and (condition == null or condition.can_charge):
		_accrue_windback(weapon, definition, speed_scale)
	update_stable_side(weapon, definition)
	_advance_phase(fighter, rules, tick, events)
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
## The fighter becomes a body (`FallenBodyState`): thrown along `fall_direction`
## (default: backward from their facing) and lying after `settle_ticks`.
static func kill(fighter: FighterState, lethal_fraction: float, fall_direction: float = NAN, settle_ticks: int = 0) -> void:
	fighter.clear_attack_input()
	_clear_charge(fighter.weapon)
	fighter.weapon.set_phase(CombatPhase.Id.DEAD)
	fighter.stagger_left = 0
	fighter.gesture.reset()
	fighter.lethal_fraction = maxf(lethal_fraction, 0.0)
	fighter.fallen.begin(fall_direction if is_finite(fall_direction) else fighter.facing + PI, settle_ticks)


## End a swing into recovery — a finished overswing, or a contact that
## arrested the cut (RECOVERY-001). There is no recovery arithmetic: the floor
## is universal and the rest is the blade's own momentum against its brake.
static func begin_recovery(fighter: FighterState, rules: DuelRules) -> void:
	enter_recovery(fighter.weapon, rules.combat.recovery_min_ticks)


## Enter recovery with a floor of `min_ticks`. It ends when the floor has
## passed **and** the blade is under `control_speed` (`_advance_phase`), the
## same gate for a whiff, an arrested cut and a dropped charge. The commitment
## the blade carried in decays with that same gate (`CommitmentModel`).
static func enter_recovery(weapon: WeaponState, min_ticks: int) -> void:
	weapon.recovery_commitment = weapon.commitment
	weapon.deflection_pending = false
	weapon.recovery_ticks = maxi(min_ticks, 1)
	weapon.recovery_left = weapon.recovery_ticks
	weapon.set_phase(CombatPhase.Id.RECOVERY)


static func _on_press(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	fighter.attack_held = true
	if can_start_attack(fighter, rules.spec_of(fighter).weapon):
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
## Promote a queued press once the blade can take it.
##
## One pending intent. A released click is a tap for the action that blocked
## it: it fires one charge-0 cut on that action's first controllable tick, and
## it is not kept into a later exchange. A finger that stays down is a hold.
## The four-tick stamp may expire; the hold does not. The hold starts on the
## first eligible tick, once, without a second press. A new press replaces a
## queued tap. Death, stagger, and cancel clear the intent.
static func _promote_buffer(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var definition := rules.spec_of(fighter).weapon
	if fighter.buffered_press_tick != -1 and can_start_attack(fighter, definition):
		_start_buffered(fighter, rules, tick, events)
		return
	if fighter.buffered_release and fighter.buffered_press_tick != -1 and _tap_expired(fighter, rules, tick):
		fighter.buffered_press_tick = -1
		fighter.buffered_release = false
	elif not fighter.buffered_release and fighter.buffered_press_tick >= 0 and tick - fighter.buffered_press_tick > definition.buffer_ticks:
		## The short buffer forgot the stamp. A finger still down is the hold
		## path below, not a second press.
		fighter.buffered_press_tick = -1
		fighter.buffered_release = false
	if (
		fighter.attack_held
		and not fighter.buffered_release
		and fighter.press_tick < 0
		and fighter.buffered_press_tick < 0
		and can_start_attack(fighter, definition)
	):
		_begin_press(fighter, tick, events)


static func _start_buffered(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var released := fighter.buffered_release
	_begin_press(fighter, tick, events)
	fighter.buffered_release = false
	if released:
		_launch(fighter, rules, 0.0, tick, events)
		fighter.press_tick = -1


## A tap pressed while the blade was already free expires with the four-tick
## buffer. A tap pressed during an action waits out that action. Once the
## recovery floor is done and the blade is still fast, the wait is the healthy
## brake from that speed. The deadline is stored as a negative stamp so the
## press tick itself is not a second piece of state.
static func _tap_expired(fighter: FighterState, rules: DuelRules, tick: int) -> bool:
	var weapon := fighter.weapon
	var definition := rules.spec_of(fighter).weapon
	if fighter.buffered_press_tick < -1:
		return tick >= -fighter.buffered_press_tick - 2
	var pressed_during_phase := fighter.buffered_press_tick >= tick - weapon.phase_ticks
	if weapon.phase == CombatPhase.Id.NEUTRAL and pressed_during_phase:
		return tick - fighter.buffered_press_tick > definition.buffer_ticks
	var coasting := (
		weapon.phase == CombatPhase.Id.RECOVERY
		and weapon.recovery_left == 0
		and absf(weapon.speed) > definition.control_speed
	)
	var carried_into_neutral := weapon.phase == CombatPhase.Id.NEUTRAL and not pressed_during_phase and absf(weapon.speed) > definition.control_speed
	if not coasting and not carried_into_neutral:
		return false
	var budget := _healthy_brake_ticks(fighter, rules) + TAP_COAST_SLACK
	fighter.buffered_press_tick = -(tick + budget) - 2
	return false


## Ticks for the healthy brake to take `speed` down to `control_speed`.
## Fatigue is not in it: a wound must not stretch a queued tap, and a bind
## that holds the speed up does not refresh this number.
static func _healthy_brake_ticks(fighter: FighterState, rules: DuelRules) -> int:
	var weapon := fighter.weapon
	var definition := rules.spec_of(fighter).weapon
	var excess := absf(weapon.speed) - definition.control_speed
	if excess <= 0.0:
		return 0
	var spec := rules.spec_of(fighter)
	var inertia := WeaponKinematics.motor_inertia(spec, weapon.angle)
	var brake := definition.brake_accel(weapon.swing_charge, spec.fighter.weapon_torque_scale, inertia)
	if brake <= SimMath.EPSILON:
		return 0
	return ceili(excess / (brake * SimulationTimebase.TICK_SECONDS))
	var definition := rules.spec_of(fighter).weapon
	weapon.swing_charge = charge
	_clear_charge(weapon)
	## Preparation is read once, from where the blade actually is at release.
	weapon.launch_preparation = definition.preparation(weapon.angle)
	weapon.swing_start = weapon.angle
	weapon.swing_end = clampf(weapon.angle + weapon.swing_dir * definition.arc(charge), -definition.guard_limit, definition.guard_limit)
	weapon.attack_contacted = false
	weapon.deflection_pending = false
	weapon.set_phase(CombatPhase.Id.LAUNCH)
	events.append(DuelEvent.create(DuelEventTypes.ATTACK_RELEASED, tick, fighter.slot, DuelEvent.NONE, {
		DuelEventKeys.CHARGE: charge,
		DuelEventKeys.ARC: absf(weapon.swing_end - weapon.swing_start),
		DuelEventKeys.DIRECTION: weapon.swing_dir,
	}))


static func _drive_motor(weapon: WeaponState, definition: WeaponDefinition, fatigue_scaled_drive: float, base_drive: float, speed_scale: float, inertia: float, combat: CombatTuning, return_scale: float, yield_attack: bool) -> bool:
	var dt := SimulationTimebase.TICK_SECONDS
	var old_speed := weapon.speed
	## Every drive is a bounded torque (`α = τ / M_θ`, at most `α·dt` per
	## tick) applied to whatever speed the last contact left: a met cut is
	## re-driven at the motor's finite authority, never restored by assignment.
	## `M_θ` is the coordinate's inertia at this pose, the one every contact
	## uses (UNIFIED-MASS-001). The torque recorded is the voluntary motor
	## only; the soft limit that follows is a stop, not exertion.
	match weapon.phase:
		CombatPhase.Id.CHARGING:
			weapon.speed = SimMath.approach(weapon.speed, -weapon.swing_dir * definition.windup_speed * speed_scale, definition.windup_accel(fatigue_scaled_drive, inertia) * dt)
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			var charge := weapon.swing_charge
			var ceiling := definition.achievable_swing_speed(charge, weapon.launch_preparation) * speed_scale
			weapon.speed = SimMath.approach(weapon.speed, weapon.swing_dir * ceiling, definition.swing_accel(charge, fatigue_scaled_drive, inertia) * dt)
		_:
			weapon.speed = coast_speed(weapon.speed, weapon.angle, weapon.phase, weapon.stable_side, weapon.swing_charge, definition, fatigue_scaled_drive, base_drive, inertia, combat, return_scale, yield_attack)
	weapon.motor_torque = inertia * (weapon.speed - old_speed) / dt
	var angle_before := weapon.angle
	var dt_limit := SimulationTimebase.TICK_SECONDS
	var accel := clampf(limit_zone_accel(weapon.angle, weapon.speed, definition.guard_limit, combat.guard_limit_zone, zone_spring(definition, fatigue_scaled_drive, inertia, combat), combat.guard_limit_damping), -limit_accel_cap(definition, fatigue_scaled_drive, inertia), limit_accel_cap(definition, fatigue_scaled_drive, inertia))
	var into := weapon.speed + accel * dt_limit
	var stopped := assign_stop(weapon, weapon.angle + into * dt_limit, into, definition.guard_limit)
	return is_hard_stop(into, angle_before, stopped, definition.guard_limit, definition.windup_accel(fatigue_scaled_drive, inertia))


## The guard limit is an inelastic stop: a blade that reaches it keeps no
## outward speed. Landing on it counts, and so does falling short by
## `STOP_ARRIVAL_RAD`: the mirror of the same step can round to the next
## float below the limit (seed 31, tick 535: 4.4e-16 rad short, 2.3 rad/s
## kept). A larger gap is not the stop, and inward speed is never removed.
## `turned` is the angle the step would reach. True when the stop moved the
## angle or removed outward speed.
static func settle_at_stop(weapon: WeaponState, turned: float, limit: float) -> bool:
	return assign_stop(weapon, turned, weapon.speed, limit)


## One coasting tick, before the soft limit: the guard return where it is
## active, the attack's brake while an overswing or a fast recovery still
## needs it, and a hold to zero speed otherwise. `yield_attack` is an attack
## command owning this tick, so NEUTRAL holds instead of returning.
## `base_drive` is the damage term (STAMINA-004): the neutral hold and the
## guard return. `fatigue_scaled_drive` is that term times fatigue: the brake
## and the stagger hold. Fatigue therefore removes less speed on a braking
## tick and does not change the return. Speed caps are not a drive. The
## predictor integrates this same function (GUARD-RETURN-001).
static func coast_speed(speed: float, angle: float, phase: CombatPhase.Id, stable_side: float, swing_charge: float, definition: WeaponDefinition, fatigue_scaled_drive: float, base_drive: float, inertia: float, combat: CombatTuning, return_scale: float, yield_attack: bool) -> float:
	var dt := SimulationTimebase.TICK_SECONDS
	if phase == CombatPhase.Id.OVERSWING or (phase == CombatPhase.Id.RECOVERY and absf(speed) > definition.control_speed):
		return SimMath.approach(speed, 0.0, definition.brake_accel(swing_charge, fatigue_scaled_drive, inertia) * dt)
	if phase == CombatPhase.Id.NEUTRAL and yield_attack:
		return SimMath.approach(speed, 0.0, definition.hold_accel(base_drive, inertia) * dt)
	if phase == CombatPhase.Id.NEUTRAL or phase == CombatPhase.Id.RECOVERY:
		return guard_return_speed(speed, angle, stable_side * definition.guard_angle, definition.hold_accel(base_drive, inertia), combat.guard_return_natural_frequency, return_scale)
	return SimMath.approach(speed, 0.0, definition.hold_accel(fatigue_scaled_drive, inertia) * dt)


## Critically damped pose track toward `target` with `ω* = 0`. The hinge
## error is `target − angle`: the guard interval is convex, so wrapping the
## error would command the long way through the stop. Implied α is capped
## at `hold_accel`, then multiplied by `scale`.
static func guard_return_speed(omega: float, angle: float, target: float, hold_accel: float, natural_frequency: float, scale: float) -> float:
	var dt := SimulationTimebase.TICK_SECONDS
	var wn := maxf(natural_frequency, 0.0)
	var kp := wn * wn
	var kd := 2.0 * wn
	var error := target - angle
	var predicted := (omega + dt * kp * error) / (1.0 + dt * kd + dt * dt * kp)
	var applied := clampf((predicted - omega) / dt, -hold_accel, hold_accel) * clampf(scale, 0.0, 1.0)
	return omega + applied * dt


## Inward acceleration (signed) of the soft zone. Zero outside it and for
## inward speed; the Hermite ramp is zero, flat, at the inner edge.
static func limit_zone_accel(angle: float, omega: float, limit: float, zone: float, stiffness: float, damping: float) -> float:
	if zone <= 0.0 or limit <= 0.0 or angle == 0.0:
		return 0.0
	var penetration := absf(angle) - (limit - zone)
	if penetration <= 0.0:
		return 0.0
	var share := clampf(penetration / zone, 0.0, 1.0)
	var shaped := share * share * (3.0 - 2.0 * share)
	var outward := 1.0 if angle > 0.0 else -1.0
	return -outward * (stiffness * shaped + damping * maxf(omega * outward, 0.0))


## Spring acceleration at full penetration: a share of this tick's wind-up
## acceleration, so a sustained wind-up still reaches the stop.
static func zone_spring(definition: WeaponDefinition, drive: float, inertia: float, combat: CombatTuning) -> float:
	return combat.guard_limit_stiffness * definition.windup_accel(drive, inertia)


## The zone never out-accelerates the weapon's strongest brake.
static func limit_accel_cap(definition: WeaponDefinition, drive: float, inertia: float) -> float:
	return maxf(definition.brake_accel(0.0, drive, inertia), definition.brake_accel(1.0, drive, inertia))


## Soft zone, then the hard stop. `out[0]` angle, `out[1]` speed after the
## stop, and `out[2]` (when present) the speed the stop saw. Callers reuse
## `out`; the weapon step itself writes the weapon and does not allocate one.
static func write_limited(out: PackedFloat64Array, angle: float, speed: float, limit: float, zone: float, stiffness: float, damping: float, accel_cap: float) -> bool:
	var dt := SimulationTimebase.TICK_SECONDS
	var accel := clampf(limit_zone_accel(angle, speed, limit, zone, stiffness, damping), -accel_cap, accel_cap)
	var into := speed + accel * dt
	var hit := _write_stop(out, angle + into * dt, into, limit)
	if out.size() > 2:
		out[2] = into
	return hit


## Angle after the inelastic stop. Closed clamp: landing on the limit stays there.
static func stopped_angle(turned: float, limit: float) -> float:
	return clampf(turned, -limit, limit)


## True when `turned` meets a stop in the direction of `speed`.
static func _outward_at_stop(turned: float, speed: float, limit: float) -> bool:
	if speed > 0.0 and turned >= limit - STOP_ARRIVAL_RAD:
		return true
	if speed < 0.0 and turned <= -limit + STOP_ARRIVAL_RAD:
		return true
	return false


## Speed after the inelastic stop. Outward speed at or past the limit is removed.
## Inward speed, and a blade already on the limit with none, stay.
static func stopped_speed(turned: float, speed: float, limit: float) -> float:
	if _outward_at_stop(turned, speed, limit):
		return 0.0
	return speed


## True when the stop moved the angle or removed outward speed.
static func stop_engaged(turned: float, speed: float, limit: float) -> bool:
	if turned > limit or turned < -limit:
		return true
	return _outward_at_stop(turned, speed, limit)


## Write the inelastic stop onto a weapon. Authoritative callers are the
## weapon step (`_drive_motor`) and the post-contact carry
## (`settle_at_stop` from `DuelSimulation._carry`). The threat estimate does
## not call this: it copies angle and speed into locals and writes the same
## rule into its own buffer (`write_limited` → `_write_stop`).
static func assign_stop(weapon: WeaponState, turned: float, speed: float, limit: float) -> bool:
	weapon.angle = stopped_angle(turned, limit)
	weapon.speed = stopped_speed(turned, speed, limit)
	return stop_engaged(turned, speed, limit)


## The resting wind-up's own push into a stop it already occupies is not the
## fallback. A fallback is outward speed the zone left above one tick of
## wind-up, or a blade that was already past the limit.
static func is_hard_stop(speed_into: float, angle_before: float, stopped: bool, limit: float, windup_accel: float) -> bool:
	if not stopped:
		return false
	if absf(angle_before) > limit:
		return true
	if angle_before == 0.0 or speed_into * angle_before <= 0.0:
		return false
	return absf(speed_into) > windup_accel * SimulationTimebase.TICK_SECONDS


static func _write_stop(out: PackedFloat64Array, turned: float, speed: float, limit: float) -> bool:
	out[0] = stopped_angle(turned, limit)
	out[1] = stopped_speed(turned, speed, limit)
	return stop_engaged(turned, speed, limit)


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
static func _accrue_windback(weapon: WeaponState, definition: WeaponDefinition, speed_scale: float) -> void:
	var excursion := absf(weapon.angle) - definition.windback_baseline(weapon.hold_start_angle)
	var motor_cap := weapon.earned_windback + definition.windup_speed * speed_scale * SimulationTimebase.TICK_SECONDS
	## `windup_speed` is the motor's own ceiling, so one tick of it is the most
	## wind-back a tick can honestly represent.
	var credited := maxf(weapon.earned_windback, minf(excursion, motor_cap))
	weapon.earned_windback = minf(credited, definition.windback_span())
	weapon.charge = definition.earned_charge(weapon.earned_windback)


static func _advance_phase(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
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
			## The brake stops at exactly zero, so a free overswing ends at rest.
			## A contact that reversed it keeps its rebound into recovery,
			## where the hold motor settles it — never assigned away here.
			if weapon.speed * weapon.swing_dir <= 0.0:
				if not weapon.attack_contacted:
					events.append(DuelEvent.create(DuelEventTypes.ATTACK_WHIFFED, tick, fighter.slot, DuelEvent.NONE, {DuelEventKeys.CHARGE: weapon.swing_charge}))
				## Steel redirected it and it struck nothing (DEFLECTION-001), credited
				## to the defender.
				elif weapon.deflection_pending:
					events.append(DuelEvent.create(DuelEventTypes.DEFLECTION, tick, 1 - fighter.slot, fighter.slot, {DuelEventKeys.CHARGE: weapon.swing_charge}))
				begin_recovery(fighter, rules)
		CombatPhase.Id.RECOVERY:
			weapon.recovery_left = maxi(weapon.recovery_left - 1, 0)
			if weapon.recovery_left == 0 and absf(weapon.speed) <= rules.spec_of(fighter).weapon.control_speed:
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

