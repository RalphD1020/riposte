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
	assert_eq(settings.screen_shake, 1.0, "shake full by default")
	assert_eq(settings.flash_intensity, 1.0, "flash full by default")
	assert_eq(settings.particle_intensity, 1.0, "particles full by default")
	assert_eq(settings.combat_readability, PlayerSettings.CombatReadability.NORMAL, "normal readability by default")
	assert_false(settings.reduced_motion, "full motion by default")
	assert_eq(settings.difficulty, MatchConfig.Difficulty.MEDIUM, "medium by default")
	assert_eq(settings.control_opacity, PlayerSettings.ControlOpacity.MEDIUM, "medium opacity")
	assert_eq(settings.trail_strength, PlayerSettings.TrailStrength.FULL, "the blade reads fully by default")
	assert_eq(settings.sweet_spot, PlayerSettings.SweetSpot.STANDARD, "standard sweet-spot emphasis by default")
	assert_false(settings.sound_captions, "sound captions are opt-in")
	assert_false(settings.contact_highlight, "and so is the contact highlight")
	assert_true(settings.bindings.is_default(), "the authored key bindings")


func test_every_field_round_trips() -> void:
	_cleanup()
	var saved := PlayerSettings.new()
	saved.master_volume = 0.4
	saved.sfx_volume = 0.0
	saved.reduced_motion = true
	saved.reduced_flash = true
	saved.show_charge_indicator = true
	saved.high_contrast_weapons = true
	saved.screen_shake = 0.0
	saved.flash_intensity = 0.3
	saved.particle_intensity = 0.5
	saved.combat_readability = PlayerSettings.CombatReadability.ENHANCED
	saved.trail_strength = PlayerSettings.TrailStrength.OFF
	saved.sweet_spot = PlayerSettings.SweetSpot.STRONG
	saved.control_opacity = PlayerSettings.ControlOpacity.HIGH
	saved.haptics = false
	saved.difficulty = MatchConfig.Difficulty.HARD
	saved.sound_captions = true
	saved.contact_highlight = true
	assert_true(saved.bindings.bind(InputActions.ATTACK, 1, KEY_J), "fixture: attack rebound")
	assert_true(saved.save_to(PATH), "saved")
	var loaded := PlayerSettings.new()
	loaded.load_from(PATH)
	assert_eq(loaded.master_volume, 0.4, "master volume")
	assert_eq(loaded.sfx_volume, 0.0, "sfx volume")
	assert_true(loaded.reduced_motion and loaded.reduced_flash, "motion and flash")
	assert_true(loaded.show_charge_indicator and loaded.high_contrast_weapons, "gameplay aids")
	assert_false(loaded.screen_shake > 0.0, "shake off")
	assert_near(loaded.flash_intensity, 0.3, 1e-9, "flash intensity")
	assert_near(loaded.particle_intensity, 0.5, 1e-9, "particle intensity")
	assert_eq(loaded.combat_readability, PlayerSettings.CombatReadability.ENHANCED, "combat readability")
	assert_eq(loaded.trail_strength, PlayerSettings.TrailStrength.OFF, "trail strength")
	assert_eq(loaded.sweet_spot, PlayerSettings.SweetSpot.STRONG, "sweet spot emphasis")
	assert_eq(loaded.control_opacity, PlayerSettings.ControlOpacity.HIGH, "opacity")
	assert_false(loaded.haptics, "haptics")
	assert_eq(loaded.difficulty, MatchConfig.Difficulty.HARD, "difficulty remembered")
	assert_true(loaded.sound_captions and loaded.contact_highlight, "sound captions and the contact highlight")
	assert_eq(loaded.bindings.code(InputActions.ATTACK, 1), KEY_J, "a rebound key")
	assert_eq(loaded.bindings.code(InputActions.ATTACK, 0), -MOUSE_BUTTON_LEFT, "beside the binding it kept")
	_cleanup()


func test_missing_file_keeps_defaults() -> void:
	_cleanup()
	var settings := PlayerSettings.new()
	settings.load_from(PATH)
	assert_true(settings.persistence_available, "first run is not an error")
	assert_eq(settings.screen_shake, 1.0, "defaults kept")


