class_name ImpactResult
extends RefCounted

## What physically arrived at one contact, before anything about the target's
## ability to cope with it (COMBAT §51.1, §51.3).
##
## Everything here is a measured physical quantity in SI units, derived from
## contact-time state. Nothing here knows about exposure, damage, or stagger —
## that separation is the point (PHYS-004): the sword does not acquire more
## momentum because its target was badly positioned.
##
## Implements: /spec/invariants.md#phys-001
## See also: /docs/concepts/combat.md

var point_x: float = 0.0
var point_y: float = 0.0
## Unit normal from the contact point into the target's center: the direction
## an impulse pushes them.
var normal_x: float = 1.0
var normal_y: float = 0.0
## Unit direction the contact point is travelling. Drives directional feedback
## and movement coherence; zero only at a degenerate pivot contact.
var strike_x: float = 0.0
var strike_y: float = 0.0
## Where on the blade, 0 = hilt, 1 = tip.
var blade_fraction: float = 0.0

## Relative contact velocity: blade-point velocity minus target velocity.
var relative_speed: float = 0.0
## Closing component along the normal, clamped at zero. This is the single
## most important physical variable in the system (PHYS-001).
var normal_speed: float = 0.0

## Share of the attacker's body that structure actually put behind the blade,
## and the striking mass that produced, in kg.
var coupling: float = 0.0
var attacker_effective_mass: float = 0.0
## Mass the target's structure brings to resisting displacement, in kg.
var target_effective_mass: float = 0.0

## Impulse `J = m_eff · v_n`, kg·m/s. Drives displacement, blade deflection,
## stagger, and camera response.
var impulse: float = 0.0
## Kinetic severity `E = ½ m_eff · v_n²`, joules. Drives cutting, injury, and
## lethality. Deliberately a different quantity from impulse: a heavy weapon
## shoves and a light fast one cuts.
var kinetic_severity: float = 0.0

## Contact geometry: where on the blade it landed and how well the edge led.
var blade_efficiency: float = 0.0
var edge_alignment: float = 0.0

## Point-strike kinematics (COMBAT-010, PHYS-007). Axial velocity is the
## component of relative velocity along the sword axis; thrust alignment is
## how much of the total relative motion is forward along the sword; incidence
## quality is how directly the point enters the body surface.
var axial_speed: float = 0.0
var thrust_alignment: float = 0.0
var incidence_quality: float = 0.0

## Bilateral impulse (PHYS-010). Inverse effective mass scalar k accounts for
## both body masses and (for non-stab) the weapon's angular inertia at the
## contact lever arm. The bilateral J is a base (zero-restitution) impulse
## that fully prevents interpenetration. The contact resolver scales by
## (1 + e) for first-contact restitution.
var inverse_effective_mass: float = 0.0
## Lever arm cross product: r × n, where r is pivot→contact and n is the
## contact normal. Stored for the resolver to derive angular reaction.
var lever_cross: float = 0.0
## Base bilateral impulse (zero restitution): v_rel_n / k.
var bilateral_impulse: float = 0.0


## Impulse as a fraction of a reference solid impact, for consumers that need
## a bounded signal (feedback channels, damage curves, telemetry).
func normalized_impulse(tuning: CombatTuning) -> float:
	return impulse / tuning.reference_impulse


func normalized_severity(tuning: CombatTuning) -> float:
	return kinetic_severity / tuning.reference_severity


## Velocity change this impulse imparts to the target, m/s. Falls straight out
## of `J = m Δv`, so a planted target is shoved less than a scrambling one and
## exposure never enters it.
func target_delta_v() -> float:
	if target_effective_mass <= SimMath.EPSILON:
		return 0.0
	return impulse / target_effective_mass
