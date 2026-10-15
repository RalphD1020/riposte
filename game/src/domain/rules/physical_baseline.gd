class_name PhysicalBaseline
extends RefCounted

## The one place the duel's physical scale is written down. `scale = 1.0` is a
## concrete fighter holding a concrete sword, in SI units — never an abstract
## "player size 100".
##
## These are a *normalized combat baseline*, not a demographic claim. The
## fighter is a neutral athletic duelist: 1.75 m is close to the modern adult
## male mean, but 80 kg is deliberately below the ~90 kg population mean,
## because that mean includes bodies nobody would cast as a duelist.
##
## The sword needs no such apology. 1.22 m overall with a ~0.97 m blade at
## ~1.6 kg is almost directly represented by surviving museum examples, which
## makes it an unusually trustworthy anchor for every weapon that scales from
## it (CONTENT-002).
##
## Nothing here is a gameplay number. Damage, reach, and speed are *derived*
## from these through physics; see FighterDefinition and WeaponDefinition.
##
## Implements: /spec/invariants.md#content-002
## See also: /docs/concepts/combat.md, /docs/concepts/content.md

## Baseline fighter.
const FIGHTER_HEIGHT_M := 1.75
const FIGHTER_MASS_KG := 80.0
const FIGHTER_RADIUS_M := 0.27
## The torso a blade can actually strike, at blade height: the enclosing
## radius of Wolf's gambeson measured from `wolf.blend` between 0.95 and
## 1.30 m (half-width 0.185, half-depth 0.154). Smaller than the footprint,
## which also has to hold elbows, hips and feet apart (CONTACT-ROLES-001).
const TORSO_HURT_RADIUS_M := 0.195
## The planar size of a hand around its grip point, for surface-to-surface
## clearance against the torso: half the width of Wolf's authored hand block
## (`build_wolf.py`, 0.07 × 0.06 m). A hand is never a point.
const HAND_PROXY_RADIUS_M := 0.035
## The mass each hand carries with the sword, as a share of body mass: the
## hand itself (0.006 of the body in the standard segment tables) rides the
## grip rigidly, and the forearm (0.016) hinges at the elbow, so as a uniform
## rod swung from one end it reflects a third of its mass to the hand. Upper
## arms barely move with θ and are left with the body. ~0.91 kg per hand at
## the baseline; the held sword's weapon coordinate carries it (RIGID-CONTACT-001,
## `WeaponKinematics.held_inertia`).
const HAND_REFLECTED_MASS_SHARE := 0.006 + 0.016 / 3.0

