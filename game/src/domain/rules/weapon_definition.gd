class_name WeaponDefinition
extends RefCounted

## Immutable weapon geometry, motor, and contact semantics (COMBAT §70). The
## bastard sword is content; a greatsword or staff is another instance of this
## type, not new combat code. Every value is authored in content; defaults
## here are neutral. Units: meters, seconds, radians, kg.
##
## Angles are relative to the fighter's facing; positive is counter-clockwise
## (the fighter's left). Blade radii are measured from the origin (pommel).
## How a wielder carries the weapon — the hilt track and its carriage — is not
## the object's: it is the fighter ↔ weapon pairing's
## (`WeaponHandlingProfile`, LOADOUT-001). Sword geometry is only ever built
## by `WeaponKinematics`.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

var id: StringName = &""

## Geometry. The sword is blade, crossguard and handle. The blade spans
## `blade_base_radius` (where it leaves the crossguard) → `tip_radius` from the
## origin, which sits at the pommel, so `tip_radius` *is* the weapon's overall
## length and the effective rotational length. Geometry scales linearly with
## weapon size; it is never a function of mass (PHYS-005).
##
## Only the blade is steel that blocks a sword (STEEL-TOPOLOGY-001); it is also
## the only part that wounds.
var blade_base_radius: float = 0.0
var tip_radius: float = 0.0
var blade_radius: float = 0.0
## The crossguard: a bar across the blade, centred `crossguard_centre_radius`
## from the origin, reaching `crossguard_half_span` either side of the blade,
## `crossguard_radius` thick. It is drawn and it carries its mass. As steel it
## is the guard root (`guard_root_apex_radius`): it stops an enemy blade that
## comes from its protected side and lets one from the grip side pass on to
## whatever it meets (GUARD-PROTECTION-001); it never touches another
## crossguard and is never hurt geometry. Zero span is a sword with no
## crossguard.
var crossguard_centre_radius: float = 0.0
var crossguard_half_span: float = 0.0
var crossguard_radius: float = 0.0
## The handle — pommel to crossguard centre, as thick as the sword's own grip.
## Grip-region hurt geometry, beside the hands on it; never steel. Zero makes
## the bare handle unhittable (the hands on it still are).
var handle_radius: float = 0.0

## Whether a blade-on-blade contact on this weapon's blade can be a successful
## defense of its wielder (DEFENSE-ROLE-001): a reading the PARRY
## classification takes, never physics — the contact is solved identically
## either way. Authored content.
var blade_protects: bool = true
## Whether a contact on the crossguard's protected side defends its wielder —
## the same reading as `blade_protects`, for the guard root. Authored content.
var crossguard_protects: bool = true
## Mass is a **measured fact** about the object, authored directly. It is
## never generated from length at runtime: a longer sword is usually a thinner
## one, so a cubic rule would quietly invent a crowbar.
var mass: float = 0.0
## Mass-distribution coefficient for `I = k·m·L²` (PHYS-006). A uniform rod
## pivoting about its own end is 1/3; mass carried further out authors more,
## a pommel-weighted weapon less. Balance is content, not hard-wired geometry.
var inertia_coefficient: float = 0.0
## The authored mass distribution these scalars are derived from
## (EMERGENT-COMBAT-001, `apply_mass_profile`). When present, `mass`,
## `center_of_mass_radius` and `inertia_coefficient` MUST agree with it to
## `MASS_PROFILE_TOLERANCE`, so nothing may overwrite a derived scalar after
## the fact and leave the distribution describing a different sword.
var mass_profile: WeaponMassProfile = null
## Derived scalars agree with their profile to rounding; the tolerance only
## absorbs floating-point summation order.
const MASS_PROFILE_TOLERANCE := 1.0e-9
## Distance (m) from the origin down the blade to the centre of mass (the
## balance point). Used with a moving origin, where the path's own motion adds
## `m·(|P′|² + 2·d_c·P′·perp(û))` to the weapon coordinate's inertia.
var center_of_mass_radius: float = 0.0
## Distance (m) from the origin down the blade to each grip station: the off
## hand on the pommel side, the dominant hand on the crossguard side, always in that
## order. Where the handle is held is the handle's geometry; how the arms then
## carry it is the handling's.
var offhand_grip_radius: float = 0.0
var dominant_grip_radius: float = 0.0

## Guard. The canonical guards are ±guard_angle and |angle| never exceeds
## guard_limit. ±guard_angle on the committed side is where the guard return
## settles an idle blade (GUARD-RETURN-001); a swing may still live anywhere
## in the 2 × guard_limit coverage.
var guard_angle: float = 0.0
var guard_limit: float = 0.0
var min_arc: float = 0.0
var max_arc: float = 0.0
## Half-width of the centre band in which the committed side is not updated,
## so numerical noise at 0° cannot flip the next swing's direction.
var side_deadzone: float = 0.0
## Motor authority multiplier at zero preparation (blade at dead centre).
## Under-loaded cuts are quick but weak; this is how weak.
var preparation_floor: float = 0.0

