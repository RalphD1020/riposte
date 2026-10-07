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
## See also: /docs/concepts/content.md, /docs/concepts/combat.md


static func of(id: StringName) -> WeaponDefinition:
	if id == ContentIds.WEAPON_BASTARD_SWORD:
		return bastard_sword()
	## Fail closed, as with fighters: no substitute, no match.
	return null


## The baseline sword (COMBAT §3): 1.22 m overall, ~0.97 m of blade, 1.6 kg.
static func bastard_sword() -> WeaponDefinition:
	return bastard_sword_at(1.0, PhysicalBaseline.SWORD_MASS_KG)


## The same sword at an arbitrary length and mass. Both are required: a longer
## blade is not automatically a heavier one, and pretending otherwise is how
## scaled content stops being believable.
static func bastard_sword_at(length_scale: float, mass: float) -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.id = ContentIds.WEAPON_BASTARD_SWORD
	## The pivot is the pommel, so `tip_radius` is the sword's overall length
	## and the grip occupies everything inboard of the blade.
	weapon.tip_radius = PhysicalBaseline.sword_length(length_scale)
	weapon.hilt_radius = weapon.tip_radius - PhysicalBaseline.sword_blade(length_scale)
	weapon.blade_radius = 0.022 * length_scale
	weapon.mass = mass
	## `I = k·m·L²` (PHYS-006). A rod pivoting about its own end is 1/3; this
	## blade's mass starts 0.25 m out at the hilt rather than at the pivot,
	## which puts it slightly further from the axis on average, so the uniform
	## case here is 0.4156. A distribution coefficient is a shape fact, so it
	## does not scale. At the baseline `moment_of_inertia()` works out to
	## ~0.99 kg·m², the scale the torques below are authored against.
	weapon.inertia_coefficient = 0.415636
	weapon.guard_angle = PhysicalBaseline.GUARD_ANGLE_RAD
	weapon.guard_limit = PhysicalBaseline.GUARD_LIMIT_RAD
	weapon.min_arc = PhysicalBaseline.TAP_ARC_RAD
	weapon.max_arc = PI
	_semantics(weapon)
	weapon.precompute()
	return weapon


## How the sword *fights*: the motor torques, the charge tempo, recovery, and
## contact behaviour. These are authored against the baseline's inertia and do
## not scale, because scaling them as well as the geometry they already act on
## would count the size twice (COMBAT §34). A longer blade is harder to swing
## because `I` grew, and that is the only reason it should be.
static func _semantics(weapon: WeaponDefinition) -> void:
	## 2° either side of centre; wide enough to swallow numerical noise,
	## narrow enough that the player never perceives a dead band.
	weapon.side_deadzone = PI / 90.0
	weapon.readiness_floor = 0.55
	weapon.tap_threshold_ticks = 7
	weapon.buffer_ticks = WeaponDefinition.BUFFER_TICKS_LIMIT
	weapon.swing_speed_tap = 10.5
	weapon.swing_speed_full = 20.0
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
	weapon.recovery_base_ticks = 6
	weapon.recovery_commit_ticks = 16.0
	weapon.recovery_overswing_ticks_per_rad = 8.0
	weapon.recovery_displacement_ticks_per_speed = 1.5
	weapon.recovery_facing_ticks_per_rad = 6.0
	weapon.recovery_balance_ticks = 8.0
	weapon.recovery_max_ticks = 48
	weapon.restitution = 0.35
	weapon.deflect_fraction = 0.4
	weapon.bind_speed = 1.4
	weapon.bind_ticks = 20
	weapon.bind_loser_recovery_ticks = 10
	weapon.reference_closing_speed = 10.5
	weapon.efficiency_fractions = PackedFloat64Array([0.0, 0.35, 0.7, 1.0])
	weapon.efficiency_values = PackedFloat64Array([0.35, 0.75, 1.0, 0.8])
	weapon.edge_floor = 0.3
	## Stagger needs real momentum behind it: a 9 m/s cut on a committed
	## opponent crosses this, a 7 m/s cut on a composed one does not.
	weapon.stagger_impulse = 0.9
	weapon.stagger_base_ticks = 9
	weapon.stagger_scale_ticks = 18.0
	weapon.swing_stop_base = 0.25
	weapon.swing_stop_scale = 0.5
	weapon.swing_end_impulse = 0.5
	## Emergent thrust (COMBAT-010). The bastard sword supports thrusts: a
	## qualifying point-first contact is lethal. The tip region is the final
	## 5% of the blade — a deliberate point entry, not a half-blade glance.
	weapon.supports_thrust = true
	weapon.tip_region_start = 0.95
	weapon.thrust_efficiency = 1.0
