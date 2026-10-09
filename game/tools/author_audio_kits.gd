extends SceneTree

## Writes the authored audio into the presentation kits from the files on
## disk, so adding a take is "drop the file in its family folder and rerun".
##
##   godot --headless --path game -s res://tools/author_audio_kits.gd
##
## Families are folders; every take in a folder becomes one variant, in file
## order, which is the order variant keys index into. Layers name which cues
## sound together from one event (transient + body + tail), rather than being
## pre-mixed into one file.
##
## See also: /docs/concepts/presentation.md

const AUDIO := "res://assets/presentation/audio/"
const WEAPON_KIT := "res://assets/presentation/weapons/bastard_sword/bastard_sword_kit.tres"
const FIGHTER_KIT := "res://assets/presentation/fighters/duelist/duelist_kit.tres"
const ARENA_KIT := "res://assets/presentation/arenas/standard/standard_arena_kit.tres"

const WEAPON_FAMILIES := {
	PresentationKit.CUE_SWING: "sfx/sword/swing",
	PresentationKit.CUE_CHARGE: "sfx/sword/charge",
	PresentationKit.CUE_BLADE_LIGHT: "sfx/blade/clash_light",
	PresentationKit.CUE_BLADE_SOLID: "sfx/blade/clash_solid",
	PresentationKit.CUE_BLADE_STRONG: "sfx/blade/clash_strong",
	PresentationKit.CUE_BIND: "sfx/blade/bind",
	PresentationKit.CUE_BODY_LIGHT: "sfx/body/hit_light",
	PresentationKit.CUE_BODY_HEAVY: "sfx/body/hit_heavy",
	PresentationKit.CUE_BODY_POKE: "sfx/body/poke",
	PresentationKit.CUE_BODY_THRUST: "sfx/body/thrust",
	PresentationKit.CUE_CRITICAL: "sfx/critical",
	PresentationKit.CUE_DASH: "sfx/dash",
	PresentationKit.CUE_FALL: "sfx/fall",
	PresentationKit.CUE_IMPACT_LOW: "sfx/layer:impact_low",
	PresentationKit.CUE_METAL_TAIL: "sfx/layer:metal_tail",
	PresentationKit.CUE_LETHAL_ACCENT: "sfx/layer:lethal_accent",
}
const WEAPON_LAYERS := {
	PresentationKit.CUE_BLADE_STRONG: [PresentationKit.CUE_METAL_TAIL, PresentationKit.CUE_IMPACT_LOW],
	PresentationKit.CUE_BODY_HEAVY: [PresentationKit.CUE_IMPACT_LOW],
	PresentationKit.CUE_BODY_THRUST: [PresentationKit.CUE_IMPACT_LOW],
}
const ARENA_FAMILIES := {
	PresentationKit.CUE_ROUND: "sfx/round:round_start",
	PresentationKit.CUE_ROUND_WIN: "sfx/round:round_win",
	PresentationKit.CUE_MUSIC: "music:arena_ambience",
}


func _init() -> void:
	var problems := PackedStringArray()
	var weapon := load(WEAPON_KIT) as PresentationKit
	weapon.audio_cues = _families(WEAPON_FAMILIES, problems)
	weapon.audio_layers = WEAPON_LAYERS.duplicate(true)
	_save(weapon, WEAPON_KIT, problems)
	var arena := load(ARENA_KIT) as PresentationKit
	arena.audio_cues = _families(ARENA_FAMILIES, problems)
	_save(arena, ARENA_KIT, problems)
	var fighter := load(FIGHTER_KIT) as PresentationKit
	var voice := FighterVoiceKit.new()
	voice.voice_id = &"voice.announcer.deep"
	voice.spoken_name = _first("voice/announcer:wolf", problems)
	fighter.voice = voice
	fighter.intro.spoken_override_first_slot_line = _first("voice/announcer:wold", problems)
	_save(fighter, FIGHTER_KIT, problems)
	var announcer := AnnouncerKit.new()
	announcer.announcer_id = &"announcer.deep"
	announcer.versus = _first("voice/announcer:versus", problems)
	announcer.duel = _first("voice/announcer:duel", problems)
	announcer.sting = _first("sfx/round:duel_sting", problems)
	_save(announcer, RiposteKits.ANNOUNCER_PATH, problems)
	var ui := UiThemeKit.new()
	ui.theme_id = &"ui.standard"
	ui.confirm = _takes("sfx/ui:confirm", problems)
	ui.back = _takes("sfx/ui:back", problems)
	ui.hover = _takes("sfx/ui:hover", problems)
	_save(ui, RiposteKits.UI_THEME_PATH, problems)
	for problem in problems:
		printerr("AUDIO_KIT_PROBLEM ", problem)
	print("AUDIO_KITS ", "FAIL" if problems.size() > 0 else "OK")
	quit(1 if problems.size() > 0 else 0)


func _families(families: Dictionary, problems: PackedStringArray) -> Dictionary:
	var cues := {}
	for cue: Variant in families:
		var takes := _takes(str(families[cue]), problems)
		if not takes.is_empty():
			cues[cue] = takes
	return cues


## "dir" lists every take in the folder; "dir:stem" only `stem_*`.
func _takes(spec: String, problems: PackedStringArray) -> Array[AudioStream]:
	var parts := spec.split(":")
	var dir := AUDIO + parts[0]
	var stem := parts[1] if parts.size() > 1 else ""
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".mp3") and (stem == "" or file.begins_with(stem)):
			files.append(file)
	files.sort()
	var takes: Array[AudioStream] = []
	for file in files:
		var stream := load(dir.path_join(file)) as AudioStream
		if stream != null:
			takes.append(stream)
	if takes.is_empty():
		problems.append("no takes for %s" % spec)
	return takes


func _first(spec: String, problems: PackedStringArray) -> AudioStream:
	var takes := _takes(spec, problems)
	return takes[0] if not takes.is_empty() else null


func _save(resource: Resource, path: String, problems: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		problems.append("could not save %s (%s)" % [path, error_string(error)])
