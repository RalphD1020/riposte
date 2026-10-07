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


static func build_catalog(fail_closed: bool = true) -> PresentationKitCatalog:
	return catalog_from(load_authored(), fail_closed)


## Authored kits win; factory kits fill the gaps.
static func catalog_from(authored: Array[PresentationKit], fail_closed: bool) -> PresentationKitCatalog:
	var catalog := PresentationKitCatalog.new()
	catalog.fail_closed = fail_closed
	for kit in authored:
		catalog.register(kit)
	for kit in factory_kits():
		if not catalog.has(kit.id):
			catalog.register(kit)
	return catalog


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
