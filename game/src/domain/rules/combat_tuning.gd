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
## Quality derives from *severity*, so the domain is quadratic in closing
## speed (PHYS-004).
var damage_qualities: PackedFloat64Array = PackedFloat64Array()
var damage_values: PackedFloat64Array = PackedFloat64Array()
## Ceiling on normalized severity, past which extra energy buys nothing.
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

## Structural coupling (COMBAT §36, PHYS-002). Plant quality erodes with
## speed, acceleration debt and body rotation; coupling blends it with how
## coherently the body is driving through the strike, bounded below so moving
## swordplay stays viable.
var plant_speed_weight: float = 0.0
var plant_accel_weight: float = 0.0
var plant_turn_weight: float = 0.0
var coupling_coherence_share: float = 0.0
var coupling_floor: float = 0.0
## Body mass that fully coupled structure puts behind a strike. Deliberately
## far below the fighter's actual mass: a sword strike couples a fraction of
## the body, never all of it.
var body_contribution_mass: float = 0.0

## Bound on the chronological contact loop. Exhausting it is pathological
## geometry, not normal play, and is reported rather than ignored.
var max_contacts_per_tick: int = 0
## Hysteresis: touching parts must come this much further apart than the touch
## distance before they count as separated and can strike again.
var separation_epsilon: float = 0.0
## Hard escape bound on consecutive ticks a pair may spend bound.
var bind_escape_ticks: int = 0

## Mass a fighter brings to resisting displacement is their own mass scaled
## between this floor (mid-scramble) and 1 (fully planted).
var resist_plant_floor: float = 0.0

## Effective striking mass (COMBAT §51) is measured against this reference.
var reference_strike_mass: float = 0.0
## A solid reference impact, for consumers that need impulse and severity as
## bounded signals rather than raw kg·m/s and joules.
var reference_impulse: float = 0.0
var reference_severity: float = 0.0

## Blade-on-blade (COMBAT §40): effective inertia = I × (floor + (1 - floor) × C_s) × (1 + bonus × K).
var blade_inertia_coupling_floor: float = 0.0
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

## Stamina tuning (STAMINA-001): ceiling, shock, exertion, recovery.
## `stamina_health_share` is the fraction of the ceiling that tracks health:
## at full health the ceiling is `base_stamina`; at zero health it falls to
## `base_stamina × (1 - stamina_health_share)`.
var stamina_health_share: float = 0.0
var stamina_shock_rate: float = 0.0
var stamina_exertion_rate: float = 0.0
var stamina_recovery_rate: float = 0.0
var stamina_recovery_effort_ceiling: float = 0.0

## Stamina normalization (STAMINA-001): reference work per tick (joules) for
## each motor channel. Represents the baseline fighter/weapon at max-power
## output for one tick. Normalizes raw joules into a [0, ∞) effort signal
## where 1.0 = a single tick at full motor power.
var stamina_move_reference_work: float = 0.0
var stamina_turn_reference_work: float = 0.0
var stamina_weapon_reference_work: float = 0.0

## Stamina work-type weights. Positive motor work (driving) costs the most
## stamina; braking costs less (deceleration is still effort but less
## metabolically expensive); utilization at near-zero velocity (static hold /
## isometric) costs the least. All >= 0.
var stamina_drive_weight: float = 0.0
var stamina_brake_weight: float = 0.0
var stamina_hold_weight: float = 0.0

## Body-body collision (COMBAT-007). Fighters are circles; when they overlap
## or are about to overlap, the contact loop resolves an inverse-mass impulse
## so a heavier fighter is barely displaced while a lighter one absorbs the
## collision. Restitution is deliberately low — bodies absorb, they don't bounce.
var body_restitution: float = 0.0
## Coulomb friction coefficient for body-body tangential contact (PHYS-005).
## Bounded: tangential impulse ≤ friction × normal impulse. Two fighters
## sliding past each other lose tangential speed proportionally; the bound
## prevents a glancing bump from halting all lateral motion.
var body_friction: float = 0.0

## Gap threshold beyond which a CONTACTING body pair transitions back to
## SEPARATED (PHYS-009). Bodies must genuinely part before contact can
## re-arm. Reuses the same hysteresis philosophy as blade separation.
var body_contact_separation_epsilon: float = 0.0

## Sword-body bilateral contact (PHYS-010). Very low restitution — this is
## sword-into-human-body, not steel-on-steel. Highly inelastic.
var sword_body_restitution: float = 0.0
## Fraction of the full rigid blocking impulse applied on lethal point entry
## before releasing the nonpenetration constraint. The blade transfers this
## much momentum bilaterally, then continues through.
var penetration_resistance_fraction: float = 0.0

## Point-strike classification (COMBAT-010, COMBAT-011). A body contact
## becomes a point strike when the tip region makes contact along a
## sufficiently axial, well-incided trajectory with enough physical severity.
var point_strike_alignment: float = 0.0
var point_strike_incidence: float = 0.0
var point_strike_severity: float = 0.0
## Contacts below this quality are GRAZE rather than SLASH.
var graze_quality: float = 0.0
## Minimum thrust alignment between burst direction and sword axis for a
## POKE to qualify as a THRUST.
var thrust_burst_alignment: float = 0.0
## Minimum physical quality for a POKE to trigger the instant-kill lethality
## law (COMBAT-011). Below this threshold, a POKE uses the standard damage
## curve; at or above it, the POKE is lethal. Unprotected THRUSTs ignore this
## threshold — they are always lethal.
var poke_lethal_quality: float = 0.0
## Game-feel target pushback scaling (PHYS-008). Multiplies the physical
## impulse-derived target push for readability. The extra amplification is
## never reflected back into the blade reaction.
var body_push_feel_scale: float = 1.0

