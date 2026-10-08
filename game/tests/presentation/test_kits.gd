extends TestCase

## PRES-KIT: one kit per identity is the only AV edit surface; authored kits
## override the primitive fallback; missing content fails closed in
## development and degrades in release.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-KIT"


func test_every_identity_has_a_kit() -> void:
	var catalog := RiposteKits.build_catalog()
	assert_eq(catalog.missing_ids(RiposteKits.required_ids()).size(), 0, "no identity without a kit")
	var kits := DuelKits.resolve(catalog, StandardDuelRules.create())
	assert_true(kits.is_complete(), "the standard rules resolve a full kit set")
	assert_eq(kits.weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "weapon kit bound by content id")


func test_development_fails_closed_and_release_degrades() -> void:
	var development := RiposteKits.build_catalog(true)
	assert_true(development.resolve(&"fighter.unknown", PresentationKit.PRIMITIVE_FIGHTER) == null, "development: missing kit is null")
	var release := RiposteKits.build_catalog(false)
	var placeholder := release.resolve(&"fighter.unknown", PresentationKit.PRIMITIVE_FIGHTER)
	assert_true(placeholder != null and placeholder.is_placeholder, "release: a placeholder keeps the game playable")


func test_authored_kits_override_the_primitive_fallback() -> void:
	var authored := PresentationKit.new()
	authored.id = ContentIds.FIGHTER_DUELIST
	authored.body_height = 1.9
	var kits: Array[PresentationKit] = [authored]
	var catalog := RiposteKits.catalog_from(kits, true)
	assert_eq(catalog.resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER).body_height, 1.9, "authored kit wins")
	assert_true(catalog.has(ContentIds.WEAPON_BASTARD_SWORD), "factory still fills the other identities")


func test_kits_declare_their_cues() -> void:
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), StandardDuelRules.create())
	assert_true(kits.weapon.has_audio(PresentationKit.CUE_BLADE_SOLID), "weapon kit sounds its contacts")
	assert_true(kits.weapon.stream_for(PresentationKit.CUE_SWING) is AudioStreamWAV, "placeholder streams are real audio")
	assert_false(kits.arena.has_audio(PresentationKit.CUE_SWING), "arena kit has no swing cue")
	assert_true(kits.arena.stream_for(PresentationKit.CUE_SWING) == null, "missing cue yields no stream")
	assert_true(kits.weapon.has_vfx(PresentationKit.VFX_SPARK), "weapon kit emits sparks")


func test_a_scene_kit_replaces_the_primitive_and_takes_combatant_color() -> void:
	var model := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Torso"
	body.mesh = BoxMesh.new()
	model.add_child(body)
	body.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var kit := PresentationKit.new()
	kit.id = ContentIds.FIGHTER_DUELIST
	kit.scene = packed
	kit.color_targets = PackedStringArray(["Torso"])
	var weapon := DuelKits.resolve(RiposteKits.build_catalog(), StandardDuelRules.create()).weapon
	var proxy := FighterPresentation3D.create(1, DuelSide.Id.DARK_NORTH, kit, weapon, 0.27, 0.25, 1.22)
	var torso := proxy.find_child("Torso", true, false) as MeshInstance3D
	assert_true(torso != null, "authored model instanced")
	assert_true(proxy.find_child("Body", true, false) == null, "primitive body not built")
	assert_eq((torso.material_override as StandardMaterial3D).albedo_color, RiposteTheme.DARK_BODY, "declared target colored for its combatant")
	proxy.free()


func test_mapped_clips_stay_inside_the_semantics_the_proxy_asks_for() -> void:
	var catalog := RiposteKits.build_catalog()
	for kit_id in RiposteKits.required_ids():
		var shipped := catalog.resolve(kit_id, PresentationKit.PRIMITIVE_FIGHTER)
		assert_eq(shipped.unknown_clip_semantics().size(), 0, "%s maps no clip the proxy never plays" % kit_id)
	var typo := PresentationKit.new()
	typo.animation_clips = {PresentationKit.ANIM_SWING: &"swing_a", &"SWNIG": &"swing_b"}
	var unknown := typo.unknown_clip_semantics()
	assert_eq(unknown.size(), 1, "the typo is reported")
	assert_eq(unknown[0], "SWNIG", "and reported by name, not repaired into the nearest semantic")
	assert_eq(typo.clip_for(PresentationKit.ANIM_SWING), &"swing_a", "the correct mapping still resolves")
	assert_eq(typo.clip_for(&"SWNIG"), &"swing_b", "a lookup is not the gate - the gate is")
	for semantic in PresentationKit.ANIM_SEMANTICS:
		assert_true(semantic != &"", "every declared semantic is nameable")


func test_placeholder_audio_is_deterministic_and_cached() -> void:
	var first := PlaceholderAudio.cues()
	var second := PlaceholderAudio.cues()
	assert_true(first[PresentationKit.CUE_BLADE_STRONG] == second[PresentationKit.CUE_BLADE_STRONG], "streams generated once")
	var stream := first[PresentationKit.CUE_BODY_HEAVY] as AudioStreamWAV
	assert_eq(stream.mix_rate, PlaceholderAudio.MIX_RATE, "22.05 kHz")
	assert_true(stream.data.size() > 1000, "real sample data")
