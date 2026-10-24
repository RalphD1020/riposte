class_name CombatTuning
extends RefCounted

## Weapon-independent combat semantics: the exposure reading, damage curve, criticals,
## recovery floor, condition floors, and swept-collision resolution. Every value is authored in
## content; defaults here are neutral.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

## Exposure is a reading, never a damage factor (v36, `ExposureModel`): how
## far behind the opponent a fighter is in time-to-threat. A margin of this
## many seconds reads as fully exposed (or fully safe the other way round).
var exposure_window_seconds: float = 0.0

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

## Critical classification (COMBAT §53): convergence of physical quality,
## blade region and edge alignment — never chance, never exposure.
var critical_quality: float = 0.0
var critical_blade_min: float = 0.0
var critical_blade_max: float = 0.0
var critical_alignment: float = 0.0

## Structural coupling (COMBAT §36, PHYS-002). Plant quality erodes with
## speed, acceleration debt and body rotation; coupling blends it with how
## coherently the body is driving through the strike, bounded below so moving
## swordplay stays viable.
var plant_speed_weight: float = 0.0
var plant_accel_weight: float = 0.0
var plant_turn_weight: float = 0.0
var coupling_coherence_share: float = 0.0
var coupling_floor: float = 0.0

## Bound on the chronological contact loop. Exhausting it is pathological
## geometry, not normal play, and is reported rather than ignored.
var max_contacts_per_tick: int = 0
## Hysteresis: touching parts must come this much further apart than the touch
## distance before they count as separated and can strike again.
var separation_epsilon: float = 0.0
## Persistent contact (RIGID-CONTACT-001): overlap a held contact may keep
## (m) — invisible, millimetres — and the most one position correction may
## move it out in a tick (m), so a deep overlap is worked out over ticks
## rather than teleported.
var contact_slop: float = 0.0
var contact_max_correction: float = 0.0
## Coulomb friction and restitution are per material pair, not tuning
## (CONTACT-MATERIAL-001): `DuelRules.materials`.

## A solid reference impact, for consumers that need impulse and severity as
## bounded signals rather than raw kg·m/s and joules. The injury calibration:
## named physical constants authored in the rules content with explicit units
## (`StandardDuelRules.REFERENCE_CUT_ENERGY_J` and friends), measured once on
## the reference strike (`ContactMechanics.reference_impulse` is its witness on
## the current mechanics), so changing the sword never renormalizes damage.
var reference_impulse: float = 0.0
var reference_severity: float = 0.0
## The same for a point driven straight in (`ContactMechanics.reference_thrust_severity`).
var reference_thrust_severity: float = 0.0
## A strong clash's dissipated energy (`ContactMechanics.reference_clash_energy`).
var reference_clash_energy: float = 0.0

## Closing speed (m/s) that separates light / solid / strong blade contact.
var blade_solid_speed: float = 0.0
var blade_strong_speed: float = 0.0

## Recovery (RECOVERY-001): the universal floor — every recovery, for every
## attack and every weapon, lasts at least this many ticks (hand and control
## re-acquisition, mirrored). Past it, recovery ends only when the blade is
## physically back under control (`WeaponDefinition.control_speed`). No other
## term: overswing, facing error, displacement and balance already cost real
## time through the brake torque, the turn torque and movement authority.
var recovery_min_ticks: int = 0

## Swept collision substeps: point travel per substep stays below this.
var substep_travel: float = 0.0
var max_substeps: int = 0

## Body-body collision (COMBAT-007, PHYS-005): the bodies' material pair gives
## the restitution and the Coulomb bound.

## Gap threshold beyond which a CONTACTING body pair transitions back to
## SEPARATED (PHYS-009). Bodies must genuinely part before contact can
## re-arm. Reuses the same hysteresis philosophy as blade separation.
var body_contact_separation_epsilon: float = 0.0