## Capability tuning: injury and fatigue penalties with a combined floor.
## `capability_injury_max` is the maximum penalty from injury alone (at zero
## health). `capability_fatigue_max` is the maximum penalty from fatigue alone
## (at zero stamina). `capability_floor` prevents the combined degradation
## from disabling input — a fighter at the floor is weak but responsive.
var capability_injury_max: float = 0.0
var capability_fatigue_max: float = 0.0
var capability_floor: float = 0.0


func is_valid() -> bool:
	if not _all_finite():
		return false
	return (
		exposure_max >= exposure_min
		and exposure_min > 0.0
		and damage_qualities.size() == damage_values.size()
		and not damage_qualities.is_empty()
		and max_physical_quality > 0.0
		and damage_scale >= 0.0
		and coupling_floor > 0.0
		and coupling_floor <= 1.0
		and coupling_coherence_share >= 0.0
		and coupling_coherence_share <= 1.0
		and body_contribution_mass > 0.0
		and resist_plant_floor > 0.0
		and resist_plant_floor <= 1.0
		and reference_strike_mass > 0.0
		and reference_impulse > 0.0
		and reference_severity > 0.0
		and blade_inertia_coupling_floor > 0.0
		and blade_strong_speed > blade_solid_speed
		and parry_margin_seconds > 0.0
		and substep_travel > 0.0
		and max_substeps > 0
		and max_contacts_per_tick > 0
		and separation_epsilon > 0.0
		and bind_escape_ticks > 0
		and stamina_health_share >= 0.0
		and stamina_health_share <= 1.0
		and stamina_shock_rate >= 0.0
		and stamina_exertion_rate >= 0.0
		and stamina_recovery_rate >= 0.0
		and stamina_recovery_effort_ceiling >= 0.0
		and stamina_move_reference_work > 0.0
		and stamina_turn_reference_work > 0.0
		and stamina_weapon_reference_work > 0.0
		and stamina_drive_weight >= 0.0
		and stamina_brake_weight >= 0.0
		and stamina_hold_weight >= 0.0
		and capability_injury_max >= 0.0
		and capability_injury_max <= 1.0
		and capability_fatigue_max >= 0.0
		and capability_fatigue_max <= 1.0
		and capability_floor > 0.0
		and capability_floor <= 1.0
		and body_restitution >= 0.0
		and body_restitution <= 1.0
		and body_friction >= 0.0
		and body_friction <= 1.0
		and body_contact_separation_epsilon > 0.0
		and sword_body_restitution >= 0.0
		and sword_body_restitution <= 1.0
		and penetration_resistance_fraction >= 0.0
		and penetration_resistance_fraction <= 1.0
		and point_strike_alignment >= 0.0
		and point_strike_alignment <= 1.0
		and point_strike_incidence >= 0.0
		and point_strike_incidence <= 1.0
		and point_strike_severity >= 0.0
		and graze_quality >= 0.0
		and thrust_burst_alignment >= 0.0
		and thrust_burst_alignment <= 1.0
		and poke_lethal_quality > 0.0
		and body_push_feel_scale > 0.0
	)


func damage_for(quality: float) -> float:
	return SimMath.piecewise(damage_qualities, damage_values, quality) * damage_scale


func _all_finite() -> bool:
	return (
		is_finite(exposure_base) and is_finite(exposure_commit)
		and is_finite(exposure_balance) and is_finite(exposure_flank)
		and is_finite(exposure_charging) and is_finite(exposure_overswing)
		and is_finite(exposure_recovery) and is_finite(exposure_stagger)
		and is_finite(exposure_min) and is_finite(exposure_max)
		and is_finite(max_physical_quality) and is_finite(damage_scale)
		and is_finite(critical_quality) and is_finite(critical_blade_min)
		and is_finite(critical_blade_max) and is_finite(critical_alignment)
		and is_finite(critical_exposure)
		and is_finite(plant_speed_weight) and is_finite(plant_accel_weight)
		and is_finite(plant_turn_weight) and is_finite(coupling_coherence_share)
		and is_finite(coupling_floor) and is_finite(body_contribution_mass)
		and is_finite(separation_epsilon) and is_finite(resist_plant_floor)
		and is_finite(reference_strike_mass) and is_finite(reference_impulse)
		and is_finite(reference_severity) and is_finite(blade_inertia_coupling_floor)
		and is_finite(blade_inertia_commit_bonus) and is_finite(blade_solid_speed)
		and is_finite(blade_strong_speed) and is_finite(bind_break_distance)
		and is_finite(parry_margin_seconds) and is_finite(substep_travel)
		and is_finite(stamina_health_share) and is_finite(stamina_shock_rate)
		and is_finite(stamina_exertion_rate) and is_finite(stamina_recovery_rate)
		and is_finite(stamina_recovery_effort_ceiling)
		and is_finite(stamina_move_reference_work) and is_finite(stamina_turn_reference_work)
		and is_finite(stamina_weapon_reference_work)
		and is_finite(stamina_drive_weight) and is_finite(stamina_brake_weight)
		and is_finite(stamina_hold_weight) 		and is_finite(body_restitution)
		and is_finite(body_friction) and is_finite(body_contact_separation_epsilon)
		and is_finite(sword_body_restitution) and is_finite(penetration_resistance_fraction)
		and is_finite(point_strike_alignment)
		and is_finite(point_strike_incidence) and is_finite(point_strike_severity)
		and is_finite(graze_quality) and is_finite(thrust_burst_alignment)
		and is_finite(poke_lethal_quality) and is_finite(body_push_feel_scale)
		and is_finite(capability_injury_max) and is_finite(capability_fatigue_max)
		and is_finite(capability_floor)
	)
