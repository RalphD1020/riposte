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
