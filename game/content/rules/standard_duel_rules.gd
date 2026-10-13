class_name StandardDuelRules
extends RefCounted

## MVP-0 rule content: the standard arena, best of five, and the combat
## constants that govern contact.
##
## A rule set *selects* its two combatants by id and tunes the arena around
## them; it does not author them. Fighters, weapons and their handling are
## content in their own right and live in their own catalogs (CONTENT-001),
## resolved into one `CombatantPhysicsSpec` per slot (`LoadoutCatalog`), which
## is what makes "same rules, different duelist" a one-line change instead of
## a fork of this file.
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md

## The injury calibration (IMPACT-PHYSICS-001, rules 42). Each has an explicit
## physical meaning and unit, seeded once from the reference strike the damage
## curve was calibrated against (rules 39: the baseline duelist's held blade,
## struck square at its centre of percussion from Long Guard at the weapon's
## reference_closing_speed), and then FROZEN. Because these are authored
## physical quantities — not "whatever the reference strike delivers today" —
## changing the hilt track, the inertia or the swing speed changes what a cut
## *delivers*, never what that much energy *does to a body*. Re-seeding them is
## a deliberate balance pass, never a side effect of a geometry change.
const REFERENCE_STAGGER_IMPULSE_NS := 14.1317560873646
const REFERENCE_CUT_ENERGY_J := 72.7078850694906
const REFERENCE_THRUST_ENERGY_J := 2204.118


static func create() -> DuelRules:
	return with_combatants(
		ContentIds.FIGHTER_DUELIST, LoadoutCatalog.default_weapon(ContentIds.FIGHTER_DUELIST),
		ContentIds.FIGHTER_DUELIST, LoadoutCatalog.default_weapon(ContentIds.FIGHTER_DUELIST)
	)


## The standard arena and format with any two loadouts. Each slot is compiled
## on its own, so the two combatants never share a definition by accident; an
## unresolvable loadout leaves the slot null and the rules invalid (fail
## closed).
static func with_combatants(fighter_0: StringName, weapon_0: StringName, fighter_1: StringName, weapon_1: StringName) -> DuelRules:
	var rules := DuelRules.new()
	rules.id = ContentIds.RULES_STANDARD_DUEL
	rules.version = 47
	rules.combatants = [LoadoutCatalog.compile(fighter_0, weapon_0), LoadoutCatalog.compile(fighter_1, weapon_1)]
	rules.combat = combat_tuning()
	rules.arena_id = ContentIds.ARENA_STANDARD
	rules.platform_radius = 8.27
	rules.edge_warning_inset = 0.27
	rules.spawn_offset = 2.5
	rules.rounds_to_win = 3
	rules.max_rounds = 9
	rules.intro_ticks = 72
	rules.result_ticks = 96
	rules.round_time_limit_ticks = 60 * SimulationTimebase.TICK_RATE
	rules.post_round_free_ticks = 150
	## The injury calibration is the authored physical constant (above);
	## `ContactMechanics.reference_*` on today's mechanics is only its witness,
	## which RULES holds within tolerance.
	rules.combat.reference_impulse = REFERENCE_STAGGER_IMPULSE_NS
	rules.combat.reference_severity = REFERENCE_CUT_ENERGY_J
	rules.combat.reference_thrust_severity = REFERENCE_THRUST_ENERGY_J
	## Presentation's clash scale stays derived: it describes a strong clash of
	## the reference loadout, not an injury. A reading's yardstick, measured
	## once on the reference duelist with his sword, so the same clash reads
	## the same whoever is fighting.
	var reference_spec := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	rules.combat.reference_clash_energy = ContactMechanics.reference_clash_energy(reference_spec, reference_spec, rules.combat)
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


