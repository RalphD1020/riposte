class_name RiposteKits
extends RefCounted

## MVP-0 presentation content: identity → kit bindings and the duel camera.
##
## To replace the primitive look of an identity (e.g. with a Blender model),
## author a PresentationKit .tres at the identity's path in AUTHORED_KIT_PATHS
## whose `scene` points at the model's wrapper scene. Authored kits load
## first; the primitive factory kit below is the fallback for anything not yet
## authored. Nothing in MatchPresenter or the directors changes.
##
## See also: /docs/concepts/presentation.md

const AUTHORED_KIT_PATHS: Dictionary = {
	ContentIds.FIGHTER_DUELIST: "res://assets/presentation/fighters/duelist/duelist_kit.tres",
	ContentIds.WEAPON_BASTARD_SWORD: "res://assets/presentation/weapons/bastard_sword/bastard_sword_kit.tres",
	ContentIds.ARENA_STANDARD: "res://assets/presentation/arenas/standard/standard_arena_kit.tres",
}


## Cosmetic skin ids the settings can pick. Ids, not paths, are what persist.
const SKIN_DUELIST_TRAINING := &"skin.duelist.training"
const SKIN_BASTARD_SWORD_TRAINING := &"skin.bastard_sword.training"

## Match-wide and cosmetic layers. All optional: a missing file is the default.
const ANNOUNCER_PATH := "res://assets/presentation/voice/announcer/announcer_kit.tres"
const UI_THEME_PATH := "res://assets/presentation/ui/ui_theme_kit.tres"
const VFX_STYLE_PATH := "res://assets/presentation/vfx/vfx_style_kit.tres"
const FIGHTER_SKIN_PATHS: PackedStringArray = [
	"res://assets/presentation/skins/wolf_training/wolf_training_skin.tres",
]
const WEAPON_SKIN_PATHS: PackedStringArray = [
	"res://assets/presentation/skins/bastard_sword_training/bastard_sword_training_skin.tres",
]


static func build_catalog(fail_closed: bool = true) -> PresentationKitCatalog:
	var catalog := catalog_from(load_authored(), fail_closed)
	for path in FIGHTER_SKIN_PATHS:
		catalog.register_fighter_skin(_optional(path) as FighterSkinKit)
	for path in WEAPON_SKIN_PATHS:
		catalog.register_weapon_skin(_optional(path) as WeaponSkinKit)
	return catalog


static func announcer() -> AnnouncerKit:
	var kit := _optional(ANNOUNCER_PATH) as AnnouncerKit
	return kit if kit != null else AnnouncerKit.new()


static func ui_theme() -> UiThemeKit:
	var kit := _optional(UI_THEME_PATH) as UiThemeKit
	return kit if kit != null else UiThemeKit.new()


static func vfx_style() -> VfxStyleKit:
	var kit := _optional(VFX_STYLE_PATH) as VfxStyleKit
	return kit if kit != null else VfxStyleKit.new()


static func match_loadout(arena: PresentationKit) -> MatchPresentationLoadout:
	return MatchPresentationLoadout.of(arena, announcer(), ui_theme(), vfx_style())


static func _optional(path: String) -> Resource:
	return load(path) if ResourceLoader.exists(path) else null


## Authored kits win; factory kits fill the gaps — whole identities that are
## not authored yet, and any cue, layer, or intro an authored kit leaves out,
## so a half-authored identity is never silent.
static func catalog_from(authored: Array[PresentationKit], fail_closed: bool) -> PresentationKitCatalog:
	var catalog := PresentationKitCatalog.new()
	catalog.fail_closed = fail_closed
	var factory := {}
	for kit in factory_kits():
		factory[kit.id] = kit
	for kit in authored:
		catalog.register(_filled(kit, factory.get(kit.id) as PresentationKit))
	for kit_id: StringName in factory:
		if not catalog.has(kit_id):
			catalog.register(factory[kit_id])
	return catalog


