extends TestCase

## PRES-THEME: the centralized tokens meet WCAG 2.2 AA (UX §11, §36, §43–§44).
## The contrast formula lives here, independent of the theme it checks.
##
## Implements: /spec/invariants.md#ux-001
## See also: /docs/concepts/ux.md

const TEXT_MIN := 4.5
const NON_TEXT_MIN := 3.0


func _init() -> void:
	suite_name = "PRES-THEME"


## WCAG 2.2 contrast ratio between two opaque colors.
static func _contrast(a: Color, b: Color) -> float:
	var first := _luminance(a)
	var second := _luminance(b)
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)


static func _luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


static func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


func test_the_formula_knows_its_fixed_points() -> void:
	assert_near(_contrast(Color.WHITE, Color.BLACK), 21.0, 1e-6, "white on black is 21:1")
	assert_near(_contrast(Color("777777"), Color("777777")), 1.0, 1e-9, "a color on itself is 1:1")


func test_every_text_pair_meets_aa() -> void:
	var failing := PackedStringArray()
	for pair: Array in RiposteTheme.TEXT_PAIRS:
		var ratio := _contrast(pair[0], pair[1])
		if ratio < TEXT_MIN:
			failing.append("%s on %s = %.3f" % [(pair[0] as Color).to_html(false), (pair[1] as Color).to_html(false), ratio])
	assert_true(RiposteTheme.TEXT_PAIRS.size() >= 4, "fixture: every text pair is declared")
	assert_eq(failing.size(), 0, "text pairs below 4.5:1: %s" % ", ".join(failing))


func test_the_documented_near_miss_is_not_allowed() -> void:
	var ratio := _contrast(RiposteTheme.MAUVE_300, RiposteTheme.STEEL_900)
	assert_true(ratio < TEXT_MIN, "mauve on steel is 4.48:1 and must never carry text (%.3f)" % ratio)


func test_essential_boundaries_meet_non_text_contrast() -> void:
	for pair: Array in RiposteTheme.BOUNDARY_PAIRS:
		assert_true(_contrast(pair[0], pair[1]) >= NON_TEXT_MIN, "%s vs %s ≥ 3:1" % [(pair[0] as Color).to_html(false), (pair[1] as Color).to_html(false)])


func test_combatants_and_blades_read_against_the_floor() -> void:
	for color in RiposteTheme.WORLD_READS:
		var ratio := _contrast(color, RiposteTheme.WORLD_FLOOR)
		assert_true(ratio >= NON_TEXT_MIN, "%s on the floor ≥ 3:1 (%.2f)" % [color.to_html(false), ratio])


func test_buttons_get_a_full_touch_target() -> void:
	assert_true(RiposteTheme.TOUCH_TARGET >= 48.0, "48 px minimum target")
	var button := Button.new()
	button.text = "Quick Play"
	RiposteTheme.style_button(button, &"PrimaryButton")
	assert_true(button.custom_minimum_size.x >= 48.0 and button.custom_minimum_size.y >= 48.0, "styled button meets the target")
	assert_eq(button.focus_mode, Control.FOCUS_ALL, "keyboard focusable")
	assert_eq(button.accessibility_name, "Quick Play", "accessible name defaults to the label")
	button.free()


func test_theme_builds_visible_focus_for_every_control() -> void:
	var theme := RiposteTheme.build()
	for type: String in ["Button", "PrimaryButton", "HudButton", "HSlider", "CheckButton"]:
		assert_true(theme.has_stylebox("focus", type), "%s has a focus style" % type)
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_false(focus.draw_center, "focus ring does not cover the control")
	assert_eq(focus.border_width_left, RiposteTheme.FOCUS_WIDTH, "3 px ring")


func test_components_style_through_theme_variations() -> void:
	var theme := RiposteTheme.build()
	for variation: StringName in [&"SectionLabel", &"CaptionLabel", &"FieldLabel", &"HudTitleLabel", &"HudAccentLabel", &"HudCaptionLabel", &"PageColumns", &"PageStack", &"SheetMargin", &"HudRow", &"HudStack", &"PlayerHealthBar", &"OpponentHealthBar"]:
		assert_true(theme.is_type_variation(variation, theme.get_type_variation_base(variation)), "%s is a theme variation" % variation)
	assert_eq(theme.get_constant("separation", "VBoxContainer"), int(RiposteTheme.STACK_GAP), "columns breathe at the stack gap")
	assert_eq(theme.get_constant("separation", "HudStack"), int(RiposteTheme.HUD_STACK_GAP), "HUD plates stay compact")
	assert_eq(theme.get_color("font_color", "HudAccentLabel"), RiposteTheme.ACCENT_ON_DARK, "accent text uses the tested accent color")
	assert_true(theme.get_stylebox("fill", "OpponentHealthBar") != theme.get_stylebox("fill", "PlayerHealthBar"), "each side has its own fill")
	assert_true(theme.has_icon("grabber", "HSlider") and theme.has_icon("checked", "CheckButton"), "slider knob and switches are drawn, high-contrast icons")
