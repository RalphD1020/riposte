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
## and movement coherence; zero only at a degenerate origin contact.
var strike_x: float = 0.0
var strike_y: float = 0.0
## Where on the blade, 0 = crossguard, 1 = tip.
var blade_fraction: float = 0.0

## Relative contact velocity: blade-point velocity minus target velocity.
var relative_speed: float = 0.0
## Closing component along the normal, clamped at zero. This is the single
## most important physical variable in the system (PHYS-001).
var normal_speed: float = 0.0

## How well the attacker's structure supports the cut (a reading; it scales
## the held weapon coordinate's inertia, never a body mass).
var coupling: float = 0.0
## The bodies on either side of the contact, in kg: always each fighter's real
## mass (rules v33) — footing changes what the actuators do, not the weight.
var attacker_mass: float = 0.0
var target_mass: float = 0.0

## The contact's solved normal impulse (N·s, ContactMechanics):
## `(1 + e)·v_n / k`, with the sword free to turn back through its lever.
## Drives displacement, blade deflection, stagger, and camera response.
var impulse: float = 0.0
## Energy the contact dissipates, `½(1 − e²)·v_n² / k` (J): what goes into
## the body rather than back into rebound — the physical ceiling on injury,
## which damage then scales by loss-only factors (bite, edge, incidence).
## Deliberately a different quantity from impulse: the bodies shove, the
## blade cuts.
var kinetic_severity: float = 0.0
## The most the contact could take out, `½·v_n² / k` (J).
var available_energy: float = 0.0
## Relative contact velocity decomposed against the blade: across it (the cut,
## along the travelling edge) and along the contact surface (sliding).
var transverse_speed: float = 0.0
var tangent_speed: float = 0.0

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

## Contact inverse effective mass `k` (PHYS-010, ContactMechanics): the
## target's body, the attacker's body, and the held weapon coordinate through
## its lever.
var inverse_effective_mass: float = 0.0
## The weapon coordinate's lever at the contact: how fast the contact point
## moves along the normal per unit θ̇ (`WeaponKinematics.lever`; `r × n` on a
## fixed pivot). Stored for the resolver to derive angular reaction.
var lever_cross: float = 0.0
## The weapon coordinate's effective inertia at this pose
## (`ContactMechanics.weapon_inertia`), paired with `lever_cross`.
var weapon_inertia: float = 0.0
## Restitution the contact was solved with.
var restitution: float = 0.0


## Impulse as a fraction of a reference solid impact, for consumers that need
## a bounded signal (feedback channels, damage curves, telemetry).
func normalized_impulse(tuning: CombatTuning) -> float:
	return impulse / tuning.reference_impulse


func normalized_severity(tuning: CombatTuning) -> float:
	return kinetic_severity / tuning.reference_severity


## Velocity change the cut's impulse imparts to the target, m/s. Falls straight
## out of `J = m Δv`, so exposure never enters it.
func target_delta_v() -> float:
	if target_mass <= SimMath.EPSILON:
		return 0.0
	return impulse / target_mass