static func combat_tuning() -> CombatTuning:
	var combat := CombatTuning.new()
	## Exposure is a reading of initiative (v36): a quarter second behind in
	## time-to-threat reads as fully open. It never scales damage.
	combat.exposure_window_seconds = 0.25
	## Damage is read from severity, which goes as `v²`, so the curve's domain
	## is wider and its low end flatter than a speed-linear one: a slow cut is
	## a scratch, and the interesting decisions live between a half-reference
	## and a double-reference strike.
	combat.damage_qualities = PackedFloat64Array([0.0, 0.1, 0.25, 0.45, 0.72, 1.0, 1.4, 1.8, 2.4])
	combat.damage_values = PackedFloat64Array([0.0, 2.0, 7.0, 20.0, 38.0, 56.0, 76.0, 95.0, 120.0])
	## Compressive at the top on purpose. Severity goes as `v²`, but injury
	## does not: a cut that already opens a fighter up is not improved by more
	## energy. Without this the quadratic would make heavy charges strictly
	## dominant and spacing, timing and punishment would stop paying.
	combat.max_physical_quality = 1.6
	combat.damage_scale = 1.0
	combat.critical_quality = 1.2
	combat.critical_blade_min = 0.45
	combat.critical_blade_max = 0.9
	combat.critical_alignment = 0.85
	## Structural coupling. Speed, acceleration debt and body rotation each
	## erode plant quality; the blend with movement coherence is deliberately
	## minority-weighted so footwork shapes a strike without dominating it.
	## The floor keeps lateral and retreating swordplay viable: planted is the
	## most controlled stance, not the universally optimal one.
	combat.plant_speed_weight = 0.25
	combat.plant_accel_weight = 0.4
	combat.plant_turn_weight = 0.2
	combat.coupling_coherence_share = 0.35
	combat.coupling_floor = 0.3
	## Bodies answer every contact with their real mass, and the held sword's
	## inertia is the sword plus the hands on the grip (rules v33). Plant and
	## commitment do not scale either. `reference_impulse` / `reference_severity`
	## are the frozen injury calibration set in `with_combatants()`.
	combat.blade_solid_speed = 3.0
	combat.blade_strong_speed = 8.0
	## Six ticks (100 ms) of hand and control re-acquisition after any attack;
	## everything longer is the blade's own momentum against its brake.
	combat.recovery_min_ticks = 6
	combat.substep_travel = 0.03
	combat.max_substeps = 48
	## Chronological contact loop. Six resolutions is far more than a duel
	## produces in a 16.7 ms tick, so hitting it means the geometry is wrong.
	combat.max_contacts_per_tick = 6
	## Twice the blade radius: blades must visibly part, not merely stop
	## overlapping, before they can clash again.
	combat.separation_epsilon = 0.044
	## Persistent contact (RIGID-CONTACT-001). Two millimetres is below what the
	## gameplay camera can show; four centimetres a tick bounds how fast a deep
	## overlap is worked out — more than one substep of travel, so a held
	## contact's drift is always cleared within the tick it happens.
	combat.contact_slop = 0.002
	combat.contact_max_correction = 0.04
	## Coulomb friction (BLADE-FRICTION-001), gameplay calibration seeds for
	## 7B.8: steel on steel grips enough that a press has consequence and a fast
	## glance still slides; a blade on cloth and flesh barely grips, so a cut
	## resting on a torso keeps sliding; a crossbar catches.
	combat.blade_friction = 0.2
	combat.blade_body_friction = 0.05
	combat.guard_friction = 0.4
	## Stamina (STAMINA-001). The ceiling tracks health: at full health the
	## fighter's pool is 100; at zero health a quarter of it has been lost to
	## injury. Shock is moderate — a reference cut costs ~22 stamina — so a
	## fighter can absorb a few hits before capability starts to erode, and
	## resting brings it back slowly.
	combat.stamina_health_share = 0.25
	combat.stamina_shock_rate = 0.4
	combat.stamina_exertion_rate = 5.0
	combat.stamina_recovery_rate = 8.0
	combat.stamina_recovery_effort_ceiling = 0.1
	## Stamina normalization: max power × tick for the baseline fighter/weapon.
	## Movement: LOCOMOTION_FORCE × max_speed × dt (1760 × 4.2 / 60).
	## Turn: turn_torque × turn_speed_max × dt (175 × 9.0 / 60).
	## Weapon: weapon_torque_scale × swing_torque_full × swing_speed_full × dt
	##         (1.0 × 148.5 × 20.0 / 60).
	combat.stamina_move_reference_work = 123.2
	combat.stamina_turn_reference_work = 26.25
	combat.stamina_weapon_reference_work = 49.5
	## Work-type weights: driving > braking > static hold (STAMINA-001).
	combat.stamina_drive_weight = 1.0
	combat.stamina_brake_weight = 0.5
	combat.stamina_hold_weight = 0.3
	## Condition (rules 45). Damage alone drives it, linearly: at zero health a
	## fighter keeps 70 % of their voluntary force, 85 % of their voluntary
	## speeds and 80 % of their tracking rate (0.85 / 0.925 / 0.90 at half
	## health). A mild actuator loss — wounded is vulnerable, never broken.
	combat.condition_force_floor = 0.70
	combat.condition_speed_floor = 0.85
	combat.condition_tracking_floor = 0.80
	## Directional commitment (rules 46, RESPONSIVE-COMMITMENT-001): redirect
	## debt — momentum plus the effort still being committed over the next
	## 0.10 s, against the fighter's healthy braking — read smoothly as
	## t / (t + T): 0.30 s of weapon debt or 0.35 s of root debt is half
	## committed. Forward root debt compounds the weapon's at 0.30; a retreat
	## gives back at most 0.25. Started soft so control is never felt as
	## taken: full commitment leaves 35 % of turn torque and 50 % of turn rate,
	## and with injury on top never less than 25 % / 40 % of healthy. Lower the
	## curves only if real-input bait play shows full forward pressure still
	## reacquires too well.
	combat.commit_lookahead_seconds = 0.10
	combat.commit_weapon_reference_seconds = 0.30
	combat.commit_root_reference_seconds = 0.35
	combat.commit_root_facing_weight = 0.30
	combat.commit_retreat_relief = 0.25
	combat.commit_turn_torque_curve = 0.35
	combat.commit_turn_speed_curve = 0.50
	combat.commit_turn_torque_floor = 0.25
	combat.commit_turn_speed_floor = 0.40	## Body-body collision: nearly inelastic so fighters don't bounce off each
	## other. Mass-aware inverse impulse handles the asymmetry (PHYS-005).
	combat.body_restitution = 0.05
	## Tangential friction. Bounded by Coulomb's law: a glancing shoulder bump
	## sheds some lateral speed but cannot halt a side-step. 0.3 keeps the
	## effect visible without making every bump a wall.
	combat.body_friction = 0.3
	## Body-body contact lifecycle (PHYS-009). Gap threshold for transitioning
	## from CONTACTING back to SEPARATED. Bodies must visibly part.
	combat.body_contact_separation_epsilon = 0.01
	## Sword-body bilateral contact (PHYS-010). Very low restitution — this is
	## sword-into-human-body, not steel-on-steel. Highly inelastic.
	combat.sword_body_restitution = 0.02
	## Fraction of the full rigid blocking impulse applied on lethal point entry
	## before releasing the nonpenetration constraint (PHYS-010).
	combat.penetration_resistance_fraction = 0.25
	## Point-strike classification (COMBAT-010). Thresholds are deliberately
	## permissive for pokes (walking into a point is common) and strict for
	## the burst-alignment needed to make one a thrust.
	combat.point_strike_alignment = 0.4
	combat.point_strike_incidence = 0.3
	combat.point_strike_severity = 0.15
	combat.graze_quality = 0.05
	## A burst must be within ~37° of the sword axis to qualify as a thrust.
	combat.thrust_burst_alignment = 0.8
	## POKE lethality threshold (COMBAT-011). Physical quality at or above this
	## value makes a POKE an instant kill. Tuned so walking-speed pokes are
	## survivable but an opponent dashing onto a held point is lethal.
	combat.poke_lethal_quality = 0.9
	## A killed body (Phase 15): a cut drops it in about the collapse's
	## presentation time (0.45 s); a run-through first holds it on the blade
	## through the striker's withdrawal (~0.6 s) and then collapses. Cloth and
	## leather on the arena floor slide at μ ≈ 0.5. The lying body's own shape
	## is each fighter's (`FighterDefinition.lying_half_length`).
	combat.fallen_settle_ticks_cut = 27
	combat.fallen_settle_ticks_point = 64
	combat.fallen_ground_friction = 0.5
	return combat
