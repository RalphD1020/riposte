class_name WeaponDefinition
extends RefCounted

## Immutable weapon geometry, motor, and contact semantics (COMBAT §70). The
## bastard sword is content; a greatsword or staff is another instance of this
## type, not new combat code. Every value is authored in content; defaults
## here are neutral. Units: meters, seconds, radians, kg.
##
## Angles are relative to the fighter's facing; positive is counter-clockwise
## (the fighter's left). The pivot is the fighter center.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

var id: StringName = &""

## Geometry. The blade segment spans hilt_radius → tip_radius from the pivot,
## which sits at the pommel, so `tip_radius` *is* the weapon's overall length
## and the effective rotational length. Geometry scales linearly with weapon
## size; it is never a function of mass (PHYS-005).
var hilt_radius: float = 0.0
var tip_radius: float = 0.0
var blade_radius: float = 0.0
## Mass is a **measured fact** about the object, authored directly. It is
## never generated from length at runtime: a longer sword is usually a thinner
## one, so a cubic rule would quietly invent a crowbar.
var mass: float = 0.0
## Mass-distribution coefficient for `I = k·m·L²` (PHYS-006). A uniform rod
## pivoting about its own end is 1/3; mass carried further out authors more,
## a pommel-weighted weapon less. Balance is content, not hard-wired geometry.
var inertia_coefficient: float = 0.0

## Guard. The canonical guards are ±guard_angle and |angle| never exceeds
## guard_limit, but ±guard_angle is a *reference*, not a resting position: the
## blade legitimately lives anywhere in its 2 × guard_limit coverage.
var guard_angle: float = 0.0
var guard_limit: float = 0.0
var min_arc: float = 0.0
var max_arc: float = 0.0
## Half-width of the centre band in which the committed side is not updated,
## so numerical noise at 0° cannot flip the next swing's direction.
var side_deadzone: float = 0.0
## Motor authority multiplier at zero readiness (blade at dead centre).
## Under-loaded cuts are quick but weak; this is how weak.
var readiness_floor: float = 0.0

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

## Recovery (COMBAT §56): base + commit×K + overswing + displacement + facing + balance.
var recovery_base_ticks: int = 0
var recovery_commit_ticks: float = 0.0
var recovery_overswing_ticks_per_rad: float = 0.0
var recovery_displacement_ticks_per_speed: float = 0.0
var recovery_facing_ticks_per_rad: float = 0.0
var recovery_balance_ticks: float = 0.0
var recovery_max_ticks: int = 0

## Blade contact (COMBAT §40, §45).
var restitution: float = 0.0
var deflect_fraction: float = 0.0
var bind_speed: float = 0.0
var bind_ticks: int = 0
var bind_loser_recovery_ticks: int = 0

## Body strike quality (COMBAT §34–§39, §51).
var reference_closing_speed: float = 0.0
## Blade efficiency by blade fraction (0 = hilt, 1 = tip).
var efficiency_fractions: PackedFloat64Array = PackedFloat64Array()
var efficiency_values: PackedFloat64Array = PackedFloat64Array()
var edge_floor: float = 0.0
## Stagger and swing arrest read *impulse*, not damage quality (PHYS-004).
## `stagger_impulse` is the stagger pressure a hit must carry; the arrest
## thresholds are normalized impulse.
var stagger_impulse: float = 0.0
var stagger_base_ticks: int = 0
var stagger_scale_ticks: float = 0.0
var swing_stop_base: float = 0.0
var swing_stop_scale: float = 0.0
var swing_end_impulse: float = 0.0

## Emergent thrust (COMBAT-010). A qualifying thrust is a contact
## classification — never an input, attack state, or animation — derived at
## contact from tip-first geometry, axial closing velocity, incidence quality,
## and physical severity. Only weapons that `supports_thrust` can produce a
## lethal-thrust classification; the other fields are ignored when false.
var supports_thrust: bool = false
## Normalized blade coordinate at which the tip region begins (0 = hilt,
## 1 = tip). A thrust candidate requires contact at or beyond this fraction.
var tip_region_start: float = 0.95
## Weapon-specific modifier on how efficiently this blade converts axial
## kinetic energy into a penetrating thrust. 1.0 is the baseline sword;
## a spear might be higher, a mace near zero.
var thrust_efficiency: float = 0.0


