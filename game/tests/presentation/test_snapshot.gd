extends TestCase

## PRES-SNAPSHOT: one read boundary from simulation to presentation, and one
## plane→world mapping.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-SNAPSHOT"


func test_projector_copies_authoritative_facts() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(1)
	fighter.x = 1.5
	fighter.y = -0.5
	fighter.health = 42.0
	fighter.weapon.angle = 0.3
	fighter.weapon.phase = CombatPhase.Id.CHARGING
	fighter.weapon.charge = 0.6
	state.scores[0] = 2
	var snapshot := SnapshotProjector.project(state, rules)
	var row := snapshot.fighter(1)
	assert_eq(row.x, 1.5, "x")
	assert_eq(row.y, -0.5, "y")
	assert_eq(row.health, 42.0, "health")
	assert_eq(row.max_health, rules.combatant(0).fighter.max_health, "health scale")
	assert_eq(row.phase, CombatPhase.Id.CHARGING, "phase")
	assert_eq(row.charge, 0.6, "charge")
	assert_near(row.blade_angle, SimMath.wrap_angle(fighter.facing + 0.3), 1e-12, "absolute blade angle")
	assert_eq(row.side, fighter.side, "side, so presentation can tell the ends apart")
	assert_eq(snapshot.scores[0], 2, "score")
	assert_eq(row.tip_radius, rules.combatant(0).weapon.tip_radius, "blade geometry")
	state.scores[0] = 3
	assert_eq(snapshot.scores[0], 2, "the snapshot does not alias live state")


## Everything presentation needs to render a swing honestly, carried on the
## snapshot (COMBAT-009). The point of the surface is that no presentation
## code ever recomputes a combat formula: if a value is not here, the trail
## and the audio must do without it rather than invent it.
func test_the_snapshot_carries_the_swing_semantics() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(0)
	ContactFixture.arm(fighter, 0.0, 0.0, 0.0, 0.0, 12.0, CombatPhase.Id.ACTIVE_THREAT, 0.7, rules.combatant(0).weapon)
	fighter.weapon.launch_preparation = 0.9
	var row := SnapshotProjector.project(state, rules).fighter(0)
	var tip_speed := SwingSemantics.tip_speed(fighter, rules.combatant(0))
	assert_near(row.tip_speed, tip_speed, 1e-9, "the simulation's own tip-speed reading, never recomputed")
	assert_true(row.tip_speed > 12.0, "tip speed, not angular speed")
	assert_eq(row.launch_preparation, 0.9, "how well prepared the swing was at release")
	assert_between(row.swing_progress, 0.0, 1.0, "how far through its arc the blade physically is")
	assert_between(row.swing_potential, 0.0, 1.0, "and how dangerous this part of it is")
	assert_true(row.swing_potential > 0.0, "a live swing at speed reads as a threat")
	var plain := SnapshotProjector.project(state, rules)
	assert_false(plain.has_threat_readings, "the threat readings are left out unless asked for, and the snapshot says so")
	assert_eq(row.exposure, 0.0, "left out, the exposure keeps its neutral default (never NaN)")
	assert_eq(row.threat_time, 0.0, "and so does the threat time")
	var read := SnapshotProjector.project(state, rules, true)
	assert_true(read.has_threat_readings, "asked for, the snapshot carries them")
	assert_between(read.fighter(0).exposure, 0.0, 1.0, "asked for, each fighter's own exposure, as a fraction")
	assert_eq(read.fighter(0).threat_time, InitiativeModel.time_to_threat(fighter, state.fighter(1), rules), "and its own threat time, the domain's estimate")
	assert_eq(read.fighter(0).exposure, ExposureModel.reading(fighter, state.fighter(1), rules), "its exposure the domain's reading exactly")
	assert_eq(row.stable_side, fighter.weapon.stable_side, "the side the blade is committed to")
	assert_eq(row.guard_region, GuardRegion.of(fighter.weapon.angle, rules.combatant(0).weapon.guard_angle), "and where it sits relative to the guard")
	assert_eq(row.burst, fighter.gesture.burst_kind, "plus any burst under way")
	## Derived, never aliased: a later change to live state must not reach a
	## snapshot that has already been handed to the renderer.
	fighter.weapon.speed = 0.0
	assert_near(row.tip_speed, tip_speed, 1e-9, "the snapshot is a copy")


