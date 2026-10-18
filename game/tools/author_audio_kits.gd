extends SceneTree

## Writes the authored audio into the presentation kits from the files on
## disk, so adding a take is "drop the file in its family folder and rerun".
##
##   godot --headless --path game -s res://tools/author_audio_kits.gd
##
## The cue map is `AudioKitPlan`. This pass edits the kits that are already
## on disk. It does not replace an intro, a symbol, a victory profile, or an
## announcer caption in order to refresh a stream.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	var problems := PackedStringArray()
	var weapon := load(AudioKitPlan.WEAPON_KIT) as PresentationKit
	var arena := load(AudioKitPlan.ARENA_KIT) as PresentationKit
	var fighter := load(AudioKitPlan.FIGHTER_KIT) as PresentationKit
	var victory := load(AudioKitPlan.VICTORY_PROFILE) as FighterVictoryProfile
	var announcer := load(AudioKitPlan.ANNOUNCER_KIT) as AnnouncerKit
	var ui := load(AudioKitPlan.UI_THEME_KIT) as UiThemeKit
	AudioKitPlan.apply_weapon(weapon, problems)
	AudioKitPlan.apply_arena(arena, problems)
	AudioKitPlan.apply_fighter(fighter, problems)
	AudioKitPlan.apply_victory(victory, problems)
	AudioKitPlan.apply_announcer(announcer, problems)
	AudioKitPlan.apply_ui(ui, problems)
	_save(weapon, AudioKitPlan.WEAPON_KIT, problems)
	_save(arena, AudioKitPlan.ARENA_KIT, problems)
	_save(fighter, AudioKitPlan.FIGHTER_KIT, problems)
	_save(victory, AudioKitPlan.VICTORY_PROFILE, problems)
	_save(announcer, AudioKitPlan.ANNOUNCER_KIT, problems)
	_save(ui, AudioKitPlan.UI_THEME_KIT, problems)
	for problem in problems:
		printerr("AUDIO_KIT_PROBLEM ", problem)
	print("AUDIO_KITS ", "FAIL" if problems.size() > 0 else "OK")
	quit(1 if problems.size() > 0 else 0)


func _save(resource: Resource, path: String, problems: PackedStringArray) -> void:
	if resource == null:
		problems.append("missing %s" % path)
		return
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		problems.append("could not save %s (%s)" % [path, error_string(error)])
