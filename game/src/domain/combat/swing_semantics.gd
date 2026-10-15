class_name SwingSemantics
extends RefCounted

## What a swing *means*, as pure readings over authoritative state.
##
## Everything here answers a question an observer has — the player watching a
## blade, the HUD, a training overlay, the debug vectors — rather than a
## question the simulation has. Nothing in this file decides an outcome, and
## nothing in the simulation reads it back. That one-way direction is what lets
## presentation be as expressive as it likes without ever becoming a rule
## (PRES-001).
##
## It lives beside `damage_model.gd` rather than inside it on purpose. The
## damage model is the *consequence* half of a strike and exists only at
## contact; these are attacker-only readings taken every tick, and folding a
## per-tick presentation input into the consequence model would invert the
## separation that file exists to keep.
##
## Two laws shape every function below.
##
## **Never double-count.** A quantity already carried by another is not
## multiplied in again. Charge is the clearest case: a charged swing is
## dangerous because the motor drove the blade faster and further, and that
## speed is already in `tip_speed`. Multiplying by charge *as well* would make
## the same physical blade speed mean two different things depending on how it
## was reached.
##
## **Potential is not prediction.** `potential` says how dangerous this part of
## this swing is in the abstract; it says nothing about whether it will land or
## what it would do to anyone. Convergence is only knowable at contact, so the
## interface must never promise it in advance.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/combat.md, /docs/concepts/presentation.md

## Classification of a resolved strike. These *describe* what the physics
## produced; they never choose damage, and there is no dice roll anywhere near
## them. A name exists so feedback and telemetry can speak about a hit without
## re-deriving it, not so a lookup table can replace the curve.
enum Grade { GRAZE, LIGHT, SOLID, HEAVY, SWEET, DEVASTATING }

## Quality thresholds for the grades above, read against `StrikeResult.quality`
## so a grade and the damage it accompanies can never disagree about which was
## the bigger hit.
const GRADE_LIGHT := 0.25
const GRADE_SOLID := 0.6
const GRADE_HEAVY := 1.0
const GRADE_DEVASTATING := 1.5

## How much of the blade is the part worth hitting with, as a fraction of blade
## length (COMBAT §23). Normalized, never metres, so it means the same thing on
## a dagger and a greatsword.
const SWEET_REGION_MIN := 0.55
const SWEET_REGION_MAX := 0.90

## Floor on the structural term, so a badly prepared swing from an off-balance
## fighter still reads as *some* threat. A blade moving at speed is dangerous
## even when thrown badly, and a potential of zero would tell the player the
## opposite.
const STRUCTURE_FLOOR := 0.35


## How mechanically dangerous this part of the current swing is, in [0, 1],
## before anything about the opponent is considered.
##
## Dominated by tip speed, and quadratically so, because cutting is an energy
## problem: severity goes as `v²`, which is why a blade twice as fast is four
## times as grievous and why speed outweighs every other factor in a sword
## fight. Reading it from the blade's *actual* angular speed is what makes the
## dangerous part of the arc emerge from the acceleration curve instead of
## being authored — it lands at a slightly different point every swing, so
## there is a living curve to learn rather than "frame 14 is the crit frame".
##
## A blade that is not carrying a strike has no potential at all, however fast
## it happens to be travelling: a wind-back is a fast-moving sword that cannot
## cut anyone.
static func potential(
	blade_tip_speed: float, launch_preparation: float, stability: float, phase: CombatPhase.Id, weapon: WeaponDefinition
) -> float:
	if not CombatPhase.is_striking(phase):
		return 0.0
	var fastest := weapon.swing_speed_full * weapon.tip_radius
	if fastest <= SimMath.EPSILON:
		return 0.0
	var speed := SimMath.clamp01(blade_tip_speed / fastest)
	return speed * speed * structure(launch_preparation, stability)


## The structural quality behind a swing: how well prepared the blade was at
## release and how composed the body is carrying it. Both are already bounded
## fractions of their own, so this is simply their product lifted off zero.
static func structure(launch_preparation: float, stability: float) -> float:
	return SimMath.mix(STRUCTURE_FLOOR, 1.0, SimMath.clamp01(launch_preparation) * SimMath.clamp01(stability))


