class_name AudioKitPlan
extends RefCounted

## The cue map `author_audio_kits.gd` writes onto the kits that already exist.
## A second apply changes nothing that was already right, and it does not
## replace the intro, the symbol, the victory profile, or the announcer's
## captions. The arena kit owns the match horn and the crowd gasp.
##
## See also: /docs/reference/assets.md

const AUDIO := "res://assets/presentation/audio/"
const ARENA_KIT := "res://assets/presentation/arenas/standard/standard_arena_kit.tres"
const FIGHTER_KIT := "res://assets/presentation/fighters/duelist/duelist_kit.tres"
const WEAPON_KIT := "res://assets/presentation/weapons/bastard_sword/bastard_sword_kit.tres"
const VICTORY_PROFILE := "res://assets/presentation/fighters/duelist/duelist_victory.tres"
const ANNOUNCER_KIT := "res://assets/presentation/voice/announcer/announcer_kit.tres"
const UI_THEME_KIT := "res://assets/presentation/ui/ui_theme_kit.tres"
const MATCH_LINES := 5

const ARENA_SPECS := {
	PresentationKit.CUE_MUSIC: "music:arena_theme",
	PresentationKit.CUE_CROWD_BED: "crowd:bed",
	PresentationKit.CUE_CROWD_CHEER: "crowd:cheer",
	PresentationKit.CUE_CROWD_STRONG: "crowd:cheer_strong",
	PresentationKit.CUE_CROWD_SETPOINT: "crowd:setpoint",
	PresentationKit.CUE_CROWD_VICTORY: "crowd:victory",
	PresentationKit.CUE_CROWD_GASP: "crowd:gasp",
	## `_01` only. `match_horn_02.mp3` is on disk and unheard, so it does not
	## rotate in until someone has listened to it.
	PresentationKit.CUE_MATCH_HORN: "sfx/arena:match_horn_01",
	PresentationKit.CUE_ROUND: "sfx/round:round_start",
	PresentationKit.CUE_ROUND_WIN: "sfx/round:round_win",
	PresentationKit.CUE_IMPACT_STEEL_STONE: "sfx/impact:steel_stone",
	PresentationKit.CUE_IMPACT_STEEL_WOOD: "sfx/impact:steel_wood",
}
const CHARACTER_CALL_SPEC := "voice:wolf_howl"
const CROWD_CHANT_SPEC := "crowd:wolf_chant"
## Own take. Absent until `crowd/wolf_name.mp3` is authored. Not the shout.
const NAME_PHRASE_SPEC := "crowd:wolf_name"
const SPOKEN_NAME_SPEC := "voice/announcer:wolf"
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


static func arena_specs() -> Dictionary:
	return ARENA_SPECS.duplicate()


## Write the plan onto kits that are already loaded. Missing subresources are
## created once. A subresource that is already there is edited, not replaced.
static func apply_weapon(kit: PresentationKit, problems: PackedStringArray) -> void:
	_assign_cues(kit, WEAPON_FAMILIES, problems)
	kit.audio_layers = WEAPON_LAYERS.duplicate(true)


static func apply_arena(kit: PresentationKit, problems: PackedStringArray) -> void:
	_assign_cues(kit, ARENA_SPECS, problems)


static func apply_fighter(kit: PresentationKit, problems: PackedStringArray) -> void:
	if kit.voice == null:
		kit.voice = FighterVoiceKit.new()
	kit.voice.voice_id = &"voice.announcer.deep"
	_set_stream(kit.voice, "spoken_name", takes_for(SPOKEN_NAME_SPEC, problems))
	_set_stream(kit, "character_call", takes_for(CHARACTER_CALL_SPEC, problems))
	_set_stream(kit, "crowd_chant", takes_for(CROWD_CHANT_SPEC, problems))
	_set_stream(kit, "name_phrase", takes_for(NAME_PHRASE_SPEC, problems))


static func apply_victory(profile: FighterVictoryProfile, problems: PackedStringArray) -> void:
	_set_stream(profile, "announcer_line", takes_for("voice/announcer:wolf_wins", problems))
	_set_stream(profile, "sting", takes_for("music:wolf_victory", problems))


static func apply_announcer(kit: AnnouncerKit, problems: PackedStringArray) -> void:
	kit.announcer_id = &"announcer.deep"
	_set_stream(kit, "versus", takes_for("voice/announcer:versus", problems))
	_set_stream(kit, "sting", takes_for("sfx/round:duel_sting", problems))
	var lines: Array[AudioStream] = []
	for number in range(1, MATCH_LINES + 1):
		var takes := takes_for("voice/announcer:match_%d" % number, problems)
		if not takes.is_empty():
			lines.append(takes[0])
	if not _same(kit.match_numbers, lines):
		kit.match_numbers = lines
	_set_stream(kit, "fight", takes_for("voice/announcer:fight", problems))


static func apply_ui(kit: UiThemeKit, problems: PackedStringArray) -> void:
	kit.theme_id = &"ui.standard"
	_set_takes(kit, "confirm", takes_for("sfx/ui:confirm", problems))
	_set_takes(kit, "back", takes_for("sfx/ui:back", problems))
	_set_takes(kit, "hover", takes_for("sfx/ui:hover", problems))


static func takes_for(spec: String, problems: PackedStringArray) -> Array[AudioStream]:
	var parts := spec.split(":")
	var dir := AUDIO + parts[0]
	var stem := parts[1] if parts.size() > 1 else ""
	var take := RegEx.create_from_string("^%s(_\\d+)?\\.mp3$" % stem)
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".mp3") and (stem == "" or take.search(file) != null):
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


static func _assign_cues(kit: PresentationKit, specs: Dictionary, problems: PackedStringArray) -> void:
	var wanted := {}
	for cue: Variant in specs:
		var takes := takes_for(str(specs[cue]), problems)
		if takes.is_empty():
			continue
		wanted[cue] = true
		if not _same(kit.audio_cues.get(cue), takes):
			kit.audio_cues[cue] = takes
	var drop: Array = []
	for cue: Variant in kit.audio_cues:
		if not wanted.has(cue):
			drop.append(cue)
	for cue: Variant in drop:
		kit.audio_cues.erase(cue)


static func _set_stream(target: Object, property: String, takes: Array[AudioStream]) -> void:
	if takes.is_empty():
		return
	if target.get(property) != takes[0]:
		target.set(property, takes[0])


static func _set_takes(target: Object, property: String, takes: Array[AudioStream]) -> void:
	if takes.is_empty():
		return
	if not _same(target.get(property), takes):
		target.set(property, takes)


static func _same(current: Variant, takes: Array[AudioStream]) -> bool:
	if current is AudioStream:
		return takes.size() == 1 and current == takes[0]
	if current is Array:
		var rows: Array = current
		if rows.size() != takes.size():
			return false
		for index in takes.size():
			if rows[index] != takes[index]:
				return false
		return true
	return false