## Input language. Tap = release before tap_threshold_ticks → exactly 0 charge.
## There is no charge *duration*: charge is bought in degrees of earned
## wind-back, so holding longer only helps while the blade is still travelling.
var tap_threshold_ticks: int = 0
## How long a press that arrived too early is held before it is used. Kept
## very short deliberately: a long buffer fires an attack the player has
## already mentally abandoned, which reads as the game acting on its own.
var buffer_ticks: int = 0
## Four ticks is ~67 ms — enough to forgive a press that beat the recovery
## window by a frame or two, short enough that it never surprises anyone.
const BUFFER_TICKS_LIMIT := 4

## Motor (COMBAT §41). The fighter authors *torques*; angular accelerations
## are derived through `α = τ / I`, so a heavier or more tip-weighted weapon
## accelerates, brakes, and winds back more slowly for the same effort. Speeds
## stay authored: they are the arm's limit, not the blade's.
var swing_speed_tap: float = 0.0
var swing_speed_full: float = 0.0
var swing_torque_tap: float = 0.0
var swing_torque_full: float = 0.0
var brake_torque_tap: float = 0.0
var brake_torque_full: float = 0.0
var windup_speed: float = 0.0
var windup_torque: float = 0.0
var hold_torque: float = 0.0
## Max |angular speed| at which the sword is under control and may attack.
var control_speed: float = 0.0

## Commitment (COMBAT §20): K = (tap + (1 - tap) × C^1.25) × phase factor.
var tap_commitment: float = 0.0

## Recovery has no authored duration (RECOVERY-001, rules 44): it ends when the
## universal floor (`CombatTuning.recovery_min_ticks`) has passed and the blade
## is back under `control_speed`, arrested by this weapon's own brake torque.
## How long that takes is the weapon's physics, not a table.

## Blade contact (COMBAT §40, §45). `restitution` applies to a new contact
## closing at least `restitution_threshold_speed` (m/s); a slower one is
## inelastic, so slow and resting contacts never bounce (RIGID-CONTACT-002).
var restitution: float = 0.0
var restitution_threshold_speed: float = 0.0

## Body strike quality (COMBAT §34–§39, §51).
var reference_closing_speed: float = 0.0
## Blade efficiency by blade fraction (0 = crossguard, 1 = tip).
var efficiency_fractions: PackedFloat64Array = PackedFloat64Array()
var efficiency_values: PackedFloat64Array = PackedFloat64Array()
var edge_floor: float = 0.0
## Stagger reads *impulse*, not damage quality (PHYS-004): `stagger_impulse`
## is the stagger pressure a hit must carry.
var stagger_impulse: float = 0.0
var stagger_base_ticks: int = 0
var stagger_scale_ticks: float = 0.0

## Emergent thrust (COMBAT-010). A qualifying thrust is a contact
## classification — never an input, attack state, or animation — derived at
## contact from tip-first geometry, axial closing velocity, incidence quality,
## and physical severity. Only weapons that `supports_thrust` can produce a
## lethal-thrust classification; the other fields are ignored when false.
var supports_thrust: bool = false
## Normalized blade coordinate at which the tip region begins (0 = crossguard,
## 1 = tip). A thrust candidate requires contact at or beyond this fraction.
var tip_region_start: float = 0.95
## Weapon-specific modifier on how efficiently this blade converts axial
## kinetic energy into a penetrating thrust. 1.0 is the baseline sword;
## a spear might be higher, a mace near zero.
var thrust_efficiency: float = 0.0


func is_valid() -> bool:
	return (
		tip_radius > blade_base_radius
		and blade_base_radius >= 0.0
		and blade_radius > 0.0
		and crossguard_half_span >= 0.0
		and handle_radius >= 0.0
		and (crossguard_half_span == 0.0 or (crossguard_radius > 0.0 and crossguard_centre_radius > dominant_grip_radius and crossguard_centre_radius <= blade_base_radius))
		and mass > 0.0
		and inertia_coefficient > 0.0
		and center_of_mass_radius > 0.0
		and center_of_mass_radius < tip_radius
		and offhand_grip_radius >= 0.0
		and offhand_grip_radius < dominant_grip_radius
		and dominant_grip_radius < blade_base_radius
		and guard_limit > guard_angle
		and max_arc > min_arc
		and min_arc > 0.0
		and side_deadzone >= 0.0
		and side_deadzone < guard_angle
		and preparation_floor > 0.0
		and preparation_floor <= 1.0
		and tap_threshold_ticks > 0
		and buffer_ticks >= 0
		and buffer_ticks <= BUFFER_TICKS_LIMIT
		and swing_speed_tap > 0.0
		and swing_torque_tap > 0.0
		and brake_torque_full > 0.0
		and windup_speed > 0.0
		and windup_torque > 0.0
		and hold_torque > 0.0
		and restitution >= 0.0
		and restitution <= 1.0
		and restitution_threshold_speed > 0.0
		and reference_closing_speed > 0.0
		and stagger_impulse > 0.0
		and efficiency_fractions.size() == efficiency_values.size()
		and not efficiency_fractions.is_empty()
		and _efficiency_is_a_loss()
		and tip_region_start > 0.0
		and tip_region_start <= 1.0
		and thrust_efficiency >= 0.0
		and (mass_profile == null or (mass_profile.is_valid() and mass_profile.matches(mass, center_of_mass_radius, inertia_coefficient, tip_radius, MASS_PROFILE_TOLERANCE)))
	)


