class_name PlayerSettings
extends RefCounted

## Player preferences (UX §54) persisted to user:// with ConfigFile.
##
## On Web, user:// is IndexedDB-backed: itch iframes with blocked third-party
## storage, private browsing, or quota errors can make it non-persistent.
## Failure degrades to defaults and never blocks play. Loaded values are
## sanitized; a stored file is untrusted input.
##
## See also: /docs/concepts/ux.md

const PATH := "user://settings.cfg"
const SILENT_DB := -80.0

## Stored file layout: [section] key.
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_GAMEPLAY := "gameplay"
const SECTION_CONTROLS := "controls"
const SECTION_MATCH := "match"
const KEY_MASTER := "master"
const KEY_MUSIC := "music"
const KEY_SFX := "sfx"
const KEY_FULLSCREEN := "fullscreen"
const KEY_REDUCED_MOTION := "reduced_motion"
const KEY_REDUCED_FLASH := "reduced_flash"
const KEY_CHARGE_INDICATOR := "show_charge_indicator"
const KEY_HIGH_CONTRAST := "high_contrast_weapons"
const KEY_SCREEN_SHAKE := "screen_shake"
const KEY_OPACITY := "opacity"
const KEY_HAPTICS := "haptics"
const KEY_DIFFICULTY := "difficulty"

enum ControlOpacity { LOW, MEDIUM, HIGH }

## Touch control alpha per ControlOpacity level.
const OPACITY_LEVELS: PackedFloat64Array = [0.2, 0.5, 0.85]

var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var fullscreen: bool = false
var reduced_motion: bool = false
var reduced_flash: bool = false
var show_charge_indicator: bool = false
var high_contrast_weapons: bool = false
var screen_shake: bool = true
var control_opacity: ControlOpacity = ControlOpacity.MEDIUM
var haptics: bool = true
var difficulty: MatchConfig.Difficulty = MatchConfig.Difficulty.MEDIUM
var persistence_available: bool = true


func load_from(path: String = PATH) -> void:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		persistence_available = true
		return
	if error != OK:
		persistence_available = false
		return
	persistence_available = true
	master_volume = _volume(config.get_value(SECTION_AUDIO, KEY_MASTER, master_volume), master_volume)
	music_volume = _volume(config.get_value(SECTION_AUDIO, KEY_MUSIC, music_volume), music_volume)
	sfx_volume = _volume(config.get_value(SECTION_AUDIO, KEY_SFX, sfx_volume), sfx_volume)
	fullscreen = _flag(config.get_value(SECTION_DISPLAY, KEY_FULLSCREEN, fullscreen), fullscreen)
	reduced_motion = _flag(config.get_value(SECTION_DISPLAY, KEY_REDUCED_MOTION, reduced_motion), reduced_motion)
	reduced_flash = _flag(config.get_value(SECTION_DISPLAY, KEY_REDUCED_FLASH, reduced_flash), reduced_flash)
	show_charge_indicator = _flag(config.get_value(SECTION_GAMEPLAY, KEY_CHARGE_INDICATOR, show_charge_indicator), show_charge_indicator)
	high_contrast_weapons = _flag(config.get_value(SECTION_GAMEPLAY, KEY_HIGH_CONTRAST, high_contrast_weapons), high_contrast_weapons)
	screen_shake = _flag(config.get_value(SECTION_GAMEPLAY, KEY_SCREEN_SHAKE, screen_shake), screen_shake)
	control_opacity = clampi(_whole(config.get_value(SECTION_CONTROLS, KEY_OPACITY, control_opacity), control_opacity), 0, ControlOpacity.HIGH) as ControlOpacity
	haptics = _flag(config.get_value(SECTION_CONTROLS, KEY_HAPTICS, haptics), haptics)
	difficulty = clampi(_whole(config.get_value(SECTION_MATCH, KEY_DIFFICULTY, difficulty), difficulty), 0, MatchConfig.Difficulty.HARD) as MatchConfig.Difficulty


func save_to(path: String = PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, KEY_MASTER, master_volume)
	config.set_value(SECTION_AUDIO, KEY_MUSIC, music_volume)
	config.set_value(SECTION_AUDIO, KEY_SFX, sfx_volume)
	config.set_value(SECTION_DISPLAY, KEY_FULLSCREEN, fullscreen)
	config.set_value(SECTION_DISPLAY, KEY_REDUCED_MOTION, reduced_motion)
	config.set_value(SECTION_DISPLAY, KEY_REDUCED_FLASH, reduced_flash)
	config.set_value(SECTION_GAMEPLAY, KEY_CHARGE_INDICATOR, show_charge_indicator)
	config.set_value(SECTION_GAMEPLAY, KEY_HIGH_CONTRAST, high_contrast_weapons)
	config.set_value(SECTION_GAMEPLAY, KEY_SCREEN_SHAKE, screen_shake)
	config.set_value(SECTION_CONTROLS, KEY_OPACITY, control_opacity)
	config.set_value(SECTION_CONTROLS, KEY_HAPTICS, haptics)
	config.set_value(SECTION_MATCH, KEY_DIFFICULTY, difficulty)
	persistence_available = config.save(path) == OK
	return persistence_available


func opacity_value() -> float:
	return OPACITY_LEVELS[control_opacity]


## Scale the layout's buses (default_bus_layout.tres) to the saved volumes.
func apply_audio() -> void:
	_apply_bus(AudioBuses.MASTER, master_volume)
	_apply_bus(AudioBuses.MUSIC, music_volume)
	_apply_bus(AudioBuses.SFX, sfx_volume)


static func _apply_bus(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(volume) if volume > 0.0 else SILENT_DB)


static func _volume(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number := float(value)
	return clampf(number, 0.0, 1.0) if is_finite(number) else fallback


static func _flag(value: Variant, fallback: bool) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


static func _whole(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else fallback
