class_name CommitmentModel
extends RefCounted

## Commitment K and its consequences for footwork and tracking
## (COMBAT §20, §21, §26, §62). Power creates positional debt: K rises with
## charge and swing phase and reduces the *authority* to change motion —
## acceleration and turn torque — never the motion itself (PHYS-003). These
## are continuous curves, not table switches.
##
## Commitment answers "how hard is this action to change?". It is a different
## question from structural coupling ("how well is the body supporting this
## impact?"), and the two must not be conflated: a fully charged swing thrown
## mid-sidestep is maximally committed and badly structured at the same time.
##
## Implements: /spec/invariants.md#phys-003
## See also: /docs/concepts/combat.md

## One continuous, mirrored commitment (v36). A held charge carries
## `FACTOR_CHARGING` of the charge's base; through a swing commitment builds
## from that same value toward the full base as the blade actually gets going
## — the more of physical travel along the commanded arc (`travel`, eased in
## over `COMMIT_TRAVEL`) and of the actuated top speed (`|θ̇|`) it has — so no
## phase boundary steps it; overswing holds the full base; recovery decays
## from what it entered with as the blade is physically arrested (rules 44).
## Nothing reads a side: a mirrored state has exactly the same commitment.
const FACTOR_CHARGING := 0.2
## Share of the commanded arc over which travel alone brings full commitment.
const COMMIT_TRAVEL := 0.35
const STAGGER_COMMITMENT := 0.6


static func commitment(weapon: WeaponState, definition: WeaponDefinition) -> float:
	var charge := weapon.charge if weapon.phase == CombatPhase.Id.CHARGING else weapon.swing_charge
	var base := SimMath.mix(definition.tap_commitment, 1.0, SimMath.pow_1_25(charge))
	match weapon.phase:
		CombatPhase.Id.CHARGING:
			return base * FACTOR_CHARGING
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			var travelled := SimMath.hermite_step(0.0, COMMIT_TRAVEL, travel(weapon))
			var speed := SimMath.clamp01(absf(weapon.speed) / definition.swing_speed_full) if definition.swing_speed_full > 0.0 else 1.0
			return base * SimMath.mix(FACTOR_CHARGING, 1.0, maxf(travelled, speed))
		CombatPhase.Id.OVERSWING:
			return base
		CombatPhase.Id.RECOVERY:
			## Physical decay (RECOVERY-001): what the blade still carries
			## (`|θ̇|` over the actuated top speed) or what is left of the
			## universal floor, whichever is more — both end at the recovery
			## gate, so commitment is continuous into recovery and out of it.
			var settling := float(weapon.recovery_left) / float(weapon.recovery_ticks) if weapon.recovery_ticks > 0 else 0.0
			var moving := SimMath.clamp01(absf(weapon.speed) / definition.swing_speed_full) if definition.swing_speed_full > 0.0 else 0.0
			return weapon.recovery_commitment * maxf(settling, moving)
		CombatPhase.Id.STAGGER:
			return STAGGER_COMMITMENT
	return 0.0


## How far through its commanded arc a swing physically is, in [0, 1] —
## travel, never elapsed ticks: a sword stopped by another has stopped
## travelling. Symmetric in the swing direction, so mirrored.
static func travel(weapon: WeaponState) -> float:
	var arc := (weapon.swing_end - weapon.swing_start) * weapon.swing_dir
	if arc <= SimMath.EPSILON:
		return 1.0
	return SimMath.clamp01((weapon.angle - weapon.swing_start) * weapon.swing_dir / arc)


## What the body is *trying* to do, as a fraction of its top speed. Commitment
## MUST NOT appear here (PHYS-003): a committed fighter who was already driving
## forward keeps driving forward. Death and stagger are constraints on intent,
## not commitment — a corpse stops asking to move and brakes.
static func translation_multiplier(fighter: FighterState, definition: FighterDefinition) -> float:
	match fighter.weapon.phase:
		CombatPhase.Id.DEAD:
			return 0.0
		CombatPhase.Id.STAGGER:
			return definition.stagger_translation
	return 1.0