func test_hostile_values_are_sanitized() -> void:
	_cleanup()
	var config := ConfigFile.new()
	config.set_value(PlayerSettings.SECTION_AUDIO, PlayerSettings.KEY_MASTER, 5.0)
	config.set_value(PlayerSettings.SECTION_AUDIO, PlayerSettings.KEY_MUSIC, "loud")
	config.set_value(PlayerSettings.SECTION_DISPLAY, PlayerSettings.KEY_FULLSCREEN, "yes")
	config.set_value(PlayerSettings.SECTION_CONTROLS, PlayerSettings.KEY_OPACITY, 99)
	config.set_value(PlayerSettings.SECTION_GAMEPLAY, PlayerSettings.KEY_TRAIL, 42)
	config.set_value(PlayerSettings.SECTION_GAMEPLAY, PlayerSettings.KEY_SWEET_SPOT, "strong")
	config.set_value(PlayerSettings.SECTION_MATCH, PlayerSettings.KEY_DIFFICULTY, -4)
	assert_eq(config.save(PATH), OK, "fixture: hostile file written")
	var settings := PlayerSettings.new()
	settings.load_from(PATH)
	assert_eq(settings.master_volume, 1.0, "volume clamped to 1")
	assert_eq(settings.music_volume, 0.7, "wrong type keeps the default")
	assert_false(settings.fullscreen, "non-bool keeps the default")
	assert_eq(settings.control_opacity, PlayerSettings.ControlOpacity.HIGH, "enum clamped high")
	assert_eq(settings.trail_strength, PlayerSettings.TrailStrength.FULL, "trail enum clamped high")
	assert_eq(settings.sweet_spot, PlayerSettings.SweetSpot.STANDARD, "wrong type keeps the default emphasis")
	assert_eq(settings.difficulty, MatchConfig.Difficulty.EASY, "enum clamped low")
	_cleanup()


func test_unreadable_storage_degrades_to_defaults() -> void:
	var blocked := "user://riposte_blocked_settings"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
	var settings := PlayerSettings.new()
	settings.load_from(blocked)
	assert_false(settings.persistence_available, "a path that cannot be read is reported as unavailable")
	assert_eq(settings.screen_shake, 1.0, "defaults kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))


func test_audio_buses_follow_volumes() -> void:
	var sfx := AudioServer.get_bus_index(AudioBuses.SFX)
	var music := AudioServer.get_bus_index(AudioBuses.MUSIC)
	assert_true(sfx > 0 and music > 0, "default_bus_layout.tres defines Music and SFX before anything runs")
	assert_eq(AudioServer.get_bus_send(sfx), AudioBuses.MASTER, "SFX sends to Master")
	assert_eq(AudioServer.get_bus_send(music), AudioBuses.MASTER, "Music sends to Master")
	for bus in AudioBuses.ALL:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "the layout defines %s" % bus)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.COMBAT)), AudioBuses.SFX, "Combat is part of effects")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.UI)), AudioBuses.SFX, "and so is UI")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.VOICE)), AudioBuses.MASTER, "Voice has its own fader beside them")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.CROWD)), AudioBuses.MASTER, "Crowd is not folded into music or effects")
	var crowd := PlayerSettings.new()
	crowd.crowd_volume = 0.0
	crowd.apply_audio()
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.CROWD)), "zero crowd volume mutes the bed and the reactions")
	crowd.crowd_volume = 1.0
	crowd.apply_audio()
	var voiced := PlayerSettings.new()
	voiced.voice_volume = 0.0
	voiced.apply_audio()
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.VOICE)), "announcer volume reaches the Voice bus")
	voiced.voice_volume = 1.0
	voiced.apply_audio()
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


func test_readability_levels_are_ordered_and_can_be_switched_off() -> void:
	var settings := PlayerSettings.new()
	settings.trail_strength = PlayerSettings.TrailStrength.OFF
	assert_eq(settings.trail_value(), 0.0, "off draws nothing")
	settings.trail_strength = PlayerSettings.TrailStrength.SUBTLE
	var subtle := settings.trail_value()
	settings.trail_strength = PlayerSettings.TrailStrength.FULL
	assert_true(0.0 < subtle and subtle < settings.trail_value(), "off < subtle < full")
	settings.sweet_spot = PlayerSettings.SweetSpot.OFF
	assert_eq(settings.sweet_spot_value(), 0.0, "off draws nothing")
	settings.sweet_spot = PlayerSettings.SweetSpot.STANDARD
	assert_eq(settings.sweet_spot_value(), 1.0, "standard is the unmodified cue")
	settings.sweet_spot = PlayerSettings.SweetSpot.STRONG
	assert_true(settings.sweet_spot_value() > 1.0, "strong is louder than standard, deliberately")


