extends TestCase

## CHARACTER: the art file's scale compiles through the existing body law, and
## scale 1.0 is the shipped duelist. The sword is not resized. A body too
## small to hold that sword is refused before a match.
##
## Implements: /spec/invariants.md#content-002
## See also: /docs/concepts/content.md


func _init() -> void:
	suite_name = "CHARACTER"


func test_scale_one_is_the_shipped_duelist() -> void:
	var character := CharacterCatalog.wolf()
	var shipped := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	assert_true(character != null, "fixture: the character art file parses")
	assert_eq(character.display_name, "Wolf", "the art file is the display name")
	assert_near(character.body_scale, 1.0, 1e-12, "Wolf is body scale 1")
	assert_eq(character.fighter_id, ContentIds.FIGHTER_DUELIST, "the fighter id is the duelist")
	var spec := CharacterCatalog.spec_at(character.body_scale)
	assert_true(spec != null and shipped != null, "fixture: both specs compile")
	assert_eq(spec.fingerprint(), shipped.fingerprint(), "scale 1 does not change the combat spec")
	assert_eq(spec.weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "the weapon id is unchanged")


func test_another_scale_uses_the_existing_body_law_and_keeps_the_sword() -> void:
	var scale := 1.25
	var spec := CharacterCatalog.spec_at(scale)
	var body := FighterCatalog.prototype_at(scale)
	assert_true(spec != null, "1.25 still reaches the sword grips")
	assert_near(spec.fighter.height, body.height, 1e-12, "height follows prototype_at")
	assert_near(spec.fighter.mass, body.mass, 1e-9, "mass follows prototype_at")
	assert_near(spec.fighter.locomotion_force, body.locomotion_force, 1e-9, "force follows prototype_at")
	assert_near(spec.fighter.turn_torque, body.turn_torque, 1e-9, "torque follows prototype_at")
	assert_near(spec.weapon.blade_length(), PhysicalBaseline.SWORD_BLADE_M, 1e-9, "the blade length stays 1.0")
	assert_near(spec.weapon.mass, PhysicalBaseline.SWORD_MASS_KG, 1e-12, "the sword mass stays 1.0")
	assert_near(spec.handling.attack_path.carriage_forward(0.0), 0.63 * scale, 1e-9, "the hilt track scales with the grip")


func test_a_body_that_cannot_hold_the_sword_is_refused() -> void:
	assert_true(CharacterCatalog.spec_at(0.5) == null, "half size puts the guard past the hands")
	assert_true(CharacterCatalog.spec_at(0.0) == null, "a non-positive scale is refused")


func test_the_display_name_is_not_part_of_the_combat_spec() -> void:
	var spec := CharacterCatalog.spec_at(1.0)
	var shipped := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	assert_eq(spec.fingerprint(), shipped.fingerprint(), "naming the character does not change the spec hash")


## The physique adapter adds no physics: Wolf's resolved file (1.80 m, frame
## 1.0, muscularity 1.0) authors exactly the shipped duelist, bit for bit, so
## every unit and field crosses the language boundary intact.
func test_wolfs_resolved_physique_authors_the_shipped_duelist() -> void:
	## ARRANGE
	var document := CharacterCatalog.physique(CharacterCatalog.WOLF_PHYSIQUE_PATH)
	var shipped := LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)
	assert_false(document.is_empty(), "fixture: wolf.physique.json parses")
	assert_eq(FighterCatalog.physique_problem(document), "", "fixture: it is a valid physique")
	assert_near(float(document["body"]["height_m"]), PhysicalBaseline.FIGHTER_HEIGHT_M, 1e-12, "fixture: Wolf is 1.80 m")
	## ACT
	var spec := CharacterCatalog.spec_from_physique(ContentIds.FIGHTER_DUELIST, document)
	## ASSERT
	assert_true(spec != null, "Wolf's physique compiles")
	assert_eq(spec.fingerprint(), shipped.fingerprint(), "and resolves to the shipped duelist exactly")