## Movement authority `A_move ∈ (0, 1]`: how much of the body's acceleration is
## still available to change velocity. This is the whole of what commitment
## costs in footwork — existing momentum continues untouched, so starting a
## heavy swing mid-stride keeps the stride and merely makes it expensive to
## brake or strafe. A corpse keeps full braking authority so it slides to rest
## rather than coasting forever.
static func move_authority(fighter: FighterState, definition: FighterDefinition) -> float:
	if fighter.weapon.phase == CombatPhase.Id.DEAD:
		return 1.0
	return clampf(
		1.0 - definition.accel_commit_penalty * fighter.weapon.commitment,
		definition.min_move_authority,
		1.0
	)


## Directional commitment (DIRECTIONAL-COMMIT-001, RESPONSIVE-COMMITMENT-001):
## the fighter's **redirect debt** — how much present momentum, and actuator
## effort still being committed, must be overcome before the action can be
## redirected. Continuous readings of the physical state, never state of their
## own, never chosen from a phase, a move or a label, and never a threshold:
##
## ```text
## t_w = (|M_θ·θ̇| + max(dir·τ_motor, 0)·T_look) / τ_brake      C_w = t_w / (t_w + T_w)
## t_r = (m·v_f + F_f·T_look) / F_brake                         C_r = sign(t_r)·|t_r| / (|t_r| + T_root)
## C_φ = clamp(1 − (1 − C_w)(1 − k·max(C_r, 0)) − relief·max(−C_r, 0), 0, 1)
## ```
##
## The saturating map grows from zero with no edge and approaches 1 smoothly,
## so a little more momentum always means a little more debt. `dir` is the
## weapon drive asked for (the swing's direction while driven, its wind-back
## while charging), `τ_motor` the torque the motor applied, `v_f` / `F_f` the
## body's velocity and footwork force along its heading. The brakes are the
## fighter's **healthy** ones: commitment describes the action, never the
## wound — injury lowers the final capability once, in `turn_torque_share` /
## `turn_rate_share` (CONDITION-001). Lateral motion has no forward component;
## a retreat relieves the debt but never below zero, so turning never exceeds
## healthy neutral. A contact that arrests the blade lowers `C_w` because it
## lowered `M_θ·θ̇` — no reset exists. Nothing reads a side.