## Baseline weapon: a bastard sword measured from the pommel, where the
## fighter grips and the swing pivots.
const SWORD_LENGTH_M := 1.22
const SWORD_BLADE_M := 0.97
const SWORD_MASS_KG := 1.60
## Baseline grip: how far out from the swing origin the duelist's hands put the
## guard. It belongs to the fighter, not the sword: weapon reach is the
## wielder's grip plus the weapon's blade, so a longer-armed fighter reaches
## further with the same sword and no mesh measurement ever decides it.
const GRIP_RADIUS_M := SWORD_LENGTH_M - SWORD_BLADE_M
## The usable handle, from the pommel: the pommel's shoulder to the underside
## of the crossguard, measured on the authored sword (`bastard_sword.blend`;
## the asset validator holds the model to these).
const POMMEL_SHOULDER_M := 0.030
const GUARD_UNDERSIDE_M := 0.2315
## The crossguard on the same model: 2.5 cm deep along the blade, so centred
## 1.25 cm above its underside, and 14.4 cm either side of the blade to the
## outer faces of the quillon caps. It is steel on its blade side only
## (GUARD-PROTECTION-001), and never hurt geometry (GRIP-NONBLOCKING-001).
const CROSSGUARD_DEPTH_M := 0.025
const CROSSGUARD_CENTRE_M := GUARD_UNDERSIDE_M + CROSSGUARD_DEPTH_M * 0.5
const CROSSGUARD_HALF_SPAN_M := 0.144
## The handle's own thickness on the same model: the `Grip` mesh's cross
## section is 2.6 × 3.0 cm, so it is enclosed by a 1.5 cm radius: the bare
## handle's hurt geometry, beside the hand discs around it
## (GRIP-NONBLOCKING-001).
const GRIP_HALF_WIDTH_M := 0.015
## How much air each hand keeps from the pommel and the guard.
const POMMEL_HAND_CLEARANCE_M := 0.005
const GUARD_HAND_CLEARANCE_M := 0.010
## Where the two hands hold the grip, from the pommel, derived from the handle
## and the hand: a right-handed hand-and-a-half grip with both hands on the
## handle — the dominant hand just under the guard, the off hand just above the
## pommel (the authored GripOffhand / GripDominant markers; the validator
## checks them). Fixed weapon-local points: they never swap, slide or bunch.
const GRIP_OFFHAND_M := POMMEL_SHOULDER_M + HAND_PROXY_RADIUS_M + POMMEL_HAND_CLEARANCE_M
const GRIP_DOMINANT_M := GUARD_UNDERSIDE_M - HAND_PROXY_RADIUS_M - GUARD_HAND_CLEARANCE_M
## The point on the sword the attack orbit carries, from the pommel
## (WEAPON-PATH-003). The orbit was calibrated with it at the old hand
## midpoint; it stays fixed so θ, `C(θ)` and every authoritative sword point
## keep their meaning whatever grip the hands take on the handle.
const CARRIAGE_REFERENCE_M := 0.1875

## Baseline blade geometry. The canonical guards sit at plus or minus 45
## degrees, the blade may legitimately travel to plus or minus 135, and the
## shortest committed arc is 90.
const GUARD_ANGLE_RAD := PI * 0.25
const GUARD_LIMIT_RAD := PI * 0.75
const TAP_ARC_RAD := PI * 0.5


## Geometry scales **linearly**. A fighter twice as tall is twice as wide, and
## a sword twice as long has twice the blade.
static func fighter_height(scale: float) -> float:
	return FIGHTER_HEIGHT_M * scale


static func fighter_radius(scale: float) -> float:
	return FIGHTER_RADIUS_M * scale


static func torso_hurt_radius(scale: float) -> float:
	return TORSO_HURT_RADIUS_M * scale


static func hand_proxy_radius(scale: float) -> float:
	return HAND_PROXY_RADIUS_M * scale


static func fighter_grip(scale: float) -> float:
	return GRIP_RADIUS_M * scale


static func sword_length(scale: float) -> float:
	return SWORD_LENGTH_M * scale


static func sword_blade(scale: float) -> float:
	return SWORD_BLADE_M * scale


## Mass scales **cubically**, but only as a *default generator* for
## hypothetical geometry of the same density (PHYS-005). It is not a law about
## real objects: a real weapon's mass is a measured fact and is authored
## directly, because a longer sword is usually also a thinner one.
static func volumetric_mass(baseline_mass: float, scale: float) -> float:
	return baseline_mass * scale * scale * scale


## Force scales with cross-section, **squared**. Combined with cubic mass this
## is where "larger is stronger but slower" comes from for free: `a = F/m` goes
## as `s² / s³`, which is `1 / s`. There is no arbitrary speed penalty
## anywhere, and there must never be one.
static func structural_scale(baseline: float, scale: float) -> float:
	return baseline * scale * scale


## Torque is force times a lever, so it scales **cubically** — squared for the
## cross-section driving it, linearly for the limb carrying it. Turning the
## body then goes as `α = τ / I_body`, or `s³ / s⁵`, so a bigger fighter turns
## more slowly; driving the *same* sword goes as `s³ / I_weapon`, so a bigger
## fighter swings it faster without the sword itself changing (COMBAT §27).
static func torque_scale(baseline: float, scale: float) -> float:
	return baseline * scale * scale * scale