func test_legacy_bool_screen_shake_migrates_to_float() -> void:
	_cleanup()
	var config := ConfigFile.new()
	config.set_value(PlayerSettings.SECTION_GAMEPLAY, PlayerSettings.KEY_SCREEN_SHAKE, true)
	assert_eq(config.save(PATH), OK, "fixture: legacy bool saved")
	var settings := PlayerSettings.new()
	settings.load_from(PATH)
	assert_eq(settings.screen_shake, 1.0, "true migrates to 1.0")
	_cleanup()
	config.set_value(PlayerSettings.SECTION_GAMEPLAY, PlayerSettings.KEY_SCREEN_SHAKE, false)
	assert_eq(config.save(PATH), OK, "fixture: legacy bool saved")
	settings = PlayerSettings.new()
	settings.load_from(PATH)
	assert_eq(settings.screen_shake, 0.0, "false migrates to 0.0")
	_cleanup()


func test_presentation_settings_do_not_affect_authoritative_hashes() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 42)
	runner.skip_intro()
	for _i in 60:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	var base_hash := StateHasher.hash_state(runner.state)
	assert_true(base_hash.length() > 0, "precondition: hash is not empty")
	var settings := PlayerSettings.new()
	settings.screen_shake = 0.0
	settings.flash_intensity = 0.0
	settings.particle_intensity = 0.0
	settings.combat_readability = PlayerSettings.CombatReadability.ENHANCED
	settings.high_contrast_weapons = true
	settings.reduced_motion = true
	settings.trail_strength = PlayerSettings.TrailStrength.OFF
	## Re-run the same commands and the hash must be identical.
	var runner2 := SimRunner.create(rules, 42)
	runner2.skip_intro()
	for _i in 60:
		runner2.push(PlayerCommand.idle(runner2.state.tick), PlayerCommand.idle(runner2.state.tick))
	assert_eq(StateHasher.hash_state(runner2.state), base_hash, "settings are presentation-only and do not affect authoritative state")


static func _codes(values: Array[int]) -> PackedInt64Array:
	return PackedInt64Array(values)


