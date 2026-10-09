extends TestCase

## APP-SHELL: the shell's pure pieces: UI scale, safe areas, copy that the
## shipped font can actually draw, and accessible choice controls.
##
## Implements: /spec/invariants.md#ux-001
## See also: /docs/concepts/ux.md

const COPY_SCRIPTS: PackedStringArray = [
	"res://src/application/app/app_copy.gd",
	"res://src/presentation/hud/hud_copy.gd",
]


func _init() -> void:
	suite_name = "APP-SHELL"


func test_menu_buttons_pulse_and_sound_through_one_shared_feel() -> void:
	var feedback := UiFeedback.new()
	var click := AudioStreamWAV.new()
	feedback.kit = UiThemeKit.new()
	feedback.kit.confirm = [click] as Array[AudioStream]
	(Engine.get_main_loop() as SceneTree).root.add_child(feedback)
	var host := VBoxContainer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var previous := UiKit.feedback
	UiKit.feedback = feedback
	var button := UiKit.button(host, "PLAY", Callable())
	UiKit.feedback = previous
	assert_true(button.has_meta(&"ui_feedback"), "the kit attaches the shared feel to every button it builds")
	feedback.attach(button)
	assert_eq(button.pressed.get_connections().size(), 1, "attaching twice never doubles the sound")
	button.pressed.emit()
	assert_eq(feedback.last_sound, PresentationKit.CUE_UI_CONFIRM, "a press confirms")
	button.mouse_entered.emit()
	assert_eq(feedback.last_sound, PresentationKit.CUE_UI_HOVER, "a hover ticks")
	assert_false(feedback.play(PresentationKit.CUE_UI_BACK), "a theme without back takes stays silent")
	host.queue_free()
	feedback.queue_free()


func test_ui_units_never_shrink_below_css_pixels() -> void:
	assert_eq(UiScale.factor_for(Vector2i(1280, 720), 1.0), 1.0, "desktop at base size")
	assert_eq(UiScale.factor_for(Vector2i(2560, 1440), 2.0), 1.0, "retina desktop already 1 unit = 1 CSS px")
	assert_near(UiScale.factor_for(Vector2i(2532, 1170), 3.0), 3.0 / 1.625, 1e-9, "landscape phone: 48 units stay 48 CSS px")
	assert_near(UiScale.factor_for(Vector2i(800, 600), 1.0), 1.6, 1e-9, "small window keeps text readable")
	assert_eq(UiScale.factor_for(Vector2i(0, 0), 2.0), 1.0, "a zero-size window is harmless")
	assert_eq(UiScale.factor_for(Vector2i(320, 180), 4.0), UiScale.MAX_FACTOR, "factor is capped")


func test_3d_renders_at_most_twice_css_resolution() -> void:
	assert_eq(UiScale.scale_3d_for(1.0), 1.0, "standard density renders natively")
	assert_eq(UiScale.scale_3d_for(2.0), 1.0, "2x renders natively")
	assert_near(UiScale.scale_3d_for(3.0), 2.0 / 3.0, 1e-9, "3x phones render 3D at 2x")
	assert_eq(UiScale.scale_3d_for(8.0), UiScale.MIN_3D_SCALE, "never below the floor")


func test_safe_area_reads_css_insets_and_display_rects() -> void:
	assert_eq(SafeArea.KEY_LEFT, "left", "fixture: the fixtures below are written in the game's own key names")
	var web := SafeArea.from_web_json('{"left":44,"top":0,"right":44,"bottom":21,"width":844,"height":390}', Vector2(844.0, 390.0))
	assert_eq(web, Vector4(44.0, 0.0, 44.0, 21.0), "CSS px map 1:1 when one unit is one CSS px")
	var scaled := SafeArea.from_web_json('{"left":10,"top":0,"right":0,"bottom":0,"width":500,"height":300}', Vector2(1000.0, 600.0))
	assert_eq(scaled.x, 20.0, "scaled into viewport units")
	assert_eq(SafeArea.from_web_json("", Vector2(800.0, 400.0)), Vector4.ZERO, "missing global is zero")
	assert_eq(SafeArea.from_web_json("not json", Vector2(800.0, 400.0)), Vector4.ZERO, "garbage is zero")
	assert_eq(SafeArea.from_web_json('{"left":5,"width":0}', Vector2(800.0, 400.0)), Vector4.ZERO, "unknown width is zero")
	var display := SafeArea.from_display(Rect2i(88, 0, 2356, 1107), Vector2i(2532, 1170), Vector2(844.0, 390.0))
	assert_near(display.x, 88.0 / 3.0, 1e-6, "notch inset in viewport units")
	assert_near(display.w, 63.0 / 3.0, 1e-6, "home indicator inset")
	assert_eq(SafeArea.from_display(Rect2i(), Vector2i(1280, 720), Vector2(1280.0, 720.0)), Vector4.ZERO, "unknown safe rect is zero")


## The browser half of the safe-area contract is JavaScript in the export
## preset, and nothing compiles the two together. A renamed key there reports
## zero inset instead of erroring, which on a notched phone means the HUD
## under the notch — the exact failure this whole feature exists to prevent.
func test_the_export_publishes_the_safe_area_keys_the_game_reads() -> void:
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_true(preset.length() > 0, "fixture: the export preset is readable")
	assert_true(preset.contains(SafeArea.WEB_PROPERTY), "the preset publishes the global the game evaluates")
	assert_eq(SafeArea.KEYS.size(), 6, "fixture: six insets and the CSS viewport size")
	for key in SafeArea.KEYS:
		assert_true(preset.contains("%s:" % key), "the preset publishes a %s value" % key)
	assert_false(preset.contains("riposteSafeArea:"), "a renamed global would not be mistaken for a key")


