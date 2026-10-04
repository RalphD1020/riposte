class_name StandardDuelRules
extends RefCounted

## MVP-0 rule content: the normalized duelist, the bastard sword, the standard
## arena, best of five. This file is the single place to tune MVP-0 numbers.
##
## Reference fighter 1.75 m tall with a 0.27 m footprint (COMBAT §4). Bastard
## sword 1.22 m overall with a ~0.97 m effective blade and ~1.6 kg (COMBAT §5).
## Tap threshold 7 ticks ≈ 117 ms; full charge 54 ticks ≈ 0.9 s past it.
##
## See also: /docs/concepts/combat.md


static func create() -> DuelRules:
	var rules := DuelRules.new()
	rules.id = ContentIds.RULES_STANDARD_DUEL
	rules.version = 1
	rules.fighter = duelist()
	rules.weapon = bastard_sword()
	rules.combat = combat_tuning()
	rules.arena_id = ContentIds.ARENA_STANDARD
	rules.arena_radius = 8.0
	rules.spawn_offset = 2.5
	rules.rounds_to_win = 3
	rules.max_rounds = 9
	rules.intro_ticks = 72
	rules.result_ticks = 96
	rules.round_time_limit_ticks = 60 * SimulationTimebase.TICK_RATE
	return rules


## Training: identical physics with non-lethal contact and one long round, so
## a first-time player can learn the verbs against a dummy (UX §57).
static func training() -> DuelRules:
	var rules := create()
	rules.id = ContentIds.RULES_TRAINING
	rules.combat.damage_scale = 0.0
	rules.rounds_to_win = 1
	rules.max_rounds = 1
	rules.round_time_limit_ticks = 180 * SimulationTimebase.TICK_RATE
	return rules


static func duelist() -> FighterDefinition:
	var fighter := FighterDefinition.new()
	fighter.id = ContentIds.FIGHTER_DUELIST
	fighter.body_radius = 0.27
	fighter.max_health = 100.0
	fighter.max_speed = 4.2
	fighter.move_accel = 22.0
	fighter.brake_accel = 30.0
	fighter.speed_forward = 1.0
	fighter.speed_lateral = 0.92
	fighter.speed_backward = 0.78
	fighter.turn_speed_max = 9.0
	fighter.turn_accel = 60.0
	fighter.track_gain = 14.0
	fighter.translation_commit_penalty = 0.32
	fighter.accel_commit_penalty = 0.66
	fighter.tracking_commit_penalty = 0.72
	fighter.overswing_tracking_penalty = 0.1
	fighter.min_tracking = 0.12
	fighter.counter_rotation_penalty = 0.5
	fighter.counter_rotation_reference_rate = 3.0
	fighter.stability_floor = 0.35
	fighter.stability_rate = 3.0
	fighter.stability_accel_weight = 0.35
	fighter.stability_turn_weight = 0.25
	fighter.stagger_translation = 0.55
	fighter.stagger_tracking = 0.35
	return fighter


static func bastard_sword() -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.id = ContentIds.WEAPON_BASTARD_SWORD
	weapon.hilt_radius = 0.25
	weapon.tip_radius = 1.22
	weapon.blade_radius = 0.022
	weapon.mass = 1.6
	weapon.inertia = 1.0
	weapon.guard_angle = PI * 0.25
	weapon.guard_limit = PI * 0.75
	weapon.min_arc = PI * 0.5
	weapon.max_arc = PI
	weapon.tap_threshold_ticks = 7
	weapon.charge_ticks = 54
	weapon.buffer_ticks = 6
	weapon.swing_speed_tap = 10.5
	weapon.swing_speed_full = 20.0
	weapon.swing_accel_tap = 130.0
	weapon.swing_accel_full = 150.0
	weapon.brake_accel_tap = 220.0
	weapon.brake_accel_full = 150.0
	weapon.windup_speed = 6.0
	weapon.windup_gain = 18.0
	weapon.windup_accel = 60.0
	weapon.hold_damping = 40.0
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
	weapon.contact_cooldown_ticks = 6
	weapon.bind_speed = 1.4
	weapon.bind_ticks = 20
	weapon.bind_loser_recovery_ticks = 10
	weapon.reference_closing_speed = 10.5
	weapon.efficiency_fractions = PackedFloat64Array([0.0, 0.35, 0.7, 1.0])
	weapon.efficiency_values = PackedFloat64Array([0.35, 0.75, 1.0, 0.8])
	weapon.edge_floor = 0.3
	weapon.knockback_speed = 3.0
	weapon.stagger_quality = 0.45
	weapon.stagger_base_ticks = 9
	weapon.stagger_scale_ticks = 18.0
	weapon.swing_stop_base = 0.25
	weapon.swing_stop_scale = 0.5
	weapon.swing_end_quality = 0.4
	return weapon


static func combat_tuning() -> CombatTuning:
	var combat := CombatTuning.new()
	combat.exposure_base = 0.9
	combat.exposure_commit = 0.3
	combat.exposure_balance = 0.2
	combat.exposure_flank = 0.3
	combat.exposure_charging = 0.05
	combat.exposure_overswing = 0.1
	combat.exposure_recovery = 0.1
	combat.exposure_stagger = 0.2
	combat.exposure_min = 0.75
	combat.exposure_max = 1.5
	combat.damage_qualities = PackedFloat64Array([0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0, 1.2])
	combat.damage_values = PackedFloat64Array([0.0, 4.0, 14.0, 30.0, 55.0, 85.0, 100.0, 120.0])
	combat.max_physical_quality = 1.25
	combat.damage_scale = 1.0
	combat.critical_quality = 0.7
	combat.critical_blade_min = 0.45
	combat.critical_blade_max = 0.9
	combat.critical_alignment = 0.85
	combat.critical_exposure = 1.0
	combat.reference_weapon_mass = 1.6
	combat.blade_inertia_stability_floor = 0.6
	combat.blade_inertia_commit_bonus = 0.5
	combat.blade_solid_speed = 3.0
	combat.blade_strong_speed = 8.0
	combat.bind_break_distance = 0.12
	combat.parry_margin_seconds = 0.08
	combat.substep_travel = 0.03
	combat.max_substeps = 48
	return combat