## Overall length from the origin, which is also the effective rotational
## length in `I = k·m·L²`.
func length() -> float:
	return tip_radius


func blade_length() -> float:
	return tip_radius - blade_base_radius


## The guard root's apex on the sword's axis (m from the origin): the convex
## steel of the guard is the rounded triangle from the crossguard's two ends to
## here, every edge at the bar's own thickness, so the corner between bar and
## blade is never a right angle a blade can wedge in (STEEL-TOPOLOGY-001). It
## rises only as far as keeps the root within the bar's own rounded edge: its
## surface stands out beyond the drawn bar and blade by at most
## `crossguard_radius` (GUARD-PROTECTION-001). The blade's own steel starts
## here. A sword with no crossguard has no root: its blade starts at its base.
func guard_root_apex_radius() -> float:
	if crossguard_half_span <= 0.0:
		return blade_base_radius
	return maxf(blade_base_radius, crossguard_centre_radius + crossguard_half_span * guard_root_rise())


## The guard root's rise above the bar as a share of its half-span: the most
## for which no point of its slanted edges stands farther than the bar's
## half-depth beyond both the drawn bar and the drawn blade. Along an edge the
## overhang is min(k·h·t − r_g, h·(1 − t) − r_b) + r_g, largest where the two
## agree, at k·(h − r_b + r_g)/(1 + k); setting that to r_g gives
## k = r_g / (h − r_b).
func guard_root_rise() -> float:
	return crossguard_radius / maxf(crossguard_half_span - blade_radius, crossguard_radius)


## Derive `mass`, `center_of_mass_radius` and `inertia_coefficient` from
## `profile` and keep it as their source. Geometry (`tip_radius`) must be set
## first: `k` is the profile's inertia about the origin over `m·L²`.
func apply_mass_profile(profile: WeaponMassProfile) -> void:
	mass_profile = profile
	mass = profile.total_mass()
	center_of_mass_radius = profile.center_of_mass_radius()
	inertia_coefficient = profile.inertia_coefficient(tip_radius)


## Precompute hook for immutable definitions. Currently a no-op: the public
## API always computes fresh because test-time mutation must remain correct.
## Catalogs call this after construction so the callsite exists when a future
## hot-loop inline path needs it.
func precompute() -> void:
	pass


## Restitution of a new blade contact closing at `closing` (m/s).
func restitution_at(closing: float) -> float:
	return restitution if closing >= restitution_threshold_speed else 0.0


## Distance (m) from the origin down the blade to the middle of the two hands:
## the point the sword turns about when it is held.
func hand_centre_radius() -> float:
	return (offhand_grip_radius + dominant_grip_radius) * 0.5


## Moment of inertia about the fighter's origin: **`I = k · m · L²`**
## (PHYS-006). Length enters squared and mass linearly, which is why a longer
## weapon punishes far harder than a heavier one of the same length.
##
## This is the sword's own moment about its origin, the first term of the
## weapon coordinate's inertia. The coordinate's whole inertia at a pose —
## the hilt track's motion and the hands on the grip included — is
## `WeaponKinematics.motor_inertia`, and the motor and every contact divide by
## that one quantity (UNIFIED-MASS-001), never by this alone.
func moment_of_inertia() -> float:
	return inertia_coefficient * mass * tip_radius * tip_radius


## Preparation quality of a blade sitting at `angle`, saturating at the
## canonical guard. Under-loaded (|angle| < guard_angle) scales down; anything
## at or beyond baseline is fully prepared. This gates achievable angular
## velocity only — it is never a damage multiplier, and it is not readiness:
## position says nothing about which way the blade is moving
## (THREAT-READINESS-001).
func preparation(angle: float) -> float:
	return SimMath.clamp01(absf(angle) / guard_angle)


## Nominal top angular speed for a charge, before preparation is accounted for.
func swing_speed(charge: float) -> float:
	return SimMath.mix(swing_speed_tap, swing_speed_full, charge)


