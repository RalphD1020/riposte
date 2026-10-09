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
	assert_true(kits.weapon.stream_for(PresentationKit.CUE_SWING) is AudioStream, "the shipped swing is real audio")
	assert_true(kits.weapon.variant_count(PresentationKit.CUE_SWING) >= 3, "with several takes to vary between")
	assert_true(kits.weapon.stream_for(PresentationKit.CUE_CHARGE) is AudioStreamMP3 and (kits.weapon.stream_for(PresentationKit.CUE_CHARGE) as AudioStreamMP3).loop, "held cues are imported as loops")
	assert_true(kits.weapon.layers_for(PresentationKit.CUE_BLADE_STRONG).size() >= 1, "a strong clash is layered, not one pre-mixed file")
	assert_true(PlaceholderAudio.cues()[PresentationKit.CUE_SWING] is AudioStreamWAV, "the procedural fallback still exists for anything not authored")
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
	var proxy := FighterPresentation3D.create(1, DuelSide.Id.DARK_NORTH, CombatantPresentationKit.of(kit, weapon), 0.27, 0.25, 1.22)
	var torso := proxy.find_child("Torso", true, false) as MeshInstance3D
	assert_true(torso != null, "authored model instanced")
	assert_true(proxy.find_child("Body", true, false) == null, "primitive body not built")
	assert_eq((torso.material_override as StandardMaterial3D).albedo_color, RiposteTheme.accent_for(DuelSide.Id.DARK_NORTH), "declared target takes its side's accent")
	proxy.free()


func test_skins_dress_the_base_body_and_never_touch_definitions() -> void:
	var model := Node3D.new()
	for part: String in ["Torso", "FurCollar", "Hair"]:
		var piece := MeshInstance3D.new()
		piece.name = part
		piece.mesh = BoxMesh.new()
		var fabric := StandardMaterial3D.new()
		fabric.resource_name = "fabric"
		piece.mesh.surface_set_material(0, fabric)
		model.add_child(piece)
		piece.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var base := PresentationKit.new()
	base.id = ContentIds.FIGHTER_DUELIST
	base.scene = packed
	var short_hair := BoxMesh.new()
	var training_fabric := StandardMaterial3D.new()
	var skin := FighterSkinKit.new()
	skin.skin_id = &"skin.test"
	skin.base_kit_id = ContentIds.FIGHTER_DUELIST
	skin.mesh_overrides = {"FurCollar": null, "Hair": short_hair}
	skin.material_overrides = {"fabric": training_fabric}
	var stranger := FighterSkinKit.new()
	stranger.skin_id = &"skin.stranger"
	stranger.base_kit_id = &"fighter.someone_else"
	var catalog := RiposteKits.build_catalog()
	catalog.register(base)
	catalog.register_fighter_skin(skin)
	catalog.register_fighter_skin(stranger)
	var rules := StandardDuelRules.create()
	var reach_before := rules.weapon.tip_radius
	var kits := DuelKits.resolve(catalog, rules, [&"skin.test", &"skin.stranger"] as Array[StringName])
	assert_true(kits.combatant(0).fighter_skin == skin, "slot 0 wears the chosen skin")
	assert_true(kits.combatant(1).fighter_skin == null, "a skin for another body is refused, not forced on")
	assert_true(DuelKits.resolve(catalog, rules, [&"skin.unknown"] as Array[StringName]).combatant(0).fighter_skin == null, "an unknown skin is the base look")
	var weapon := kits.weapon
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), 0.27, 0.25, 1.22)
	assert_false((proxy.find_child("FurCollar", true, false) as MeshInstance3D).visible, "a null mesh override hides the piece")
	assert_true((proxy.find_child("Hair", true, false) as MeshInstance3D).mesh == short_hair, "a mesh override swaps the piece")
	var torso := proxy.find_child("Torso", true, false) as MeshInstance3D
	assert_true(torso.get_surface_override_material(0) == training_fabric, "a material override follows the authored material name")
	assert_eq(rules.weapon.tip_radius, reach_before, "dressing a fighter never changes reach")
	assert_true(rules.is_valid(), "and the rules are untouched")
	assert_true(kits.combatant(1).weapon == weapon, "both combatants hold the same weapon kit")
	proxy.free()


func test_colorway_is_a_mirror_discriminator_not_a_team_identity() -> void:
	assert_false(ColorwayResolver.is_mirror([&"fighter.duelist", &"fighter.other"] as Array, [&"", &""] as Array), "different fighters are not a mirror")
	assert_false(ColorwayResolver.is_mirror([&"fighter.duelist", &"fighter.duelist"] as Array, [&"", &"skin.x"] as Array), "same fighter, different skins is not a mirror")
	assert_true(ColorwayResolver.is_mirror([&"fighter.duelist", &"fighter.duelist"] as Array, [&"", &""] as Array), "same fighter and same skin is a mirror")
	assert_eq(ColorwayResolver.variant_for(DuelSide.Id.LIGHT_SOUTH, true), SkinColorwayProfile.Variant.DEFAULT, "the Light side of a mirror keeps default")
	assert_eq(ColorwayResolver.variant_for(DuelSide.Id.DARK_NORTH, true), SkinColorwayProfile.Variant.ALTERNATE, "only the Dark side of a mirror takes alternate")
	assert_eq(ColorwayResolver.variant_for(DuelSide.Id.DARK_NORTH, false), SkinColorwayProfile.Variant.DEFAULT, "no mirror, no alternate — side never forces a colorway")