## Sword-body bilateral contact (PHYS-010): the steel–flesh material pair.
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
## Condition (CONDITION-001): what damage leaves of a fighter's voluntary
## force, speed and tracking at zero health. Each scale runs linearly from 1 at
## full health down to its floor; the floors are in [0.5, 1] so the healthy
## identity is exact in floating point and injury can never disable input.
var condition_force_floor: float = 0.0
var condition_speed_floor: float = 0.0
var condition_tracking_floor: float = 0.0
## Stamina (STAMINA-004): what fatigue leaves of a fighter's voluntary force at
## zero stamina (force only; speed and tracking stay damage-only), so the
## product with `condition_force_floor` stays at or above 0.5; the stamina a
## dash start costs, once; each motor's cost per reference energy (one full
## acceleration to top speed, one full spin-up of the heading, one full-charge
## swing of the blade) and the share of braking work that counts; and the
## rate (per second) recovered while a tick's exertion stays at or under the
## recovery ceiling (stamina per second).
var stamina_force_floor: float = 0.0
var stamina_dash_cost: float = 0.0
var stamina_move_cost: float = 0.0
var stamina_turn_cost: float = 0.0
var stamina_swing_cost: float = 0.0
var stamina_brake_share: float = 0.0
var stamina_recovery_rate: float = 0.0
var stamina_recovery_effort_ceiling: float = 0.0
## Guard return (GUARD-RETURN-001). Natural frequency (rad/s) of the critically
## damped pose tracker that carries an idle blade to ±guard_angle. The implied
## acceleration is capped at the hold torque's α. The return is multiplied by
## `guard_steel_return_scale` while steel is persisted.
var guard_return_natural_frequency: float = 0.0
var guard_steel_return_scale: float = 0.0
## Impact authority (IMPACT-AUTHORITY-001). Episodes compound by
## `|Δθ̇| / (|Δθ̇| + ω_full)` and never fall below this share of the return.
var impact_authority_floor: float = 0.0
## Soft guard limit (GUARD-LIMIT-SOFT-001). Width (rad) of the restoring zone
## inside the hard stop. `guard_limit_stiffness` is the share of this tick's
## wind-up acceleration reached at full penetration, so a sustained wind-up
## still arrives at the stop; `guard_limit_damping` (1/s) resists outward
## speed only. Their sum with one tick of damping stays below 1 so the
## discrete wind-up rests on the stop instead of being pushed back off it.
var guard_limit_zone: float = 0.0
var guard_limit_stiffness: float = 0.0
var guard_limit_damping: float = 0.0
## Directional commitment (DIRECTIONAL-COMMIT-001, RESPONSIVE-COMMITMENT-001):
## physical redirect debt — momentum plus the actuator effort still being
## committed over `commit_lookahead_seconds`, against the healthy braking —
## mapped smoothly as `t / (t + T)` against a reference time for the weapon
## and the root. Forward root debt compounds the weapon's at
## `commit_root_facing_weight`; retreat relieves it by at most
## `commit_retreat_relief`. Full facing commitment leaves the heading
## `commit_turn_torque_curve` of its turn torque and `commit_turn_speed_curve`
## of its turn-rate cap; after injury the final share never drops below the
## `*_floor` of healthy. Gameplay calibration, not forces.
var commit_lookahead_seconds: float = 0.0
var commit_weapon_reference_seconds: float = 0.0
var commit_root_reference_seconds: float = 0.0
var commit_root_facing_weight: float = 0.0
var commit_retreat_relief: float = 0.0
var commit_turn_torque_curve: float = 0.0
var commit_turn_speed_curve: float = 0.0
var commit_turn_torque_floor: float = 0.0
var commit_turn_speed_floor: float = 0.0
## A killed body (`FallenBodyState`, Phase 15). Collapse ticks before it lies,
## per cause: a cut drops it at once, a run-through holds it on the blade
## first. Lying, it slides against Coulomb ground friction
## `fallen_ground_friction` (deceleration μ·g; the turning resistance is that
## friction over a uniform rod, derived, never authored). The lying body's own
## shape is the fighter's (`FighterDefinition.lying_half_length` /
## `lying_radius`): a floor material is a rule, a body's length is not.
var fallen_settle_ticks_cut: int = 0
var fallen_settle_ticks_point: int = 0
var fallen_ground_friction: float = 0.0


