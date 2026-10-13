class_name WeaponMassProfile
extends RefCounted

## The authored mass distribution of a weapon, as contributions along the
## blade axis measured from the origin (the pommel), in metres and kilograms.
## The physical facts the simulation needs — total mass, centre of mass,
## moment of inertia about the origin, and from them the `I = k·m·L²`
## distribution coefficient — are DERIVED from the distribution once
## (EMERGENT-COMBAT-001), so a tip-heavy or pommel-weighted design changes
## handling by itself, with no separate authored inertia to keep in sync.
##
## This is authoring data. A weapon is one rigid body at runtime
## (`WeaponKinematics`), never a simulated chain of masses: a profile is
## summarised to its moments once when the weapon definition is built. A
## contribution is either a uniform segment `[from, to]` carrying a mass (a
## blade is close to uniform) or a point mass at a radius (a pommel, a guard,
## a concentrated tip). Both moments are exact.
##
## The profile is the runtime source: `WeaponDefinition.apply_mass_profile`
## derives the weapon's `mass`, `center_of_mass_radius` and
## `inertia_coefficient` from it (rules v33), and `is_valid()` holds them to it
## (`matches`) so no later write can leave the two describing different swords.
##
## Implements: /spec/invariants.md#emergent-combat-001
## See also: /docs/concepts/combat.md

## Accumulated moments about the origin: Σ m, Σ m·r, Σ m·r².
var _mass: float = 0.0
var _first_moment: float = 0.0
var _second_moment: float = 0.0


## Add a uniform segment of `mass` kg spanning `[from_radius, to_radius]` m
## from the origin. Its first and second moments are the exact integrals of a
## uniform rod, so a single blade segment reproduces the uniform-blade model
## the shipped sword is authored against.
func add_segment(from_radius: float, to_radius: float, mass: float) -> WeaponMassProfile:
	var a := minf(from_radius, to_radius)
	var b := maxf(from_radius, to_radius)
	_mass += mass
	_first_moment += mass * (a + b) * 0.5
	_second_moment += mass * (a * a + a * b + b * b) / 3.0
	return self


## Add a point mass (a pommel, a guard, a concentrated tip) at `radius` m.
func add_point(radius: float, mass: float) -> WeaponMassProfile:
	_mass += mass
	_first_moment += mass * radius
	_second_moment += mass * radius * radius
	return self


## Total mass (kg): Σ m.
func total_mass() -> float:
	return _mass


## Centre-of-mass radius from the origin (m): Σ m·r / Σ m.
func center_of_mass_radius() -> float:
	return _first_moment / _mass if _mass > 0.0 else 0.0


## Moment of inertia about the origin (kg·m²): Σ m·r².
func moment_of_inertia_about_origin() -> float:
	return _second_moment


## The distribution coefficient `k` in `I = k·m·L²` (PHYS-006) for a weapon of
## overall length `L`, derived from the distribution rather than authored.
func inertia_coefficient(length: float) -> float:
	return _second_moment / (_mass * length * length) if _mass > 0.0 and length > 0.0 else 0.0


func is_valid() -> bool:
	return _mass > 0.0 and _first_moment > 0.0 and _second_moment > 0.0


## Whether a weapon's runtime scalars still agree with this distribution to
## within `tolerance` (relative): a gate against a derived scalar being
## overwritten after the fact.
func matches(mass: float, com_radius: float, coefficient: float, length: float, tolerance: float) -> bool:
	return (
		_relative(total_mass(), mass) <= tolerance
		and _relative(center_of_mass_radius(), com_radius) <= tolerance
		and _relative(inertia_coefficient(length), coefficient) <= tolerance
	)


static func _relative(derived: float, authored: float) -> float:
	return absf(derived - authored) / maxf(absf(authored), 1.0e-9)