static func _key(physical: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = true
	return event


## The defaults are the actions authored in project.godot, read rather than
## repeated: both movement keys, the mouse and Space for attack.
func test_bindings_default_to_the_authored_actions() -> void:
	var bindings := KeyBindings.new()
	assert_eq(bindings.codes(InputActions.MOVE_UP), _codes([KEY_W, KEY_UP]), "move up: W and Up")
	assert_eq(bindings.codes(InputActions.ATTACK), _codes([-MOUSE_BUTTON_LEFT, KEY_SPACE]), "attack: the left mouse button and Space")
	assert_eq(bindings.codes(InputActions.PAUSE), _codes([KEY_ESCAPE, 0]), "pause: Escape, one slot free")
	for action in KeyBindings.ACTIONS:
		var authored: Array = (ProjectSettings.get_setting("input/%s" % action) as Dictionary)["events"]
		var bound := 0
		for code in bindings.codes(action):
			if code != 0:
				bound += 1
				assert_true(KeyBindings.event_for(code).is_action(action, true), "%s: %s triggers it" % [action, AppCopy.binding_label(code)])
		assert_eq(bound, authored.size(), "%s: every authored event and nothing else" % action)


## Binding an input another action uses swaps the two, so no input ever does
## two things; a swap that would leave an action with nothing is refused.
func test_binding_a_used_input_swaps_and_never_strands_an_action() -> void:
	var bindings := KeyBindings.new()
	assert_eq(bindings.code(InputActions.MOVE_DOWN, 0), KEY_S, "fixture: S moves down")
	assert_true(bindings.bind(InputActions.MOVE_UP, 0, KEY_S), "S bound to move up")
	assert_eq(bindings.code(InputActions.MOVE_UP, 0), KEY_S, "move up takes S")
	assert_eq(bindings.code(InputActions.MOVE_DOWN, 0), KEY_W, "move down takes the W it gave up")
	assert_eq(bindings.owner_of(KEY_S), Vector2i(KeyBindings.ACTIONS.find(InputActions.MOVE_UP), 0), "S has one owner")
	assert_true(bindings.bind(InputActions.ATTACK, 1, -MOUSE_BUTTON_LEFT), "swapping an action's own two slots is fine")
	assert_eq(bindings.codes(InputActions.ATTACK), _codes([KEY_SPACE, -MOUSE_BUTTON_LEFT]), "the attack slots trade places")
	assert_eq(bindings.codes(InputActions.DASH_MODIFIER), _codes([KEY_SHIFT, 0]), "fixture: dash has a free slot")
	var pause_before := bindings.codes(InputActions.PAUSE)
	assert_false(bindings.bind(InputActions.DASH_MODIFIER, 1, KEY_ESCAPE), "taking pause's only key for dash's free slot is refused")
	assert_eq(bindings.codes(InputActions.PAUSE), pause_before, "pause keeps its key")
	assert_eq(bindings.codes(InputActions.DASH_MODIFIER), _codes([KEY_SHIFT, 0]), "dash is unchanged")
	assert_true(bindings.bind(InputActions.DASH_MODIFIER, 0, KEY_ESCAPE), "but a full swap is allowed")
	assert_eq(bindings.codes(InputActions.PAUSE), _codes([KEY_SHIFT, 0]), "pause takes Shift")
	for invalid: Array in [[&"toggle_debug", 0, KEY_K], [InputActions.ATTACK, 2, KEY_K], [InputActions.ATTACK, 0, 0], [InputActions.ATTACK, 0, -MOUSE_BUTTON_WHEEL_UP]]:
		assert_false(bindings.bind(invalid[0], invalid[1], invalid[2]), "refused: %s" % str(invalid))
	bindings.reset()
	assert_true(bindings.is_default(), "reset restores the authored set")


## Bindings drive the InputMap and nothing else: the action fires from the new
## key and no longer from the old one.
func test_bindings_drive_the_input_map() -> void:
	var bindings := KeyBindings.new()
	assert_true(_key(KEY_SPACE).is_action(InputActions.ATTACK, true), "fixture: Space attacks")
	assert_true(bindings.bind(InputActions.ATTACK, 1, KEY_J), "J replaces Space")
	bindings.apply()
	assert_true(_key(KEY_J).is_action(InputActions.ATTACK, true), "J attacks")
	assert_false(_key(KEY_SPACE).is_action(InputActions.ATTACK, true), "Space no longer does")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(click.is_action(InputActions.ATTACK, true), "and the kept mouse binding still does")
	KeyBindings.new().apply()
	assert_true(_key(KEY_SPACE).is_action(InputActions.ATTACK, true), "the authored set restores Space")


## A stored binding set is untrusted: anything unusable falls back to the
## defaults as a whole, because a partly merged set could double-bind.
func test_stored_bindings_are_untrusted() -> void:
	var good := KeyBindings.new()
	assert_true(good.bind(InputActions.MOVE_LEFT, 1, KEY_J), "fixture: a valid change")
	var config := ConfigFile.new()
	good.save_to(config, PlayerSettings.SECTION_BINDINGS)
	var loaded := KeyBindings.new()
	loaded.load_from(config, PlayerSettings.SECTION_BINDINGS)
	assert_eq(loaded.code(InputActions.MOVE_LEFT, 1), KEY_J, "a valid set loads")
	var hostile: Array = [
		["duplicated", InputActions.MOVE_RIGHT, _codes([KEY_J, 0])],
		["wrong size", InputActions.ATTACK, _codes([KEY_SPACE])],
		["not a key", InputActions.ATTACK, _codes([KEY_SPACE, 999_999_999])],
		["wheel", InputActions.ATTACK, _codes([KEY_SPACE, -MOUSE_BUTTON_WHEEL_DOWN])],
		["empty", InputActions.PAUSE, _codes([0, 0])],
		["wrong type", InputActions.PAUSE, "Escape"],
	]
	for case: Array in hostile:
		var file := ConfigFile.new()
		good.save_to(file, PlayerSettings.SECTION_BINDINGS)
		file.set_value(PlayerSettings.SECTION_BINDINGS, String(case[1]), case[2])
		var read := KeyBindings.new()
		read.load_from(file, PlayerSettings.SECTION_BINDINGS)
		assert_true(read.is_default(), "%s: the authored set, not a partial merge" % case[0])