extends TestCase

## SETTINGS: persistence round-trips, degrades gracefully, and sanitizes
## untrusted stored values (UX §54).
##
## See also: /docs/concepts/ux.md

const PATH := "user://riposte_test_settings.cfg"


func _init() -> void:
	suite_name = "SETTINGS"


func _cleanup() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_defaults_are_safe() -> void:
	var settings := PlayerSettings.new()
	assert_true(settings.screen_shake, "shake on by default")
	assert_false(settings.reduced_motion, "full motion by default")
	assert_eq(settings.difficulty, MatchConfig.Difficulty.MEDIUM, "medium by default")
	assert_eq(settings.control_opacity, PlayerSettings.ControlOpacity.MEDIUM, "medium opacity")


func test_every_field_round_trips() -> void:
	_cleanup()
	var saved := PlayerSettings.new()
	saved.master_volume = 0.4
	saved.sfx_volume = 0.0
	saved.reduced_motion = true
	saved.reduced_flash = true
	saved.show_charge_indicator = true
	saved.high_contrast_weapons = true
	saved.screen_shake = false
	saved.control_opacity = PlayerSettings.ControlOpacity.HIGH
	saved.haptics = false
	saved.difficulty = MatchConfig.Difficulty.HARD
	assert_true(saved.save_to(PATH), "saved")
	var loaded := PlayerSettings.new()
	loaded.load_from(PATH)
	assert_eq(loaded.master_volume, 0.4, "master volume")
	assert_eq(loaded.sfx_volume, 0.0, "sfx volume")
	assert_true(loaded.reduced_motion and loaded.reduced_flash, "motion and flash")
	assert_true(loaded.show_charge_indicator and loaded.high_contrast_weapons, "gameplay aids")
	assert_false(loaded.screen_shake, "shake")
	assert_eq(loaded.control_opacity, PlayerSettings.ControlOpacity.HIGH, "opacity")
	assert_false(loaded.haptics, "haptics")
	assert_eq(loaded.difficulty, MatchConfig.Difficulty.HARD, "difficulty remembered")
	_cleanup()


func test_missing_file_keeps_defaults() -> void:
	_cleanup()
	var settings := PlayerSettings.new()
	settings.load_from(PATH)
	assert_true(settings.persistence_available, "first run is not an error")
	assert_true(settings.screen_shake, "defaults kept")


func test_hostile_values_are_sanitized() -> void:
	_cleanup()
	var config := ConfigFile.new()
	config.set_value(PlayerSettings.SECTION_AUDIO, PlayerSettings.KEY_MASTER, 5.0)
	config.set_value(PlayerSettings.SECTION_AUDIO, PlayerSettings.KEY_MUSIC, "loud")
	config.set_value(PlayerSettings.SECTION_DISPLAY, PlayerSettings.KEY_FULLSCREEN, "yes")
	config.set_value(PlayerSettings.SECTION_CONTROLS, PlayerSettings.KEY_OPACITY, 99)
	config.set_value(PlayerSettings.SECTION_MATCH, PlayerSettings.KEY_DIFFICULTY, -4)
	assert_eq(config.save(PATH), OK, "fixture: hostile file written")
	var settings := PlayerSettings.new()
	settings.load_from(PATH)
	assert_eq(settings.master_volume, 1.0, "volume clamped to 1")
	assert_eq(settings.music_volume, 0.7, "wrong type keeps the default")
	assert_false(settings.fullscreen, "non-bool keeps the default")
	assert_eq(settings.control_opacity, PlayerSettings.ControlOpacity.HIGH, "enum clamped high")
	assert_eq(settings.difficulty, MatchConfig.Difficulty.EASY, "enum clamped low")
	_cleanup()


func test_unreadable_storage_degrades_to_defaults() -> void:
	var blocked := "user://riposte_blocked_settings"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
	var settings := PlayerSettings.new()
	settings.load_from(blocked)
	assert_false(settings.persistence_available, "a path that cannot be read is reported as unavailable")
	assert_true(settings.screen_shake, "defaults kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))


func test_audio_buses_follow_volumes() -> void:
	var sfx := AudioServer.get_bus_index(AudioBuses.SFX)
	var music := AudioServer.get_bus_index(AudioBuses.MUSIC)
	assert_true(sfx > 0 and music > 0, "default_bus_layout.tres defines Music and SFX before anything runs")
	assert_eq(AudioServer.get_bus_send(sfx), AudioBuses.MASTER, "SFX sends to Master")
	assert_eq(AudioServer.get_bus_send(music), AudioBuses.MASTER, "Music sends to Master")
	var settings := PlayerSettings.new()
	settings.sfx_volume = 0.0
	settings.apply_audio()
	assert_true(AudioServer.is_bus_mute(sfx), "zero volume mutes the bus")
	settings.sfx_volume = 1.0
	settings.apply_audio()
	assert_false(AudioServer.is_bus_mute(sfx), "restored")
	assert_near(AudioServer.get_bus_volume_db(sfx), 0.0, 1e-6, "full volume is 0 dB")


func test_opacity_levels_are_ordered() -> void:
	var settings := PlayerSettings.new()
	settings.control_opacity = PlayerSettings.ControlOpacity.LOW
	var low := settings.opacity_value()
	settings.control_opacity = PlayerSettings.ControlOpacity.HIGH
	var high := settings.opacity_value()
	assert_true(low < 0.5 and 0.5 < high, "low < medium < high")