## A blade that is not carrying a strike must read as no threat at all, or the
## trail would advertise a wind-back as something to fear.
func test_a_charging_blade_reads_as_no_threat() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(0)
	fighter.weapon.set_phase(CombatPhase.Id.CHARGING)
	fighter.weapon.speed = -rules.combatant(0).weapon.windup_speed
	fighter.weapon.charge = 0.5
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_true(row.tip_speed > 0.0, "precondition: the blade really is moving")
	assert_eq(row.swing_potential, 0.0, "but a wind-back threatens nobody")
	assert_eq(row.charge, 0.5, "the charge is still reported, for the wind-back cue")


func test_time_left_counts_down_from_the_limit() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	state.round_ticks = 600
	assert_eq(SnapshotProjector.project(state, rules).time_left_ticks, rules.round_time_limit_ticks - 600, "remaining ticks")


func test_plane_maps_to_world_with_up_away_from_camera() -> void:
	assert_eq(ArenaTransform.to_world(1.0, 2.0), Vector3(1.0, 0.0, -2.0), "+Y is world -Z")
	assert_eq(ArenaTransform.to_plane(Vector3(3.0, 1.0, -4.0)), Vector2(3.0, 4.0), "round trip")
	for degrees: float in [0.0, 90.0, 180.0, -45.0]:
		var heading := deg_to_rad(degrees)
		var probe := Node3D.new()
		probe.rotation.y = ArenaTransform.yaw(heading)
		var front := probe.basis.z
		probe.free()
		assert_true(front.is_equal_approx(ArenaTransform.direction(heading)), "model front follows heading %s°" % str(degrees))


func test_projector_carries_condition_and_stamina() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(0)
	fighter.health = rules.combatant(0).fighter.max_health * 0.4
	assert_eq(fighter.stamina, 1.0, "fixture: a fresh fighter is rested")
	var row := SnapshotProjector.project(state, rules).fighter(0)
	## STAMINA-004: the settled stamina and the dash cost, copied.
	assert_eq(row.stamina, 1.0, "full stamina in the snapshot")
	assert_eq(row.dash_cost, rules.combat.stamina_dash_cost, "with the dash cost the HUD marks")
	assert_eq(row.condition, FighterCondition.Id.WOUNDED, "40% health is WOUNDED")
	## CONDITION-001: the three scales are the domain's own, copied, at h = 0.4.
	assert_near(row.force_scale, 0.70 + 0.30 * 0.4, 1e-12, "force scale projected from health (rested)")
	fighter.stamina = 0.5
	var tired := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(tired.stamina, 0.5, "a drained bar projects as it stands")
	assert_eq(tired.impact_authority, 1.0, "a fresh fighter's impact authority projects full")
	fighter.impact_authority = 0.6
	var dipped := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(dipped.impact_authority, 0.6, "a dipped return projects as it stands")
	assert_near(tired.force_scale, (0.70 + 0.30 * 0.4) * (rules.combat.stamina_force_floor + (1.0 - rules.combat.stamina_force_floor) * 0.5), 1e-12, "and the force scale carries the fatigue term")
	assert_near(row.speed_scale, 0.85 + 0.15 * 0.4, 1e-12, "speed scale")
	assert_near(row.tracking_scale, 0.80 + 0.20 * 0.4, 1e-12, "tracking scale")


func test_full_health_projects_healthy_condition() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(row.condition, FighterCondition.Id.HEALTHY, "full health is HEALTHY")
	assert_eq(row.force_scale, 1.0, "no degradation at full health")
	assert_eq(row.speed_scale, 1.0, "none in speed")
	assert_eq(row.tracking_scale, 1.0, "none in tracking")


## ──────────────────── COMBAT READABILITY STATE ─────────────────────────────


