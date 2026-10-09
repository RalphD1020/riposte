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
const ID_MAX_LENGTH := 64
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
const KEY_VOICE := "voice"
const KEY_CAPTIONS := "captions"
const SECTION_LOOK := "look"
const KEY_FIGHTER_SKIN := "fighter_skin"
const KEY_WEAPON_SKIN := "weapon_skin"
const KEY_FULLSCREEN := "fullscreen"
const KEY_REDUCED_MOTION := "reduced_motion"
const KEY_REDUCED_FLASH := "reduced_flash"
const KEY_CHARGE_INDICATOR := "show_charge_indicator"
const KEY_HIGH_CONTRAST := "high_contrast_weapons"
const KEY_SCREEN_SHAKE := "screen_shake"
const KEY_TRAIL := "trail_strength"
const KEY_SWEET_SPOT := "sweet_spot"
const KEY_OPACITY := "opacity"
const KEY_HAPTICS := "haptics"
const KEY_DIFFICULTY := "difficulty"
const KEY_FLASH_INTENSITY := "flash_intensity"
const KEY_PARTICLE_INTENSITY := "particle_intensity"
const KEY_COMBAT_READABILITY := "combat_readability"

enum ControlOpacity { LOW, MEDIUM, HIGH }
enum TrailStrength { OFF, SUBTLE, FULL }
enum SweetSpot { OFF, STANDARD, STRONG }
enum CombatReadability { NORMAL, ENHANCED }

## Touch control alpha per ControlOpacity level.
const OPACITY_LEVELS: PackedFloat64Array = [0.2, 0.5, 0.85]
## Blade ribbon prominence and sweet-region emphasis per level. `STRONG`
## exceeds 1 deliberately: accessibility may draw a cue more loudly, and
## nothing here can move the region, the damage, or the timing (UX §54).
const TRAIL_LEVELS: PackedFloat64Array = [0.0, 0.55, 1.0]
const SWEET_SPOT_LEVELS: PackedFloat64Array = [0.0, 1.0, 1.8]

var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var voice_volume: float = 1.0
## Announcer captions. On by default: the intro must read with sound off.
var captions: bool = true
## Cosmetic skin ids; empty is the base look. Unknown ids also resolve to it.
var fighter_skin: String = ""
var weapon_skin: String = ""
var fullscreen: bool = false
var reduced_motion: bool = false
var reduced_flash: bool = false
var show_charge_indicator: bool = false
var high_contrast_weapons: bool = false
var screen_shake: float = 1.0
var flash_intensity: float = 1.0
var particle_intensity: float = 1.0
var combat_readability: CombatReadability = CombatReadability.NORMAL
var trail_strength: TrailStrength = TrailStrength.FULL
var sweet_spot: SweetSpot = SweetSpot.STANDARD
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
	voice_volume = _volume(config.get_value(SECTION_AUDIO, KEY_VOICE, voice_volume), voice_volume)
	captions = _flag(config.get_value(SECTION_AUDIO, KEY_CAPTIONS, captions), captions)
	fighter_skin = _id(config.get_value(SECTION_LOOK, KEY_FIGHTER_SKIN, fighter_skin))
	weapon_skin = _id(config.get_value(SECTION_LOOK, KEY_WEAPON_SKIN, weapon_skin))
	fullscreen = _flag(config.get_value(SECTION_DISPLAY, KEY_FULLSCREEN, fullscreen), fullscreen)
	reduced_motion = _flag(config.get_value(SECTION_DISPLAY, KEY_REDUCED_MOTION, reduced_motion), reduced_motion)
	reduced_flash = _flag(config.get_value(SECTION_DISPLAY, KEY_REDUCED_FLASH, reduced_flash), reduced_flash)
	show_charge_indicator = _flag(config.get_value(SECTION_GAMEPLAY, KEY_CHARGE_INDICATOR, show_charge_indicator), show_charge_indicator)
	high_contrast_weapons = _flag(config.get_value(SECTION_GAMEPLAY, KEY_HIGH_CONTRAST, high_contrast_weapons), high_contrast_weapons)
	screen_shake = _shake(config.get_value(SECTION_GAMEPLAY, KEY_SCREEN_SHAKE, screen_shake))
	flash_intensity = _volume(config.get_value(SECTION_GAMEPLAY, KEY_FLASH_INTENSITY, flash_intensity), flash_intensity)
	particle_intensity = _volume(config.get_value(SECTION_GAMEPLAY, KEY_PARTICLE_INTENSITY, particle_intensity), particle_intensity)
	combat_readability = clampi(_whole(config.get_value(SECTION_GAMEPLAY, KEY_COMBAT_READABILITY, combat_readability), combat_readability), 0, CombatReadability.ENHANCED) as CombatReadability
	trail_strength = clampi(_whole(config.get_value(SECTION_GAMEPLAY, KEY_TRAIL, trail_strength), trail_strength), 0, TrailStrength.FULL) as TrailStrength
	sweet_spot = clampi(_whole(config.get_value(SECTION_GAMEPLAY, KEY_SWEET_SPOT, sweet_spot), sweet_spot), 0, SweetSpot.STRONG) as SweetSpot
	control_opacity = clampi(_whole(config.get_value(SECTION_CONTROLS, KEY_OPACITY, control_opacity), control_opacity), 0, ControlOpacity.HIGH) as ControlOpacity
	haptics = _flag(config.get_value(SECTION_CONTROLS, KEY_HAPTICS, haptics), haptics)
	difficulty = clampi(_whole(config.get_value(SECTION_MATCH, KEY_DIFFICULTY, difficulty), difficulty), 0, MatchConfig.Difficulty.HARD) as MatchConfig.Difficulty