func is_valid() -> bool:
	return (
		tip_radius > hilt_radius
		and hilt_radius >= 0.0
		and blade_radius > 0.0
		and mass > 0.0
		and inertia_coefficient > 0.0
		and guard_limit > guard_angle
		and max_arc > min_arc
		and min_arc > 0.0
		and side_deadzone >= 0.0
		and side_deadzone < guard_angle
		and readiness_floor > 0.0
		and readiness_floor <= 1.0
		and tap_threshold_ticks > 0
		and buffer_ticks >= 0
		and buffer_ticks <= BUFFER_TICKS_LIMIT
		and swing_speed_tap > 0.0
		and swing_torque_tap > 0.0
		and brake_torque_full > 0.0
		and windup_speed > 0.0
		and windup_torque > 0.0
		and hold_torque > 0.0
		and reference_closing_speed > 0.0
		and stagger_impulse > 0.0
		and swing_end_impulse > 0.0
		and efficiency_fractions.size() == efficiency_values.size()
		and not efficiency_fractions.is_empty()
		and tip_region_start > 0.0
		and tip_region_start <= 1.0
		and thrust_efficiency >= 0.0
	)


## Overall length from the pivot, which is also the effective rotational
## length in `I = k·m·L²`.
func length() -> float:
	return tip_radius


func blade_length() -> float:
	return tip_radius - hilt_radius


## Precompute hook for immutable definitions. Currently a no-op: the public
## API always computes fresh because test-time mutation must remain correct.
## Catalogs call this after construction so the callsite exists when a future
## hot-loop inline path needs it.
func precompute() -> void:
	pass


## Moment of inertia about the fighter's pivot: **`I = k · m · L²`**
## (PHYS-006). Length enters squared and mass linearly, which is why a longer
## weapon punishes far harder than a heavier one of the same length.
##
## This is the one place the weapon's resistance to being turned is defined.
## The motor divides torque by it, and blade contact divides impulse by it, so
## a heavier or longer blade is harder both to swing and to displace — for
## free, with no second set of authored accelerations to keep in sync.
func moment_of_inertia() -> float:
	return inertia_coefficient * mass * tip_radius * tip_radius


## Preparation quality of a blade sitting at `angle`, saturating at the
## canonical guard. Under-loaded (|angle| < guard_angle) scales down; anything
## at or beyond baseline is fully prepared. This gates achievable angular
## velocity only — it is never a damage multiplier.
func readiness(angle: float) -> float:
	return SimMath.clamp01(absf(angle) / guard_angle)


## Nominal top angular speed for a charge, before preparation is accounted for.
func swing_speed(charge: float) -> float:
	return SimMath.mix(swing_speed_tap, swing_speed_full, charge)


## The top angular speed a swing launched at `readiness_value` can actually
## reach. The one definition of a swing's ceiling: the motor accelerates
## toward it and contact resolution measures deflection against it, so the two
## can never disagree about what a swing was capable of.
func achievable_swing_speed(charge: float, readiness_value: float) -> float:
	return swing_speed(charge) * SimMath.mix(readiness_floor, 1.0, SimMath.clamp01(readiness_value))


## Angular acceleration available to drive a swing, `α = τ / I`.
##
## `drive` is the wielder's `weapon_torque_scale`: the same sword in a
## stronger arm accelerates faster because more torque is applied to it, not
## because the object changed (COMBAT §27). Every motor accel takes it, so a
## wielder can never affect one phase of a swing and not another.
func swing_accel(charge: float, drive: float) -> float:
	return drive * SimMath.mix(swing_torque_tap, swing_torque_full, charge) / moment_of_inertia()


## Angular acceleration available to arrest a swing.
func brake_accel(charge: float, drive: float) -> float:
	return drive * SimMath.mix(brake_torque_tap, brake_torque_full, charge) / moment_of_inertia()


## Angular acceleration available to wind the blade back.
func windup_accel(drive: float) -> float:
	return drive * windup_torque / moment_of_inertia()


## Angular acceleration that settles an idle or bound blade.
func hold_accel(drive: float) -> float:
	return drive * hold_torque / moment_of_inertia()


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
## forever; the physics never consults it.
func windback_limit_ticks(drive: float) -> int:
	var travel := (guard_limit + guard_limit) / windup_speed
	var ramp := windup_speed / windup_accel(drive)
	return ceili((travel + ramp) * float(SimulationTimebase.TICK_RATE))


func efficiency(blade_fraction: float) -> float:
	return SimMath.piecewise(efficiency_fractions, efficiency_values, blade_fraction)


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