## Weapon redirect debt (N·m·s): its generalized momentum plus the drive the
## motor is still committing over the lookahead.
static func weapon_redirect_impulse(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	var weapon := fighter.weapon
	var momentum := absf(WeaponKinematics.motor_inertia(spec, weapon.angle) * weapon.speed)
	var direction := 0.0
	if CombatPhase.is_swinging(weapon.phase):
		direction = weapon.swing_dir
	elif weapon.phase == CombatPhase.Id.CHARGING:
		direction = -weapon.swing_dir
	return momentum + maxf(direction * weapon.motor_torque, 0.0) * combat.commit_lookahead_seconds


## The healthy torque (N·m) this fighter arrests its blade with: the attack's
## own brake at full strength.
static func weapon_brake_torque(fighter: FighterState, spec: CombatantPhysicsSpec) -> float:
	var weapon := fighter.weapon
	var charge := weapon.charge if weapon.phase == CombatPhase.Id.CHARGING else weapon.swing_charge
	var inertia := WeaponKinematics.motor_inertia(spec, weapon.angle)
	return spec.weapon.brake_accel(charge, spec.fighter.weapon_torque_scale, inertia) * inertia


## Seconds of healthy braking the weapon's redirect debt costs.
static func weapon_stop_time(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	var brake := weapon_brake_torque(fighter, spec)
	return weapon_redirect_impulse(fighter, spec, combat) / brake if brake > SimMath.EPSILON else 0.0


## `C_w ∈ [0, 1)`.
static func weapon_commitment(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	return saturate(weapon_stop_time(fighter, spec, combat), combat.commit_weapon_reference_seconds)


## The body's velocity along its combat heading (m/s, + forward).
static func forward_speed(fighter: FighterState) -> float:
	return fighter.vx * SimMath.cosine(fighter.facing) + fighter.vy * SimMath.sine(fighter.facing)


## Signed seconds of healthy braking the body's directional debt costs: its
## momentum along the heading plus the impulse its footwork motor (`a·m`, last
## tick's applied force) is committing over the lookahead.
static func root_redirect_time(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	var body := spec.fighter
	if body.braking_force <= SimMath.EPSILON:
		return 0.0
	var momentum := body.mass * forward_speed(fighter)
	var drive := body.mass * (fighter.ax * SimMath.cosine(fighter.facing) + fighter.ay * SimMath.sine(fighter.facing))
	return (momentum + drive * combat.commit_lookahead_seconds) / body.braking_force


## `C_r ∈ (−1, +1)`: toward +1 strongly committed forward, 0 planted or
## lateral, toward −1 strongly retreating.
static func root_commitment(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	var time := root_redirect_time(fighter, spec, combat)
	return signf(time) * saturate(absf(time), combat.commit_root_reference_seconds)


## `C_φ ∈ [0, 1)`: one bounded composition — forward debt compounds the
## weapon's, retreat relieves it, and nothing goes below neutral.
static func facing_commitment(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	var weapon := weapon_commitment(fighter, spec, combat)
	var root := root_commitment(fighter, spec, combat)
	var forward := 1.0 - (1.0 - weapon) * (1.0 - combat.commit_root_facing_weight * maxf(root, 0.0))
	return SimMath.clamp01(forward - combat.commit_retreat_relief * maxf(-root, 0.0))


## The smooth saturating debt map `t / (t + T)`: 0 at 0, ½ at the reference,
## approaching 1 without an edge.
static func saturate(time: float, reference_time: float) -> float:
	return time / (time + reference_time) if time > 0.0 else 0.0


## The final share of the fighter's healthy turn torque available to bring φ
## onto the target bearing (HEADING-001): `lerp(1, commit_turn_torque_curve,
## C_φ)` times the wound's force scale, never below `commit_turn_torque_floor`
## of healthy (RESPONSIVE-COMMITMENT-001). Commitment never rejects the turn
## (AUTHORITY-001): the fighter starts turning on the tick it is asked, only
## slower. Constraints sit outside the floors: a corpse cannot turn, a
## staggered body turns at its stagger tracking, and a committed forward dash
## keeps its launch heading through the drive (MOVE-002), handing authority
## back continuously through its recovery.
static func turn_torque_share(fighter: FighterState, spec: CombatantPhysicsSpec, condition: ConditionState, combat: CombatTuning) -> float:
	var force := condition.force_scale if condition != null else 1.0
	return _share(fighter, spec, combat, combat.commit_turn_torque_curve, force, combat.commit_turn_torque_floor)


## The final share of the healthy turn-rate cap, likewise: `lerp(1,
## commit_turn_speed_curve, C_φ)` times the wound's tracking scale, never below
## `commit_turn_speed_floor`.
static func turn_rate_share(fighter: FighterState, spec: CombatantPhysicsSpec, condition: ConditionState, combat: CombatTuning) -> float:
	var tracking := condition.tracking_scale if condition != null else 1.0
	return _share(fighter, spec, combat, combat.commit_turn_speed_curve, tracking, combat.commit_turn_speed_floor)


static func _share(fighter: FighterState, spec: CombatantPhysicsSpec, combat: CombatTuning, curve: float, capability: float, floor_share: float) -> float:
	var share := 0.0
	match fighter.weapon.phase:
		CombatPhase.Id.DEAD:
			return 0.0
		CombatPhase.Id.STAGGER:
			share = spec.fighter.stagger_tracking * capability
		_:
			share = maxf(SimMath.mix(1.0, curve, facing_commitment(fighter, spec, combat)) * capability, floor_share)
	var gesture := fighter.gesture
	if gesture.is_bursting() and gesture.burst_kind == MovementGestureState.BurstKind.FORWARD_DASH:
		return 0.0
	if gesture.is_recovering():
		return share * gesture.recovery_progress()
	return share