func test_wolf_versus_wolf_mirror_colours_only_the_dark_body() -> void:
	var rules := StandardDuelRules.create()
	var catalog := RiposteKits.build_catalog()
	var kits := DuelKits.resolve(catalog, rules)
	assert_true(kits.combatant(0).mirror, "base Wolf vs base Wolf is a mirror")
	assert_true(kits.combatant(0).colorway() != null and kits.combatant(0).colorway().has_alternate(), "and base Wolf ships an alternate colorway")
	assert_true(kits.combatant(0).colorway_overrides(DuelSide.Id.LIGHT_SOUTH).is_empty(), "Light Wolf keeps its own palette")
	assert_false(kits.combatant(1).colorway_overrides(DuelSide.Id.DARK_NORTH).is_empty(), "Dark Wolf takes the alternate palette")
	## The Dark body actually repaints the fabric, and SideAccent still wins.
	var dark := FighterPresentation3D.create(1, DuelSide.Id.DARK_NORTH, kits.combatant(1), rules.fighter.body_radius, rules.fighter.grip_radius, rules.weapon.tip_radius)
	var torso := dark.find_child("TorsoCore", true, false) as MeshInstance3D
	assert_true(torso != null and torso.get_surface_override_material(0) != null, "the alternate colorway repainted the dark Wolf's fabric")
	var accent := dark.find_child("SideAccentSash", true, false) as MeshInstance3D
	assert_eq((accent.material_override as StandardMaterial3D).albedo_color, RiposteTheme.accent_for(DuelSide.Id.DARK_NORTH), "and the side accent still reads over the colorway")
	dark.queue_free()
	## A non-mirror (training skin on only one slot) leaves both on default.
	var mixed := DuelKits.resolve(catalog, rules, [&"", RiposteKits.SKIN_DUELIST_TRAINING] as Array[StringName])
	assert_false(mixed.combatant(0).mirror, "different skins are not a mirror")
	assert_true(mixed.combatant(1).colorway_overrides(DuelSide.Id.DARK_NORTH).is_empty(), "so the Dark side keeps its own palette")


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


## A killing blow picks a death style deterministically from the contact family
## and the event key, so a replay dies the same way, and a kit that authors no
## deaths still gets the full built-in spread.
func test_a_killing_blow_picks_a_death_style_deterministically() -> void:
	assert_eq(DeathPresentationProfile.family_of("thrust"), DeathPresentationProfile.Family.STAB, "a thrust runs the body through")
	assert_eq(DeathPresentationProfile.family_of("poke"), DeathPresentationProfile.Family.STAB, "so does a lethal poke")
	assert_eq(DeathPresentationProfile.family_of("slash"), DeathPresentationProfile.Family.SLASH, "a cut strikes down")
	assert_eq(DeathPresentationProfile.family_of("graze"), DeathPresentationProfile.Family.SLASH, "an edge contact strikes down")
	var profile := DeathPresentationProfile.new()
	var slash := profile.style_for(DeathPresentationProfile.Family.SLASH, 7)
	assert_eq(profile.style_for(DeathPresentationProfile.Family.SLASH, 7), slash, "the same key dies the same way")
	assert_true(DeathPresentationProfile.SLASH_STYLES.has(slash), "an unauthored kit still draws from the built-in slash spread")
	var stab := profile.style_for(DeathPresentationProfile.Family.STAB, 7)
	assert_true(DeathPresentationProfile.STAB_STYLES.has(stab), "and the stab spread for a run-through")
	var seen := {}
	for key in 12:
		seen[profile.style_for(DeathPresentationProfile.Family.SLASH, key)] = true
	assert_true(seen.size() > 1, "keys spread across the styles rather than always picking one")


## Every death style the Wolf's profile maps to a clip names a clip both Wolf
## scenes (base and Training Gear) actually carry, so a run-through never asks
## for an animation the rig does not have.
func test_the_wolfs_death_styles_name_clips_its_scenes_carry() -> void:
	var kit := RiposteKits.build_catalog().resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER)
	assert_true(kit.death != null, "the Wolf authors its deaths")
	assert_eq(kit.death_clip(DeathPresentationProfile.STYLE_STAB_PITCH), &"death_stab", "a run-through has its own clip")
	assert_eq(kit.death_clip(DeathPresentationProfile.STYLE_DEAD_DROP), &"", "a cut-down falls back to the generic death")
	for scene_path: String in ["res://assets/generated/fighters/wolf.glb", "res://assets/generated/fighters/wolf_training.glb"]:
		var scene := (load(scene_path) as PackedScene).instantiate()
		var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for style: Variant in kit.death.style_clips:
			var clip := kit.death_clip(StringName(str(style)))
			assert_true(player.has_animation(clip), "%s carries %s for %s" % [scene_path.get_file(), clip, style])
		assert_true(player.has_animation(kit.clip_for(PresentationKit.ANIM_DEATH)), "and the generic death")
		assert_true(player.has_animation(kit.finisher_clip()), "%s carries the striker's run-through" % scene_path.get_file())
		scene.free()


func test_placeholder_audio_is_deterministic_and_cached() -> void:
	var first := PlaceholderAudio.cues()
	var second := PlaceholderAudio.cues()
	assert_true(first[PresentationKit.CUE_BLADE_STRONG] == second[PresentationKit.CUE_BLADE_STRONG], "streams generated once")
	var stream := first[PresentationKit.CUE_BODY_HEAVY] as AudioStreamWAV
	assert_eq(stream.mix_rate, PlaceholderAudio.MIX_RATE, "22.05 kHz")
	assert_true(stream.data.size() > 1000, "real sample data")
