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

## Geometry. The blade segment spans hilt_radius → tip_radius from the pivot.
var hilt_radius: float = 0.0
var tip_radius: float = 0.0
var blade_radius: float = 0.0
var mass: float = 0.0
var inertia: float = 0.0

## Guard. Rest side is ±guard_angle; |angle| never exceeds guard_limit.
var guard_angle: float = 0.0
var guard_limit: float = 0.0
var min_arc: float = 0.0
var max_arc: float = 0.0

## Input language. Tap = release before tap_threshold_ticks → exactly 0 charge.
var tap_threshold_ticks: int = 0
var charge_ticks: int = 0
var buffer_ticks: int = 0

## Motor (COMBAT §41). Speed/accel interpolate tap → full charge.
var swing_speed_tap: float = 0.0
var swing_speed_full: float = 0.0
var swing_accel_tap: float = 0.0
var swing_accel_full: float = 0.0
var brake_accel_tap: float = 0.0
var brake_accel_full: float = 0.0
var windup_speed: float = 0.0
var windup_gain: float = 0.0
var windup_accel: float = 0.0
var hold_damping: float = 0.0
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
var contact_cooldown_ticks: int = 0
var bind_speed: float = 0.0
var bind_ticks: int = 0
var bind_loser_recovery_ticks: int = 0

## Body strike quality (COMBAT §34–§39, §51).
var reference_closing_speed: float = 0.0
## Blade efficiency by blade fraction (0 = hilt, 1 = tip).
var efficiency_fractions: PackedFloat64Array = PackedFloat64Array()
var efficiency_values: PackedFloat64Array = PackedFloat64Array()
var edge_floor: float = 0.0
var knockback_speed: float = 0.0
var stagger_quality: float = 0.0
var stagger_base_ticks: int = 0
var stagger_scale_ticks: float = 0.0
var swing_stop_base: float = 0.0
var swing_stop_scale: float = 0.0
var swing_end_quality: float = 0.0


func is_valid() -> bool:
	return (
		tip_radius > hilt_radius
		and hilt_radius >= 0.0
		and blade_radius > 0.0
		and inertia > 0.0
		and guard_limit > guard_angle
		and max_arc >= min_arc
		and min_arc > 0.0
		and tap_threshold_ticks > 0
		and charge_ticks > 0
		and swing_speed_tap > 0.0
		and swing_accel_tap > 0.0
		and brake_accel_full > 0.0
		and hold_damping > 0.0
		and reference_closing_speed > 0.0
		and efficiency_fractions.size() == efficiency_values.size()
		and not efficiency_fractions.is_empty()
	)


func blade_length() -> float:
	return tip_radius - hilt_radius


func swing_speed(charge: float) -> float:
	return SimMath.mix(swing_speed_tap, swing_speed_full, charge)


func swing_accel(charge: float) -> float:
	return SimMath.mix(swing_accel_tap, swing_accel_full, charge)


func brake_accel(charge: float) -> float:
	return SimMath.mix(brake_accel_tap, brake_accel_full, charge)


## Arc = min_arc + (max_arc - min_arc) × charge (COMBAT §18).
func arc(charge: float) -> float:
	return SimMath.mix(min_arc, max_arc, charge)


## Extra retraction behind the guard at a given charge (COMBAT §17).
func windup_angle(charge: float) -> float:
	return (max_arc - min_arc) * charge


func efficiency(blade_fraction: float) -> float:
	return SimMath.piecewise(efficiency_fractions, efficiency_values, blade_fraction)