## Linear speed of the blade tip relative to the fighter's own translation,
## m/s. Body rotation and weapon rotation turn the blade about the same
## centre, so they add — the same sum `ImpactModel` uses, which is why a
## fighter spinning into their own cut hits harder — and a moving origin adds
## its path's share (`WeaponKinematics`).
static func tip_speed(fighter: FighterState, spec: CombatantPhysicsSpec) -> float:
	var weapon := spec.weapon
	if spec.handling.attack_path.is_fixed():
		return absf(fighter.turn_rate + fighter.weapon.speed) * weapon.tip_radius
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	WeaponKinematics.velocity_into(fighter, pose, pose.point_x(weapon.tip_radius), pose.point_y(weapon.tip_radius))
	return SimMath.length(pose.vx - fighter.vx, pose.vy - fighter.vy)


## How far through its commanded arc a swing physically is, in [0, 1].
##
## Measured in *travel*, never in elapsed ticks. A sword stopped dead by
## another sword has stopped progressing, and an animation clock would keep
## counting and tell the player their swing was further along than their blade.
static func phase_progress(weapon: WeaponState) -> float:
	return CommitmentModel.travel(weapon)


## How well the contact geometry served the strike, in [0, 1]: the right part
## of the blade, led by the edge. The two factors are separate questions — a
## perfectly aligned edge at the crossguard and a flat slap at the sweet spot are
## both poor contacts, for different reasons.
static func contact_quality(blade_efficiency: float, edge_alignment: float, weapon: WeaponDefinition) -> float:
	return SimMath.clamp01(blade_efficiency) * SimMath.mix(weapon.edge_floor, 1.0, SimMath.clamp01(edge_alignment))


## How hard a sword clash was, in [0, 1]: the energy the solve took out of it
## against a reference strong clash (`reference_clash_energy`), as an
## amplitude (`√(E / E_ref)`). For two swords meeting square at their centres of
## percussion that is exactly the closing speed over `blade_strong_speed`;
## where the solve gave way differently — a crash at the fortes that the bodies
## take, a flick off a free point — it reads as hard as it really was. A
## bounded fraction rather than a class name, so feedback is one continuous
## curve from a graze to a full deflection, never a louder label (COMBAT-009).
static func clash_intensity(energy: float, tuning: CombatTuning) -> float:
	if tuning.reference_clash_energy <= SimMath.EPSILON:
		return 0.0
	return SimMath.clamp01(sqrt(maxf(energy, 0.0) / tuning.reference_clash_energy))


## True when contact landed in the part of the blade worth hitting with.
## Diagnostic: the resolver reads the continuous efficiency curve, never this.
static func in_sweet_region(blade_fraction: float) -> bool:
	return blade_fraction >= SWEET_REGION_MIN and blade_fraction <= SWEET_REGION_MAX


## Name a resolved strike by the quality it actually produced. SWEET is the one
## grade that is not purely a magnitude: it means a heavy hit that also
## converged — the right part of the blade, edge leading, against a target that
## could not answer it — which is exactly what `StrikeResult.critical` already
## decides.
static func grade(quality: float, critical: bool) -> Grade:
	if quality >= GRADE_DEVASTATING:
		return Grade.DEVASTATING
	if critical:
		return Grade.SWEET
	if quality >= GRADE_HEAVY:
		return Grade.HEAVY
	if quality >= GRADE_SOLID:
		return Grade.SOLID
	if quality >= GRADE_LIGHT:
		return Grade.LIGHT
	return Grade.GRAZE


static func grade_label(value: Grade) -> String:
	match value:
		Grade.GRAZE:
			return "GRAZE"
		Grade.LIGHT:
			return "LIGHT"
		Grade.SOLID:
			return "SOLID"
		Grade.HEAVY:
			return "HEAVY"
		Grade.SWEET:
			return "SWEET"
		Grade.DEVASTATING:
			return "DEVASTATING"
	return "UNKNOWN"