func save_to(path: String = PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, KEY_MASTER, master_volume)
	config.set_value(SECTION_AUDIO, KEY_MUSIC, music_volume)
	config.set_value(SECTION_AUDIO, KEY_SFX, sfx_volume)
	config.set_value(SECTION_AUDIO, KEY_VOICE, voice_volume)
	config.set_value(SECTION_AUDIO, KEY_CAPTIONS, captions)
	config.set_value(SECTION_LOOK, KEY_FIGHTER_SKIN, fighter_skin)
	config.set_value(SECTION_LOOK, KEY_WEAPON_SKIN, weapon_skin)
	config.set_value(SECTION_DISPLAY, KEY_FULLSCREEN, fullscreen)
	config.set_value(SECTION_DISPLAY, KEY_REDUCED_MOTION, reduced_motion)
	config.set_value(SECTION_DISPLAY, KEY_REDUCED_FLASH, reduced_flash)
	config.set_value(SECTION_GAMEPLAY, KEY_CHARGE_INDICATOR, show_charge_indicator)
	config.set_value(SECTION_GAMEPLAY, KEY_HIGH_CONTRAST, high_contrast_weapons)
	config.set_value(SECTION_GAMEPLAY, KEY_SCREEN_SHAKE, screen_shake)
	config.set_value(SECTION_GAMEPLAY, KEY_FLASH_INTENSITY, flash_intensity)
	config.set_value(SECTION_GAMEPLAY, KEY_PARTICLE_INTENSITY, particle_intensity)
	config.set_value(SECTION_GAMEPLAY, KEY_COMBAT_READABILITY, combat_readability)
	config.set_value(SECTION_GAMEPLAY, KEY_TRAIL, trail_strength)
	config.set_value(SECTION_GAMEPLAY, KEY_SWEET_SPOT, sweet_spot)
	config.set_value(SECTION_CONTROLS, KEY_OPACITY, control_opacity)
	config.set_value(SECTION_CONTROLS, KEY_HAPTICS, haptics)
	config.set_value(SECTION_MATCH, KEY_DIFFICULTY, difficulty)
	persistence_available = config.save(path) == OK
	return persistence_available


func opacity_value() -> float:
	return OPACITY_LEVELS[control_opacity]


func trail_value() -> float:
	return TRAIL_LEVELS[trail_strength]


func sweet_spot_value() -> float:
	return SWEET_SPOT_LEVELS[sweet_spot]


## Scale the layout's buses (default_bus_layout.tres) to the saved volumes.
func apply_audio() -> void:
	_apply_bus(AudioBuses.MASTER, master_volume)
	_apply_bus(AudioBuses.MUSIC, music_volume)
	_apply_bus(AudioBuses.SFX, sfx_volume)
	_apply_bus(AudioBuses.VOICE, voice_volume)


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


## A stored id is untrusted text: short, identifier-shaped, or nothing.
static func _id(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text := str(value)
	return text if text.length() <= ID_MAX_LENGTH and text.replace(".", "_").is_valid_ascii_identifier() else ""


static func _whole(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else fallback


## Migrate screen_shake from bool (legacy) to float. `true` → 1.0, `false` → 0.0.
static func _shake(value: Variant) -> float:
	if typeof(value) == TYPE_BOOL:
		return 1.0 if bool(value) else 0.0
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		var number := float(value)
		return clampf(number, 0.0, 1.0) if is_finite(number) else 1.0
	return 1.0