## Each applied value lands on the field the simulation reads, through the
## existing actuator seam; semantics never move with the body (PHYS-005); and
## proposed values (stamina) are not read.
func test_resolved_values_reach_their_authored_fields_and_nothing_else() -> void:
	## ARRANGE
	var document := _physique(1.93, {"mass_kg": 104.5, "strength_scale": 1.31, "traction_scale": 1.18,
		"turn_support_scale": 1.27, "hurt_radius_m": 0.214, "push_radius_m": 0.297, "grip_radius_m": 0.268,
		"hand_radius_m": 0.0375, "lying_half_length_m": 0.911, "lying_radius_m": 0.197})
	var wolf := FighterCatalog.duelist()
	## ACT
	var fighter := FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST, document)
	## ASSERT
	assert_true(fighter != null and fighter.is_valid(), "a valid physique authors a valid fighter")
	assert_near(fighter.height, 1.93, 1e-12, "height from body")
	assert_near(fighter.mass, 104.5, 1e-12, "mass in kg")
	assert_near(fighter.hand_mass, 104.5 * PhysicalBaseline.HAND_REFLECTED_MASS_SHARE, 1e-12, "hand mass by the reference share")
	assert_near(fighter.hurt_radius, 0.214, 1e-12, "the torso circle in metres")
	assert_near(fighter.push_radius, 0.297, 1e-12, "the footprint in metres")
	assert_near(fighter.grip_radius, 0.268, 1e-12, "the grip reach")
	assert_near(fighter.hand_radius, 0.0375, 1e-12, "the hand proxy")
	assert_near(fighter.lying_half_length, 0.911, 1e-12, "the lying length")
	assert_near(fighter.lying_radius, 0.197, 1e-12, "the lying girth")
	assert_near(fighter.locomotion_force, FighterCatalog.LOCOMOTION_FORCE_N * 1.18, 1e-9, "traction scales Wolf's newtons")
	assert_near(fighter.braking_force, FighterCatalog.BRAKING_FORCE_N * 1.18, 1e-9, "and his braking")
	assert_near(fighter.burst_force, FighterCatalog.BURST_FORCE_N * 1.18, 1e-9, "and his burst")
	assert_near(fighter.turn_torque, FighterCatalog.TURN_TORQUE_NM * 1.27, 1e-9, "turn support scales Wolf's N·m")
	assert_near(fighter.weapon_torque_scale, 1.31, 1e-12, "strength is the weapon drive")
	for semantic: String in ["max_speed", "turn_speed_max", "track_gain", "tap_window_ticks", "burst_ticks", "max_health"]:
		assert_eq(fighter.get(semantic), wolf.get(semantic), "%s does not move with the body" % semantic)
	var restaminaed := document.duplicate(true)
	restaminaed["proposed"] = {"stamina_capacity": 3.0, "stamina_recovery": 0.1}
	var same := FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST, restaminaed)
	assert_eq(LoadoutCatalog.assemble(same, WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, same.grip_radius)).fingerprint(),
		LoadoutCatalog.assemble(fighter, WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, fighter.grip_radius)).fingerprint(),
		"proposed stamina never reaches the spec")


## A physique that breaks the torso-circle bound, misses a field, or names the
## wrong schema is refused with its reason. Nothing is clamped into range.
func test_a_bad_physique_is_refused_with_a_reason_not_clamped() -> void:
	var good := _physique(1.8, {"mass_kg": 80.0, "strength_scale": 1.0, "traction_scale": 1.0,
		"turn_support_scale": 1.0, "hurt_radius_m": 0.195, "push_radius_m": 0.27, "grip_radius_m": 0.25,
		"hand_radius_m": 0.035, "lying_half_length_m": 0.85, "lying_radius_m": 0.18})
	assert_eq(FighterCatalog.physique_problem(good), "", "fixture: the reference document is valid")
	var wide := good.duplicate(true)
	wide["applied"]["hurt_radius_m"] = 0.30
	assert_eq(FighterCatalog.physique_problem(wide), "hurt_radius must not exceed push_radius", "a circle past the footprint is named")
	assert_true(FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST, wide) == null, "and refused, not clamped to 0.27")
	var missing := good.duplicate(true)
	(missing["applied"] as Dictionary).erase("grip_radius_m")
	assert_eq(FighterCatalog.physique_problem(missing), "applied.grip_radius_m must be a positive number", "a missing field is named")
	var weightless := good.duplicate(true)
	weightless["applied"]["mass_kg"] = 0.0
	assert_eq(FighterCatalog.physique_problem(weightless), "applied.mass_kg must be a positive number", "a weightless body is named")
	var future := good.duplicate(true)
	future["version"] = 2
	assert_eq(FighterCatalog.physique_problem(future), "a physique must be riposte.physique version 1", "an unknown schema version is named")
	assert_true(CharacterCatalog.physique("res://content/characters/no_such.physique.json").is_empty(), "a missing file parses to nothing")


