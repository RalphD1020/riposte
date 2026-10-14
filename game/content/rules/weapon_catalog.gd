class_name WeaponCatalog
extends RefCounted

## Every weapon the game ships, keyed by identity (CONTENT-001).
##
## Weapons scale differently from bodies, and the signature of `bastard_sword_at`
## says so: geometry comes from a length scale, but **mass is always stated**.
## A body may plausibly be assumed uniform-density, so a volumetric default is
## a useful starting guess; a sword may not. Longer blades are made thinner and
## better distally tapered precisely so they stay wieldable, so generating
## mass from length would quietly invent a crowbar. Mass is a measured fact
## about a real object (PHYS-005).
##
## The weapon is the object only. How a particular body carries it — the hilt
## track — is that pairing's `WeaponHandlingProfile` (`HandlingCatalog`).
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md


## The weapon as held at `grip_radius` — the wielder's
## `FighterDefinition.grip_radius`, where the pommel origin sits. Reach is grip
## plus blade; the sword contributes only its blade.
static func of(id: StringName, grip_radius: float = PhysicalBaseline.GRIP_RADIUS_M) -> WeaponDefinition:
	if id == ContentIds.WEAPON_BASTARD_SWORD:
		return bastard_sword_at(1.0, PhysicalBaseline.SWORD_MASS_KG, grip_radius)
	## Fail closed, as with fighters: no substitute, no match.
	return null


## The baseline sword (COMBAT §3): 1.22 m overall, ~0.97 m of blade, 1.6 kg,
## in the baseline duelist's hands.
static func bastard_sword() -> WeaponDefinition:
	return bastard_sword_at(1.0, PhysicalBaseline.SWORD_MASS_KG)


## The same sword at an arbitrary length and mass. Both are required: a longer
## blade is not automatically a heavier one, and pretending otherwise is how
## scaled content stops being believable.
static func bastard_sword_at(length_scale: float, mass: float, grip_radius: float = PhysicalBaseline.GRIP_RADIUS_M) -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.id = ContentIds.WEAPON_BASTARD_SWORD
	## The origin is the pommel at the wielder's grip, so the blade starts at
	## `grip_radius` and `tip_radius` is grip plus blade.
	weapon.hilt_radius = grip_radius
	weapon.tip_radius = grip_radius + PhysicalBaseline.sword_blade(length_scale)
	weapon.blade_radius = 0.022 * length_scale
	## The crossguard sits where the model has it relative to the blade's
	## start, and its bar scales with the sword (GUARD-CONTACT-001).
	weapon.guard_centre_radius = grip_radius - (PhysicalBaseline.GRIP_RADIUS_M - PhysicalBaseline.GUARD_CENTRE_M)
	weapon.guard_half_span = PhysicalBaseline.GUARD_HALF_SPAN_M * length_scale
	weapon.guard_radius = PhysicalBaseline.GUARD_DEPTH_M * 0.5 * length_scale
	## The handle collides as itself — the model's grip, scaled with the
	## sword. The hands around it are presentation, not collision.
	weapon.handle_radius = PhysicalBaseline.GRIP_HALF_WIDTH_M * length_scale
	## The shipped sword's mass, balance point and `I = k·m·L²` (PHYS-006) are
	## DERIVED from its authored mass distribution (EMERGENT-COMBAT-001) — one
	## source of physical truth, nothing hand-copied beside it. The whole mass
	## is a uniform blade segment from the hilt to the tip (the handle's mass
	## folded in): its mass starts 0.25 m out rather than at the origin, so `k`
	## comes out ~0.4156 (a rod about its own end is 1/3) and
	## `moment_of_inertia()` ~0.99 kg·m², the scale the torques below are
	## authored against. A tip-heavy or pommel-weighted design is authored as
	## its own distribution (a greatsword would `add_point()` its pommel).
	##
	## Other lengths, masses and grips are test-only scaling fixtures
	## (SCALING, IMPACT), never shipped content: they keep the reference
	## distribution's shape coefficient and a mid-blade balance point, so a
	## scaling proof isolates length and mass (CONTENT-002). A variant that
	## ships MUST author its own profile and derive from it.
	var profile := reference_mass_profile()
	weapon.inertia_coefficient = profile.inertia_coefficient(PhysicalBaseline.SWORD_LENGTH_M)
	weapon.mass = mass
	weapon.center_of_mass_radius = (weapon.hilt_radius + weapon.tip_radius) * 0.5
	var is_reference := is_equal_approx(length_scale, 1.0) and is_equal_approx(mass, PhysicalBaseline.SWORD_MASS_KG) and is_equal_approx(grip_radius, PhysicalBaseline.GRIP_RADIUS_M)
	if is_reference:
		weapon.apply_mass_profile(profile)
	## The handle's two grip stations, from the pommel.
	weapon.offhand_grip_radius = PhysicalBaseline.GRIP_OFFHAND_M
	weapon.dominant_grip_radius = PhysicalBaseline.GRIP_DOMINANT_M
	weapon.guard_angle = PhysicalBaseline.GUARD_ANGLE_RAD
	weapon.guard_limit = PhysicalBaseline.GUARD_LIMIT_RAD
	weapon.min_arc = PhysicalBaseline.TAP_ARC_RAD
	weapon.max_arc = PI
	_semantics(weapon)
	weapon.precompute()
	return weapon


