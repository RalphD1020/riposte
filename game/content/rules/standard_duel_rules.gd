class_name StandardDuelRules
extends RefCounted

## MVP-0 rule content: the standard arena, best of five, and the combat
## constants that govern contact.
##
## A rule set *selects* its fighter and weapon by id and tunes the arena around
## them; it does not author them. The fighter and the sword are content in their
## own right and live in their own catalogs (CONTENT-001), which is what makes
## "same rules, different duelist" a one-line change instead of a fork of this
## file.
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md


static func create() -> DuelRules:
	var rules := DuelRules.new()
	rules.id = ContentIds.RULES_STANDARD_DUEL
	rules.version = 17
	rules.fighter = FighterCatalog.of(ContentIds.FIGHTER_DUELIST)
	rules.weapon = WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD)
	rules.combat = combat_tuning()
	rules.arena_id = ContentIds.ARENA_STANDARD
	rules.arena_radius = 8.0
	rules.spawn_offset = 2.5
	rules.rounds_to_win = 3
	rules.max_rounds = 9
	rules.intro_ticks = 72
	rules.result_ticks = 96
	rules.round_time_limit_ticks = 60 * SimulationTimebase.TICK_RATE
	rules.post_round_free_ticks = 150
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
	combat.critical_exposure = 1.0
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
	## The 80 kg body is the *reservoir* a strike may draw on, never its
	## automatic strike mass: a sword couples a fraction of it, and well-
	## coupled contact lands around 19 kg-equivalent.
	combat.body_contribution_mass = 20.0
	combat.resist_plant_floor = 0.45
	combat.reference_strike_mass = 18.6
	## The reference strike: `reference_strike_mass` closing at the weapon's
	## `reference_closing_speed` of 10.5 m/s. `J = m v` and `E = ½ m v²`, so
	## normalized impulse and severity both read 1.0 for exactly that hit.
	combat.reference_impulse = 195.3
	combat.reference_severity = 1025.3
	combat.blade_inertia_coupling_floor = 0.6
	combat.blade_inertia_commit_bonus = 0.5
	combat.blade_solid_speed = 3.0
	combat.blade_strong_speed = 8.0
	combat.bind_break_distance = 0.12
	combat.parry_margin_seconds = 0.08
	combat.substep_travel = 0.03
	combat.max_substeps = 48
	## Chronological contact loop. Six resolutions is far more than a duel
	## produces in a 16.7 ms tick, so hitting it means the geometry is wrong.
	combat.max_contacts_per_tick = 6
	## Twice the blade radius: blades must visibly part, not merely stop
	## overlapping, before they can clash again.
	combat.separation_epsilon = 0.044
	combat.bind_escape_ticks = 30
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
	## Capability. Injury alone can cost up to 35% of motor authority; fatigue
	## alone up to 25%. The additive floor of 0.4 ensures even a badly hurt,
	## exhausted fighter retains 40% of their force and torque — enough to
	## swing and turn, never enough to fight at full speed.
	combat.capability_injury_max = 0.35
	combat.capability_fatigue_max = 0.25
	combat.capability_floor = 0.4
	## Body-body collision: nearly inelastic so fighters don't bounce off each
	## other. Mass-aware inverse impulse handles the asymmetry (PHYS-005).
	combat.body_restitution = 0.05
	## Tangential friction. Bounded by Coulomb's law: a glancing shoulder bump
	## sheds some lateral speed but cannot halt a side-step. 0.3 keeps the
	## effect visible without making every bump a wall.
	combat.body_friction = 0.3
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
	## Game-feel pushback. Slightly above 1.0 for readable defender displacement.
	## Never reflected back into blade reaction.
	combat.body_push_feel_scale = 1.2
	return combat