## The force path is mass-aware for a physique-authored fighter, end to end:
## the resolved mass and actuator values reach the derived accelerations the
## simulation reads (`a = F/m`, `α = τ/I`), with no kinematic bypass. Proven at
## the definition seam the solver consumes; GENERIC covers the contact path for
## any spec, and a physique fighter is just a spec.
func test_a_physique_fighter_is_mass_aware_through_the_derived_accelerations() -> void:
	## ARRANGE: Wolf, and a heavier, stronger, broader build.
	var wolf := FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST,
		CharacterCatalog.physique(CharacterCatalog.WOLF_PHYSIQUE_PATH))
	var heavy := FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST, _physique(1.95, {
		"mass_kg": 120.0, "strength_scale": 1.4, "traction_scale": 1.25, "turn_support_scale": 1.3,
		"hurt_radius_m": 0.225, "push_radius_m": 0.30, "grip_radius_m": 0.27, "hand_radius_m": 0.038,
		"lying_half_length_m": 0.92, "lying_radius_m": 0.21}))
	assert_true(wolf != null and heavy != null, "both physiques author fighters")
	## ASSERT: a = F/m holds for the resolved values (the one place mass pays).
	assert_near(heavy.move_accel(), heavy.locomotion_force / heavy.mass, 1e-12, "move accel is force over mass")
	assert_near(heavy.turn_accel(), heavy.turn_torque / heavy.moment_of_inertia(), 1e-12, "turn accel is torque over inertia")
	## Same applied-force relationship, different mass: the 120 kg build with
	## 1.25x traction accelerates less than its force ratio because its mass rose
	## faster (1.5x) than its force (1.25x) — mass is not cancelled out.
	assert_true(heavy.move_accel() < wolf.move_accel(), "the heavier build starts slower")
	assert_true(heavy.moment_of_inertia() > wolf.moment_of_inertia(), "more mass and a wider body resist turning")
	assert_true(heavy.turn_accel() < wolf.turn_accel(), "so it turns slower for its torque")
	## Strength is weapon drive, independent of mass: it does not touch move accel.
	var stronger_only := FighterCatalog.from_physique(ContentIds.FIGHTER_DUELIST, _physique(1.8, {
		"mass_kg": 80.0, "strength_scale": 1.5, "traction_scale": 1.0, "turn_support_scale": 1.0,
		"hurt_radius_m": 0.195, "push_radius_m": 0.27, "grip_radius_m": 0.25, "hand_radius_m": 0.035,
		"lying_half_length_m": 0.85, "lying_radius_m": 0.18}))
	assert_near(stronger_only.move_accel(), wolf.move_accel(), 1e-12, "strength alone does not change footwork")
	assert_true(stronger_only.weapon_torque_scale > wolf.weapon_torque_scale, "it only drives the weapon harder")
	assert_near(stronger_only.mass, wolf.mass, 1e-12, "and does not change mass")


func _physique(height: float, applied: Dictionary) -> Dictionary:
	return {"schema": "riposte.physique", "version": 1, "id": "character.fixture",
		"body": {"height_m": height, "frame_build": 1.0, "muscularity": 1.0}, "applied": applied}