func is_valid() -> bool:
	if not _all_finite():
		return false
	return (
		exposure_window_seconds > 0.0
		and fallen_settle_ticks_cut >= 0
		and fallen_settle_ticks_point >= 0
		and fallen_ground_friction > 0.0
		and damage_qualities.size() == damage_values.size()
		and not damage_qualities.is_empty()
		and max_physical_quality > 0.0
		and damage_scale >= 0.0
		and coupling_floor > 0.0
		and coupling_floor <= 1.0
		and coupling_coherence_share >= 0.0
		and coupling_coherence_share <= 1.0
		and reference_impulse > 0.0
		and reference_severity > 0.0
		and reference_thrust_severity > 0.0
		and reference_clash_energy > 0.0
		and blade_strong_speed > blade_solid_speed
		and recovery_min_ticks > 0
		and substep_travel > 0.0
		and max_substeps > 0
		and max_contacts_per_tick > 0
		and separation_epsilon > 0.0
		and contact_slop > 0.0
		and contact_max_correction > contact_slop
		and ArenaConstraints.BODY_CONTACT_REST_EPSILON < contact_slop
		and condition_force_floor >= 0.5
		and condition_force_floor <= 1.0
		and condition_speed_floor >= 0.5
		and condition_speed_floor <= 1.0
		and condition_tracking_floor >= 0.5
		and condition_tracking_floor <= 1.0
		and stamina_force_floor > 0.0
		and stamina_force_floor <= 1.0
		and condition_force_floor * stamina_force_floor >= 0.5
		and stamina_dash_cost >= 0.0
		and stamina_dash_cost <= 1.0
		and stamina_move_cost >= 0.0
		and stamina_turn_cost >= 0.0
		and stamina_swing_cost >= 0.0
		and stamina_brake_share >= 0.0
		and stamina_brake_share <= 1.0
		and stamina_recovery_rate > 0.0
		and stamina_recovery_effort_ceiling >= 0.0
		and guard_return_natural_frequency > 0.0
		and guard_steel_return_scale >= 0.0
		and guard_steel_return_scale <= 1.0
		and impact_authority_floor > 0.0
		and impact_authority_floor <= 1.0
		and guard_limit_zone > 0.0
		and guard_limit_stiffness > 0.0
		and guard_limit_stiffness < 1.0
		and guard_limit_damping >= 0.0
		and guard_limit_stiffness + guard_limit_damping * SimulationTimebase.TICK_SECONDS < 1.0
		and commit_weapon_reference_seconds > 0.0
		and commit_root_reference_seconds > 0.0
		and commit_lookahead_seconds >= 0.0
		and commit_root_facing_weight >= 0.0
		and commit_root_facing_weight <= 1.0
		and commit_retreat_relief >= 0.0
		and commit_retreat_relief <= 1.0
		and commit_turn_torque_floor > 0.0
		and commit_turn_torque_curve >= commit_turn_torque_floor
		and commit_turn_torque_curve <= 1.0
		and commit_turn_speed_floor > 0.0
		and commit_turn_speed_curve >= commit_turn_speed_floor
		and commit_turn_speed_curve <= 1.0
		and body_contact_separation_epsilon > 0.0
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
	)


func damage_for(quality: float) -> float:
	return SimMath.piecewise(damage_qualities, damage_values, quality) * damage_scale


func _all_finite() -> bool:
	return (
		is_finite(exposure_window_seconds)
		and is_finite(max_physical_quality) and is_finite(damage_scale)
		and is_finite(critical_quality) and is_finite(critical_blade_min)
		and is_finite(critical_blade_max) and is_finite(critical_alignment)
		and is_finite(plant_speed_weight) and is_finite(plant_accel_weight)
		and is_finite(plant_turn_weight) and is_finite(coupling_coherence_share)
		and is_finite(coupling_floor)
		and is_finite(separation_epsilon)
		and is_finite(contact_slop) and is_finite(contact_max_correction)
		and is_finite(reference_impulse) and is_finite(reference_thrust_severity)
		and is_finite(reference_severity) and is_finite(blade_solid_speed)
		and is_finite(blade_strong_speed)
		and is_finite(substep_travel)
		and is_finite(body_contact_separation_epsilon)
		and is_finite(penetration_resistance_fraction)
		and is_finite(point_strike_alignment)
		and is_finite(point_strike_incidence) and is_finite(point_strike_severity)
		and is_finite(graze_quality) and is_finite(thrust_burst_alignment)
		and is_finite(poke_lethal_quality)
		and is_finite(condition_force_floor) and is_finite(condition_speed_floor)
		and is_finite(condition_tracking_floor)
		and is_finite(stamina_force_floor) and is_finite(stamina_dash_cost)
		and is_finite(stamina_move_cost) and is_finite(stamina_turn_cost)
		and is_finite(stamina_swing_cost) and is_finite(stamina_brake_share)
		and is_finite(stamina_recovery_rate) and is_finite(stamina_recovery_effort_ceiling)
		and is_finite(guard_return_natural_frequency) and is_finite(guard_steel_return_scale)
		and is_finite(impact_authority_floor)
		and is_finite(guard_limit_zone) and is_finite(guard_limit_stiffness)
		and is_finite(guard_limit_damping)
		and is_finite(commit_weapon_reference_seconds) and is_finite(commit_root_reference_seconds)
		and is_finite(commit_lookahead_seconds) and is_finite(commit_root_facing_weight)
		and is_finite(commit_retreat_relief)
		and is_finite(commit_turn_torque_curve) and is_finite(commit_turn_speed_curve)
		and is_finite(commit_turn_torque_floor) and is_finite(commit_turn_speed_floor)
	)
