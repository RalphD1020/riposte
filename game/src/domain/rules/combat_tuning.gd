class_name CombatTuning
extends RefCounted

## Weapon-independent combat semantics: exposure, damage curve, criticals,
## parry margin, and swept-collision resolution. Every value is authored in
## content; defaults here are neutral.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

## Exposure (COMBAT §47): base + commitment + balance debt + flank + phase bonus.
var exposure_base: float = 0.0
var exposure_commit: float = 0.0
var exposure_balance: float = 0.0
var exposure_flank: float = 0.0
var exposure_charging: float = 0.0
var exposure_overswing: float = 0.0
var exposure_recovery: float = 0.0
var exposure_stagger: float = 0.0
var exposure_min: float = 0.0
var exposure_max: float = 0.0

## Nonlinear damage curve (COMBAT §52). Quality → damage, clamped at the ends.
var damage_qualities: PackedFloat64Array = PackedFloat64Array()
var damage_values: PackedFloat64Array = PackedFloat64Array()
var max_physical_quality: float = 0.0
## Multiplies every body-hit damage. 1 for duels; 0 makes contact physical
## but non-lethal (training).
var damage_scale: float = 0.0

## Critical classification (COMBAT §53): convergence, never chance.
var critical_quality: float = 0.0
var critical_blade_min: float = 0.0
var critical_blade_max: float = 0.0
var critical_alignment: float = 0.0
var critical_exposure: float = 0.0

## Effective striking mass (COMBAT §51) is weapon mass over this reference.
var reference_weapon_mass: float = 0.0

## Blade-on-blade (COMBAT §40): effective inertia = I × (floor + (1 - floor) × B) × (1 + bonus × K).
var blade_inertia_stability_floor: float = 0.0
var blade_inertia_commit_bonus: float = 0.0
## Closing speed (m/s) that separates light / solid / strong blade contact.
var blade_solid_speed: float = 0.0
var blade_strong_speed: float = 0.0
## A bind breaks once the blades drift this far beyond contact distance.
var bind_break_distance: float = 0.0

## Parry: defender threatens first by at least this margin after contact.
var parry_margin_seconds: float = 0.0

## Swept collision substeps: point travel per substep stays below this.
var substep_travel: float = 0.0
var max_substeps: int = 0


func is_valid() -> bool:
	return (
		exposure_max >= exposure_min
		and exposure_min > 0.0
		and damage_qualities.size() == damage_values.size()
		and not damage_qualities.is_empty()
		and max_physical_quality > 0.0
		and damage_scale >= 0.0
		and reference_weapon_mass > 0.0
		and blade_strong_speed > blade_solid_speed
		and substep_travel > 0.0
		and max_substeps > 0
	)


func damage_for(quality: float) -> float:
	return SimMath.piecewise(damage_qualities, damage_values, quality) * damage_scale