func test_readability_fields_are_bounded_and_pure() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var before := StateHasher.hash_state(state)
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(StateHasher.hash_state(state), before, "projector does not mutate state")
	assert_between(row.recovery_remaining01, 0.0, 1.0, "recovery_remaining01 bounded")
	assert_between(row.point_threat01, 0.0, 1.0, "point_threat01 bounded")
	assert_between(row.movement_speed01, 0.0, 1.0, "movement_speed01 bounded")
	assert_between(row.burst01, 0.0, 1.0, "burst01 bounded")


func test_readability_recovery_reads_phase() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(0)
	fighter.weapon.set_phase(CombatPhase.Id.RECOVERY)
	fighter.weapon.recovery_ticks = 20
	fighter.weapon.recovery_left = 10
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_near(row.recovery_remaining01, 0.5, 1e-9, "halfway through recovery reads 0.5")
	fighter.weapon.recovery_left = 20
	var start := SnapshotProjector.project(state, rules).fighter(0)
	assert_near(start.recovery_remaining01, 1.0, 1e-9, "just entered recovery reads 1.0")
	fighter.weapon.recovery_left = 1
	var nearly_done := SnapshotProjector.project(state, rules).fighter(0)
	assert_near(nearly_done.recovery_remaining01, 0.05, 1e-9, "1/20 remaining reads 0.05")
	fighter.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	var neutral := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(neutral.recovery_remaining01, 0.0, "neutral phase reads 0")
	fighter.weapon.set_phase(CombatPhase.Id.OVERSWING)
	var overswing := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(overswing.recovery_remaining01, 1.0, "overswing reads maximum remaining")


func test_readability_movement_speed() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	state.fighter(0).vx = rules.combatant(0).fighter.max_speed
	state.fighter(0).vy = 0.0
	var row := SnapshotProjector.project(state, rules).fighter(0)
	assert_near(row.movement_speed01, 1.0, 1e-6, "max speed reads 1.0")
	state.fighter(0).vx = 0.0
	var still := SnapshotProjector.project(state, rules).fighter(0)
	assert_eq(still.movement_speed01, 0.0, "stationary reads 0.0")


## ──────────────────── IMPACT FEEDBACK ──────────────────────────────────────


func test_impact_feedback_from_contact_event() -> void:
	var rules := StandardDuelRules.create()
	var event := DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
		DuelEventKeys.IMPULSE: rules.combat.reference_impulse * 0.5,
		DuelEventKeys.SEVERITY: rules.combat.reference_severity * 0.25,
		DuelEventKeys.BLADE_FRACTION: 0.7,
		DuelEventKeys.ALIGNMENT: 0.9,
		DuelEventKeys.X: 1.0,
		DuelEventKeys.Y: 2.0,
		DuelEventKeys.NORMAL_X: 0.0,
		DuelEventKeys.NORMAL_Y: 1.0,
	})
	var fb := ImpactFeedback.from_event(event, rules.combat)
	assert_near(fb.impulse01, 0.5, 1e-9, "impulse normalized to reference")
	assert_near(fb.severity01, 0.25, 1e-9, "severity normalized to reference")
	assert_eq(fb.blade_fraction, 0.7, "blade fraction carried")
	assert_eq(fb.edge_alignment, 0.9, "alignment carried")
	assert_eq(fb.attacker, 0, "attacker slot")
	assert_eq(fb.target, 1, "target slot")
	assert_eq(fb.contact_type, DuelEventTypes.BODY_HIT, "event type")
	assert_eq(fb.point_x, 1.0, "contact point x")
	assert_eq(fb.point_y, 2.0, "contact point y")
	assert_eq(event.text(DuelEventKeys.REGION), "", "a body hit carries its region from the resolver, not from this projection")


func test_impact_feedback_recognizes_contact_events() -> void:
	assert_true(ImpactFeedback.is_contact_event(DuelEvent.create(DuelEventTypes.BODY_HIT, 1)), "body hit")
	assert_true(ImpactFeedback.is_contact_event(DuelEvent.create(DuelEventTypes.BLADE_CONTACT, 1)), "blade contact")
	assert_true(ImpactFeedback.is_contact_event(DuelEvent.create(DuelEventTypes.BODY_PUSH, 1)), "body push")
	assert_false(ImpactFeedback.is_contact_event(DuelEvent.create(DuelEventTypes.ATTACK_RELEASED, 1)), "not attack")
