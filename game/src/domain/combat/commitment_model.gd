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

## Phase factor F_phase (COMBAT §20). Recovery decays linearly to zero.
const FACTOR_CHARGING := 0.2
const FACTOR_LAUNCH := 0.6
const FACTOR_ACTIVE_EARLY := 0.8
const FACTOR_ACTIVE := 1.0
const FACTOR_BIND := 0.5
const STAGGER_COMMITMENT := 0.6


static func commitment(weapon: WeaponState, definition: WeaponDefinition) -> float:
	var charge := weapon.charge if weapon.phase == CombatPhase.Id.CHARGING else weapon.swing_charge
	var base := SimMath.mix(definition.tap_commitment, 1.0, SimMath.pow_1_25(charge))
	match weapon.phase:
		CombatPhase.Id.CHARGING:
			return base * FACTOR_CHARGING
		CombatPhase.Id.LAUNCH:
			return base * FACTOR_LAUNCH
		CombatPhase.Id.ACTIVE_EARLY:
			return base * FACTOR_ACTIVE_EARLY
		CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE, CombatPhase.Id.OVERSWING:
			return base * FACTOR_ACTIVE
		CombatPhase.Id.RECOVERY:
			if weapon.recovery_ticks <= 0:
				return 0.0
			return weapon.recovery_commitment * float(weapon.recovery_left) / float(weapon.recovery_ticks)
		CombatPhase.Id.BIND:
			return base * FACTOR_BIND
		CombatPhase.Id.STAGGER:
			return STAGGER_COMMITMENT
	return 0.0


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


## Opponent orbiting against the committed swing direction, normalized to [0, 1].
static func counter_rotation_pressure(fighter: FighterState, opponent: FighterState, definition: FighterDefinition) -> float:
	var phase := fighter.weapon.phase
	if phase != CombatPhase.Id.CHARGING and not CombatPhase.is_striking(phase):
		return 0.0
	var orbit := DuelGeometry.orbit_rate(fighter, opponent)
	if orbit * fighter.weapon.swing_dir >= 0.0 or definition.counter_rotation_reference_rate <= 0.0:
		return 0.0
	return SimMath.clamp01(absf(orbit) / definition.counter_rotation_reference_rate)


## Facing must be earned (COMBAT §10): committed fighters cannot track well.
static func tracking_multiplier(fighter: FighterState, opponent: FighterState, definition: FighterDefinition) -> float:
	match fighter.weapon.phase:
		CombatPhase.Id.DEAD:
			return 0.0
		CombatPhase.Id.STAGGER:
			return definition.stagger_tracking
	var commitment_value := fighter.weapon.commitment
	var tracking := 1.0 - definition.tracking_commit_penalty * commitment_value
	if fighter.weapon.phase == CombatPhase.Id.OVERSWING:
		tracking -= definition.overswing_tracking_penalty
	var pressure := counter_rotation_pressure(fighter, opponent, definition)
	tracking *= 1.0 - definition.counter_rotation_penalty * commitment_value * pressure
	return clampf(tracking, definition.min_tracking, 1.0)