## The top angular speed a swing launched at `preparation_value` can actually
## reach. The one definition of a swing's ceiling: the motor accelerates
## toward it and contact resolution measures deflection against it, so the two
## can never disagree about what a swing was capable of.
func achievable_swing_speed(charge: float, preparation_value: float) -> float:
	return swing_speed(charge) * SimMath.mix(preparation_floor, 1.0, SimMath.clamp01(preparation_value))


## Angular acceleration available to drive a swing, `α = τ / M_θ`.
##
## `drive` is the wielder's `weapon_torque_scale`: the same sword in a
## stronger arm accelerates faster because more torque is applied to it, not
## because the object changed (COMBAT §27). Every motor accel takes it, so a
## wielder can never affect one phase of a swing and not another. `inertia` is
## the weapon coordinate's inertia at the current pose
## (`WeaponKinematics.motor_inertia`) — the same one every contact uses
## (UNIFIED-MASS-001); there is no default, so no caller can quietly fall back
## to the sword's bare moment.
func swing_accel(charge: float, drive: float, inertia: float) -> float:
	return drive * SimMath.mix(swing_torque_tap, swing_torque_full, charge) / inertia


## Angular acceleration available to arrest a swing.
func brake_accel(charge: float, drive: float, inertia: float) -> float:
	return drive * SimMath.mix(brake_torque_tap, brake_torque_full, charge) / inertia


## Angular acceleration available to wind the blade back.
func windup_accel(drive: float, inertia: float) -> float:
	return drive * windup_torque / inertia


## Angular acceleration that settles an idle or bound blade.
func hold_accel(drive: float, inertia: float) -> float:
	return drive * hold_torque / inertia


## Arc = min_arc + (max_arc - min_arc) × charge (COMBAT §18). Equivalently
## min_arc + earned wind-back: charge is bought one-for-one in degrees.
func arc(charge: float) -> float:
	return SimMath.mix(min_arc, max_arc, charge)


## The wind-back that buys full charge, and so the full extra arc it adds.
func windback_span() -> float:
	return max_arc - min_arc


## The displacement a hold must *exceed* before it earns anything. Winding in
## from under-prepared is restoration, not preparation, so the baseline is the
## canonical guard; a blade already beyond it has to beat where it started, so
## a collision that flung it outward is never free charge.
func windback_baseline(hold_start_angle: float) -> float:
	return maxf(guard_angle, absf(hold_start_angle))


## Charge earned by `earned_windback` radians of outward travel.
func earned_charge(earned_windback: float) -> float:
	return SimMath.clamp01(earned_windback / windback_span())


## Upper bound on the ticks a hold can still be earning charge: the longest
## traverse the motor can make, plus the time to reach top speed. Automated
## controllers use it as a release valve so they cannot hold a pinned blade
## forever; the physics never consults it. `inertia` must bound the weapon
## coordinate's inertia from above (`WeaponKinematics.peak_motor_inertia`), so
## the ramp is never undercounted.
func windback_limit_ticks(drive: float, inertia: float) -> int:
	var travel := (guard_limit + guard_limit) / windup_speed
	var ramp := windup_speed / windup_accel(drive, inertia)
	return ceili((travel + ramp) * float(SimulationTimebase.TICK_RATE))


## Cut efficiency at a blade fraction: a loss the rigid model leaves out
## (vibration, a poor bite), in (0, 1] — it can never add energy
## (IMPACT-PHYSICS-001).
func efficiency(blade_fraction: float) -> float:
	return SimMath.piecewise(efficiency_fractions, efficiency_values, blade_fraction)


func _efficiency_is_a_loss() -> bool:
	for index in efficiency_values.size():
		if not (efficiency_values[index] > 0.0 and efficiency_values[index] <= 1.0):
			return false
		if index > 0 and not (efficiency_fractions[index] > efficiency_fractions[index - 1]):
			return false
	return true


## Normalized diagnostics against the baseline bastard sword (COMBAT §33).
## Designer-facing only; the simulation reads the absolute quantities, which
## already carry every effect of scale.
func length_ratio() -> float:
	return tip_radius / PhysicalBaseline.SWORD_LENGTH_M


func mass_ratio() -> float:
	return mass / PhysicalBaseline.SWORD_MASS_KG


## How much harder this weapon is to turn than the baseline sword. Worth
## seeing separately from length and mass, because inertia combines them
## non-linearly and is what the player actually feels.
func inertia_ratio() -> float:
	var baseline := (
		inertia_coefficient * PhysicalBaseline.SWORD_MASS_KG * PhysicalBaseline.SWORD_LENGTH_M * PhysicalBaseline.SWORD_LENGTH_M
	)
	return moment_of_inertia() / baseline
