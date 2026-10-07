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

## Baseline weapon: a bastard sword measured from the pommel, where the
## fighter grips and the swing pivots.
const SWORD_LENGTH_M := 1.22
const SWORD_BLADE_M := 0.97
const SWORD_MASS_KG := 1.60

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