## The shipped bastard sword's mass distribution: 1.6 kg as a uniform blade
## from the guard (`GRIP_RADIUS_M` from the pommel) to the point.
static func reference_mass_profile() -> WeaponMassProfile:
	return WeaponMassProfile.new().add_segment(PhysicalBaseline.GRIP_RADIUS_M, PhysicalBaseline.SWORD_LENGTH_M, PhysicalBaseline.SWORD_MASS_KG)


## How the sword *fights*: the motor torques, the charge tempo, recovery, and
## contact behaviour. These are authored against the baseline's inertia and do
## not scale, because scaling them as well as the geometry they already act on
## would count the size twice (COMBAT §34). A longer blade is harder to swing
## because `I` grew, and that is the only reason it should be.
static func _semantics(weapon: WeaponDefinition) -> void:
	## 2° either side of centre; wide enough to swallow numerical noise,
	## narrow enough that the player never perceives a dead band.
	weapon.side_deadzone = PI / 90.0
	weapon.preparation_floor = 0.55
	weapon.tap_threshold_ticks = 7
	weapon.buffer_ticks = WeaponDefinition.BUFFER_TICKS_LIMIT
	## Target swing speeds, linear in charge: a tap 10.5, a half charge 14.25,
	## a full charge 18 rad/s (rules 42; was 20). Fast enough that a committed
	## cut is dangerous, slow enough that a side-step and the opening it leaves
	## can be seen. The curve is never tuned; only the 18-vs-20 endpoint is an
	## open calibration question for the gameplay camera.
	weapon.swing_speed_tap = 10.5
	weapon.swing_speed_full = 18.0
	## Torques, not accelerations: `α = τ / I`. A tap is driven hard and
	## stopped harder; a full swing is driven harder still but is far more
	## reluctant to be arrested, which is where its positional debt comes from.
	weapon.swing_torque_tap = 128.7
	weapon.swing_torque_full = 148.5
	weapon.brake_torque_tap = 217.8
	weapon.brake_torque_full = 148.5
	## Charge is bought in degrees of wind-back, so wind-back speed *is* the
	## charge tempo: 90° of earned travel at 1.8 rad/s takes ~0.9 s, which is
	## how long a full charge has always been meant to feel.
	weapon.windup_speed = 1.8
	weapon.windup_torque = 59.4
	weapon.hold_torque = 39.6
	weapon.control_speed = 1.2
	weapon.tap_commitment = 0.4
	weapon.restitution = 0.35
	## The closing speed below which the old scripted bind used to start: a
	## blade contact that slow is resting, not an impact, so it does not bounce.
	weapon.restitution_threshold_speed = 1.4
	weapon.reference_closing_speed = 10.5
	## Cut efficiency along the blade: what a rigid sword's physics leaves out
	## — vibration and a poor bite near the hilt and at the very point — as a
	## loss only, never above 1. Its peak is the sword's own centre of
	## percussion about the hands (`ContactMechanics.percussion_fraction`,
	## ~0.65 for this blade), derived from its mass distribution rather than
	## authored, so a heavier point moves the sweet spot by itself. The energy
	## a cut carries is the contact's; this only says how cleanly it bites.
	weapon.efficiency_fractions = PackedFloat64Array([0.0, 0.35, ContactMechanics.percussion_fraction(weapon), 1.0])
	weapon.efficiency_values = PackedFloat64Array([0.35, 0.75, 1.0, 0.8])
	weapon.edge_floor = 0.3
	## Stagger needs real momentum behind it: a 9 m/s cut on a committed
	## opponent crosses this, a 7 m/s cut on a composed one does not.
	weapon.stagger_impulse = 0.9
	weapon.stagger_base_ticks = 9
	weapon.stagger_scale_ticks = 18.0
	## Emergent thrust (COMBAT-010). The bastard sword supports thrusts: a
	## qualifying point-first contact is lethal. The tip region is the final
	## 5% of the blade — a deliberate point entry, not a half-blade glance.
	weapon.supports_thrust = true
	weapon.tip_region_start = 0.95
	weapon.thrust_efficiency = 1.0