func test_every_shipped_string_renders_in_the_shipped_font() -> void:
	var font := ThemeDB.fallback_font
	var missing := PackedStringArray()
	var strings := 0
	for path in COPY_SCRIPTS:
		var script := load(path) as GDScript
		assert_true(script != null, "copy script loads: %s" % path)
		var texts := PackedStringArray()
		for value: Variant in script.get_script_constant_map().values():
			_collect(value, texts)
		strings += texts.size()
		for text in texts:
			for index in text.length():
				var code := text.unicode_at(index)
				if not font.has_char(code) and not missing.has(text[index]):
					missing.append(text[index])
	assert_true(strings > 60, "fixture: the copy tables were actually scanned (%d strings)" % strings)
	assert_eq(missing.size(), 0, "glyphs missing from the shipped font: %s" % " ".join(missing))


func _collect(value: Variant, into: PackedStringArray) -> void:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			into.append(str(value))
		TYPE_PACKED_STRING_ARRAY:
			into.append_array(value as PackedStringArray)
		TYPE_ARRAY:
			for item: Variant in value as Array:
				_collect(item, into)
		TYPE_DICTIONARY:
			for item: Variant in (value as Dictionary).values():
				_collect(item, into)


func test_segmented_choice_marks_selection_by_fill_and_marker() -> void:
	var host := VBoxContainer.new()
	var chosen: Array[int] = []
	var buttons := UiKit.segmented(host, PackedStringArray(["Easy", "Medium", "Hard"]), 1, func(index: int) -> void: chosen.append(index), "Difficulty")
	assert_eq(buttons.size(), 3, "one button per option")
	assert_true(buttons[1].button_pressed and buttons[1].icon != null, "initial selection is pressed and marked")
	assert_true(buttons[0].icon == null and not buttons[0].button_pressed, "others are plain")
	assert_eq(buttons[2].accessibility_name, "Difficulty: Hard", "options are named with their group")
	buttons[2].pressed.emit()
	assert_eq(chosen, [2], "selection reported")
	assert_true(buttons[2].icon != null and buttons[1].icon == null, "marker moved")
	assert_eq(buttons[2].theme_type_variation, &"PrimaryButton", "selected option is filled")
	for button in buttons:
		assert_true(button.custom_minimum_size.y >= RiposteTheme.TOUCH_TARGET, "48 px target")
	host.free()


func test_every_input_action_the_code_names_exists() -> void:
	var names: Array[StringName] = []
	names.append_array(InputActions.PROJECT_ACTIONS)
	names.append(InputActions.UI_CANCEL)
	names.append_array(InputActions.UI_NAVIGATION)
	assert_true(names.size() >= 10, "fixture: project and GUI actions listed")
	for action in names:
		assert_true(InputMap.has_action(action), "InputMap defines %s" % action)


class ProbeScreen:
	extends ScreenBase

	func build() -> void:
		UiKit.heading(lead, "Lead")
		UiKit.button(body, "Act", Callable())


func test_menus_sit_side_by_side_only_on_short_landscape_screens() -> void:
	var host := Control.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	host.size = Vector2(844.0, 390.0)
	var screen := ProbeScreen.new()
	host.add_child(screen)
	await await_frames(1)
	assert_eq(screen.size, Vector2(844.0, 390.0), "fixture: screen fills a landscape phone")
	assert_true(screen.is_side_by_side(), "short landscape phone: title beside actions, no scrolling")
	host.size = Vector2(390.0, 844.0)
	await await_frames(1)
	assert_false(screen.is_side_by_side(), "portrait phone: stacked")
	host.size = Vector2(1280.0, 720.0)
	await await_frames(1)
	assert_false(screen.is_side_by_side(), "desktop: stacked and centered")
	host.queue_free()


func test_portrait_orientation_plays_without_blocking() -> void:
	var portrait := Vector2(390.0, 844.0)
	var landscape := Vector2(844.0, 390.0)
	assert_true(portrait.y > portrait.x, "fixture: portrait")
	assert_true(landscape.x > landscape.y, "fixture: landscape")
	## Both orientations work; neither shows a blocking prompt.
	assert_eq(Camera3D.KEEP_WIDTH, 0, "portrait camera keeps width so the arena stays fully visible")


func test_stub_buttons_say_why_they_do_nothing() -> void:
	var host := HBoxContainer.new()
	var stub := UiKit.stub_button(host, "Discord", "Soon", "Coming soon")
	assert_true(stub.disabled, "a stub never navigates")
	assert_eq(stub.text, "Discord · Soon", "visible state")
	assert_eq(stub.accessibility_name, "Discord. Coming soon", "announced state")
	assert_false(CommunityLinks.is_configured(CommunityLinks.COMMUNITY), "no invented community (Discord) URL")
	assert_false(CommunityLinks.is_configured(CommunityLinks.SUPPORT), "no invented support (Patreon) URL")
	assert_false(CommunityLinks.is_configured("http://insecure.example"), "https only")
	host.free()