static func _filled(kit: PresentationKit, fallback: PresentationKit) -> PresentationKit:
	if fallback == null:
		return kit
	var filled := kit.duplicate() as PresentationKit
	filled.audio_cues = kit.audio_cues.duplicate()
	for cue: Variant in fallback.audio_cues:
		if not filled.has_audio(StringName(str(cue))):
			filled.audio_cues[cue] = fallback.audio_cues[cue]
	if filled.intro == null:
		filled.intro = fallback.intro
	return filled


static func load_authored() -> Array[PresentationKit]:
	var kits: Array[PresentationKit] = []
	for kit_id: StringName in AUTHORED_KIT_PATHS:
		var path := str(AUTHORED_KIT_PATHS[kit_id])
		if ResourceLoader.exists(path):
			var kit := load(path) as PresentationKit
			if kit != null and kit.id == kit_id:
				kits.append(kit)
	return kits


static func required_ids() -> Array[StringName]:
	return [ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD, ContentIds.ARENA_STANDARD]


static func factory_kits() -> Array[PresentationKit]:
	var audio := PlaceholderAudio.cues()
	var fighter := PresentationKit.new()
	fighter.id = ContentIds.FIGHTER_DUELIST
	fighter.primitive = PresentationKit.PRIMITIVE_FIGHTER
	fighter.body_height = 1.4
	fighter.intro = duelist_intro()
	var sword := PresentationKit.new()
	sword.id = ContentIds.WEAPON_BASTARD_SWORD
	sword.primitive = PresentationKit.PRIMITIVE_BLADE
	sword.blade_width = 0.05
	sword.blade_height = 1.0
	sword.trail_samples = 10
	sword.trail_min_speed = 4.0
	sword.vfx_cues = PackedStringArray([PresentationKit.VFX_TRAIL, PresentationKit.VFX_SPARK, PresentationKit.VFX_IMPACT])
	for cue: StringName in [
		PresentationKit.CUE_SWING,
		PresentationKit.CUE_CHARGE,
		PresentationKit.CUE_BLADE_LIGHT,
		PresentationKit.CUE_BLADE_SOLID,
		PresentationKit.CUE_BLADE_STRONG,
		PresentationKit.CUE_BIND,
		PresentationKit.CUE_BODY_LIGHT,
		PresentationKit.CUE_BODY_HEAVY,
		PresentationKit.CUE_BODY_POKE,
		PresentationKit.CUE_BODY_THRUST,
		PresentationKit.CUE_CRITICAL,
	]:
		sword.audio_cues[cue] = audio[cue]
	var arena := PresentationKit.new()
	arena.id = ContentIds.ARENA_STANDARD
	arena.primitive = PresentationKit.PRIMITIVE_ARENA
	arena.audio_cues[PresentationKit.CUE_ROUND] = audio[PresentationKit.CUE_ROUND]
	arena.audio_cues[PresentationKit.CUE_MUSIC] = audio[PresentationKit.CUE_MUSIC]
	return [fighter, sword, arena]


## Wolf, the baseline duelist. Introduced first, the announcer reads him as
## "Wold" — a deliberate bit that lives here, in content, and nowhere else.
static func duelist_intro() -> FighterIntroProfile:
	var intro := FighterIntroProfile.new()
	intro.display_name = "WOLF"
	intro.spoken_name = "Wolf."
	intro.spoken_override_first_slot = "Wold."
	intro.intro_clip = &"flourish"
	return intro


static func camera_profile() -> CameraProfile:
	var profile := CameraProfile.new()
	profile.pitch_degrees = 56.0
	profile.fov_degrees = 40.0
	profile.base_distance = 8.0
	profile.separation_gain = 1.1
	profile.min_distance = 8.5
	profile.max_distance = 15.0
	profile.follow_rate = 6.0
	profile.zoom_rate = 3.0
	profile.touch_focus_bias = 1.3
	profile.impulse_decay = 14.0
	profile.max_impulse = 0.22
	return profile
