class_name RiposteTheme
extends RefCounted

## Centralized Godot style tokens: the game's equivalent of
## apps/web/src/app/globals.css. Light-only interface with Dark Steel Gray as
## the dominant framing color (UX §10–§12). Every text pair used by the UI is
## listed in TEXT_PAIRS and proven ≥ 4.5:1 by tests (UX §11, §43).
##
## Implements: /spec/invariants.md#ux-001
## See also: /docs/concepts/ux.md

## --- Palette (UX §10) -------------------------------------------------------
const STEEL_900 := Color("404548")
const SURFACE := Color("ffffff")
const MAUVE_300 := Color("b6aeb3")
## Decorative only: never text, never an essential boundary on its own.
const SAGE_500 := Color("797e71")
const SAGE_LIGHT := Color("aeb2a9")
const SAGE_DARK := Color("41433c")

## --- Semantic roles --------------------------------------------------------
const TEXT_ON_LIGHT := STEEL_900
const TEXT_ON_DARK := SURFACE
const ACCENT_ON_DARK := SAGE_LIGHT
const ACCENT_ON_MAUVE := SAGE_DARK
const FOCUS_ON_LIGHT := STEEL_900
const FOCUS_ON_DARK := SURFACE
const OVERLAY := Color(0.251, 0.271, 0.282, 0.78)

## Text/background pairs the UI is allowed to use; each must meet 4.5:1.
const TEXT_PAIRS: Array[Array] = [
	[TEXT_ON_LIGHT, SURFACE],
	[TEXT_ON_DARK, STEEL_900],
	[ACCENT_ON_DARK, STEEL_900],
	[ACCENT_ON_MAUVE, MAUVE_300],
]
## Essential non-text boundaries; each must meet 3:1 (UX §44).
const BOUNDARY_PAIRS: Array[Array] = [
	[FOCUS_ON_LIGHT, SURFACE],
	[FOCUS_ON_DARK, STEEL_900],
	[STEEL_900, SURFACE],
]

## --- Sizing (UX §36, §45–§46) ------------------------------------------------
const TOUCH_TARGET := 48.0
const CONTROL_GAP := 8.0
## Vertical rhythm between controls in a menu column or sheet.
const STACK_GAP := 12.0
const SECTION_GAP := 16.0
## Between side-by-side menu columns.
const COLUMN_GAP := 32.0
const MARGIN := 24.0
const RADIUS := 6
const BORDER_WIDTH := 2
const FOCUS_WIDTH := 3
const FOCUS_GAP := 3
## Padding inside a styled box. Not `SECTION_GAP`: a gap separates siblings,
## this is the space a control keeps around its own label.
const BOX_PAD_X := 16
const BOX_PAD_Y := 10
const COLUMN_MAX_WIDTH := 440.0
const SHEET_WIDTH := 360.0
## Label column beside a slider, so label and slider share one 48 px row.
const FIELD_LABEL_WIDTH := 140.0
## Decorative mauve band along the bottom of menu screens.
const BAND_HEIGHT := 6.0
## In-duel HUD: inset from the (safe-area) edge, gaps between plates and
## inside a plate.
const HUD_EDGE := 12.0
const HUD_GAP := 8.0
const HUD_STACK_GAP := 4.0
const FONT_BODY := 18
const FONT_LABEL := 16
const FONT_SMALL := 14
const FONT_H2 := 28
const FONT_H1 := 44
const FONT_DISPLAY := 56
const HEALTH_BAR_HEIGHT := 14.0
const STAMINA_BAR_HEIGHT := 8.0

## --- Duel world (UX §7, §13, §18, §80) -------------------------------------
const WORLD_BACKGROUND := Color("d7d9d6")
## Floor luminance sits where both a light and a dark combatant clear 3:1.
const WORLD_FLOOR := Color("7f857b")
const WORLD_FLOOR_EDGE := Color("6a7067")
const WORLD_RING := STEEL_900
## Home-end tints (SIDE-001). Deliberately close to the floor: cardinality is
## orientation, not decoration, and the floor must never compete with blade
## readability. Each end is also a different *shape*, so the two ends stay
## distinguishable without relying on colour.
const WORLD_HOME_LIGHT := Color("949a8d")
const WORLD_HOME_DARK := Color("646a60")
const WORLD_AMBIENT := Color("eceeea")
const WORLD_AMBIENT_ENERGY := 0.65
const WORLD_KEY := Color("fffaf0")
const WORLD_KEY_ENERGY := 1.1
const WORLD_KEY_ROTATION_DEGREES := Vector3(-58.0, -32.0, 0.0)
const SHADOW := Color(0.08, 0.09, 0.1, 0.38)

## Combatant styles (UX §13): hue + outline + HUD side + label, never color alone.
const PLAYER_BODY := Color("f2eee6")
const PLAYER_OUTLINE := STEEL_900
const PLAYER_BLADE := Color("f6ead0")
const OPPONENT_BODY := Color("2e2a30")
const OPPONENT_OUTLINE := MAUVE_300
const OPPONENT_BLADE := Color("e6ecf2")
const BLADE_OUTLINE := Color("15181a")
const BLADE_HIGH_CONTRAST_CORE := Color("ffffff")
## Combat-critical world reads; each must meet 3:1 against the floor (UX §44).
const WORLD_READS: Array[Color] = [PLAYER_BODY, OPPONENT_BODY, PLAYER_BLADE, OPPONENT_BLADE, BLADE_OUTLINE]

## Feedback (UX §19–§22). Reduced Flash scales intensity down.
const SPARK := Color("ffe7a8")
const BODY_IMPACT := Color("f4e2d8")
const CRITICAL := Color("ffffff")
const CHARGE_RING := Color("f6ead0")
const REDUCED_FLASH_SCALE := 0.45

## HUD health fills.
const HEALTH_PLAYER := PLAYER_BODY
const HEALTH_OPPONENT := MAUVE_300
const HEALTH_TRACK := Color("2a2e30")

static var _display_font: FontVariation


## Stylized display face for titles and banners, derived from the engine's
## fallback font (no font download; system-light like the website).
static func display_font() -> FontVariation:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = ThemeDB.fallback_font
		_display_font.variation_embolden = 0.8
		_display_font.spacing_glyph = 3
	return _display_font


## The game's stylesheet. Components pick a `theme_type_variation`; only
## runtime values (safe-area margins) are set as per-node overrides.
static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY
	theme.set_color("font_color", "Label", TEXT_ON_LIGHT)
	_style_buttons(theme)
	_style_panels(theme)
	_style_labels(theme)
	_style_layout(theme)
	_style_inputs(theme)
	return theme


static func _style_buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _box(SURFACE, STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("hover", "Button", _box(Color("eef0ee"), STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("pressed", "Button", _box(Color("e2e5e2"), STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("disabled", "Button", _box(SURFACE, SAGE_500, BORDER_WIDTH))
	theme.set_stylebox("focus", "Button", focus_box(FOCUS_ON_LIGHT))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", TEXT_ON_LIGHT)
	theme.set_color("font_disabled_color", "Button", TEXT_ON_LIGHT)
	theme.set_font_size("font_size", "Button", FONT_LABEL)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box(STEEL_900, STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("hover", "PrimaryButton", _box(Color("4c5256"), STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("pressed", "PrimaryButton", _box(Color("33383a"), STEEL_900, BORDER_WIDTH))
	theme.set_stylebox("focus", "PrimaryButton", focus_box(FOCUS_ON_LIGHT))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "PrimaryButton", TEXT_ON_DARK)
	theme.set_type_variation("HudButton", "Button")
	theme.set_stylebox("normal", "HudButton", _box(STEEL_900, SAGE_LIGHT, BORDER_WIDTH))
	theme.set_stylebox("hover", "HudButton", _box(Color("4c5256"), SAGE_LIGHT, BORDER_WIDTH))
	theme.set_stylebox("pressed", "HudButton", _box(Color("33383a"), SAGE_LIGHT, BORDER_WIDTH))
	theme.set_stylebox("focus", "HudButton", focus_box(FOCUS_ON_DARK))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "HudButton", TEXT_ON_DARK)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, STEEL_900, 0, 0))
	theme.set_type_variation("HudPlate", "PanelContainer")
	theme.set_stylebox("panel", "HudPlate", _box(STEEL_900, STEEL_900, 0))
	theme.set_type_variation("Sheet", "PanelContainer")
	theme.set_stylebox("panel", "Sheet", _box(SURFACE, STEEL_900, BORDER_WIDTH))


static func _style_labels(theme: Theme) -> void:
	_label_variation(theme, &"HeadingLabel", &"Label", FONT_H2, display_font())
	_label_variation(theme, &"TitleLabel", &"Label", FONT_DISPLAY, display_font())
	_label_variation(theme, &"SectionLabel", &"Label", FONT_LABEL, display_font())
	_label_variation(theme, &"FieldLabel", &"Label", FONT_LABEL)
	_label_variation(theme, &"CaptionLabel", &"Label", FONT_SMALL)
	_label_variation(theme, &"BannerLabel", &"Label", FONT_H1, display_font(), TEXT_ON_DARK)
	_label_variation(theme, &"HudLabel", &"Label", FONT_LABEL, null, TEXT_ON_DARK)
	_label_variation(theme, &"HudTitleLabel", &"HudLabel", FONT_LABEL, display_font())
	_label_variation(theme, &"HudAccentLabel", &"HudLabel", FONT_LABEL, null, ACCENT_ON_DARK)
	_label_variation(theme, &"HudCaptionLabel", &"HudLabel", FONT_SMALL)


static func _label_variation(theme: Theme, variation: StringName, base: StringName, size: int, font: Font = null, color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	theme.set_type_variation(variation, base)
	theme.set_font_size("font_size", variation, size)
	if font != null:
		theme.set_font("font", variation, font)
	if color.a > 0.0:
		theme.set_color("font_color", variation, color)


static func _style_layout(theme: Theme) -> void:
	theme.set_constant("separation", "VBoxContainer", int(STACK_GAP))
	theme.set_constant("separation", "HBoxContainer", int(CONTROL_GAP))
	theme.set_constant("h_separation", "GridContainer", int(SECTION_GAP))
	theme.set_constant("v_separation", "GridContainer", int(CONTROL_GAP))
	theme.set_type_variation("PageStack", "VBoxContainer")
	theme.set_constant("separation", "PageStack", 0)
	theme.set_type_variation("PageColumns", "BoxContainer")
	theme.set_constant("separation", "PageColumns", int(COLUMN_GAP))
	theme.set_type_variation("SheetMargin", "MarginContainer")
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		theme.set_constant(side, "SheetMargin", int(MARGIN))
	theme.set_type_variation("HudRow", "HBoxContainer")
	theme.set_constant("separation", "HudRow", int(HUD_GAP))
	theme.set_type_variation("HudStack", "VBoxContainer")
	theme.set_constant("separation", "HudStack", int(HUD_STACK_GAP))


static func _style_inputs(theme: Theme) -> void:
	var track := _box(Color("e2e5e2"), STEEL_900, 1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", _box(STEEL_900, STEEL_900, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(STEEL_900, STEEL_900, 0))
	theme.set_icon("grabber", "HSlider", HudIcons.knob())
	theme.set_icon("grabber_highlight", "HSlider", HudIcons.knob())
	theme.set_stylebox("focus", "HSlider", focus_box(FOCUS_ON_LIGHT))
	theme.set_stylebox("focus", "CheckButton", focus_box(FOCUS_ON_LIGHT))
	theme.set_icon("checked", "CheckButton", HudIcons.switch(true))
	theme.set_icon("unchecked", "CheckButton", HudIcons.switch(false))
	theme.set_color("font_color", "CheckButton", TEXT_ON_LIGHT)
	theme.set_color("font_hover_color", "CheckButton", TEXT_ON_LIGHT)
	theme.set_color("font_pressed_color", "CheckButton", TEXT_ON_LIGHT)
	theme.set_color("font_focus_color", "CheckButton", TEXT_ON_LIGHT)
	theme.set_color("font_hover_pressed_color", "CheckButton", TEXT_ON_LIGHT)
	theme.set_stylebox("background", "ProgressBar", _box(HEALTH_TRACK, HEALTH_TRACK, 0, 2))
	theme.set_stylebox("fill", "ProgressBar", _box(HEALTH_PLAYER, HEALTH_PLAYER, 0, 2))
	theme.set_type_variation("PlayerHealthBar", "ProgressBar")
	theme.set_stylebox("fill", "PlayerHealthBar", _box(HEALTH_PLAYER, HEALTH_PLAYER, 0, 2))
	theme.set_type_variation("OpponentHealthBar", "ProgressBar")
	theme.set_stylebox("fill", "OpponentHealthBar", _box(HEALTH_OPPONENT, HEALTH_OPPONENT, 0, 2))


## Visible focus (UX §42): a 3 px ring offset by a 3 px gap so it reads
## against any control fill.
static func focus_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(FOCUS_WIDTH)
	box.set_corner_radius_all(RADIUS + FOCUS_GAP)
	box.set_expand_margin_all(FOCUS_WIDTH + FOCUS_GAP)
	return box


## Runtime margins: `edge` plus safe-area insets (left, top, right, bottom).
## The one style applied per node, because it depends on the device.
static func apply_insets(container: MarginContainer, edge: float, insets: Vector4) -> void:
	container.add_theme_constant_override("margin_left", int(edge + insets.x))
	container.add_theme_constant_override("margin_top", int(edge + insets.y))
	container.add_theme_constant_override("margin_right", int(edge + insets.z))
	container.add_theme_constant_override("margin_bottom", int(edge + insets.w))


static func _box(fill: Color, border: Color, border_width: int, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = BOX_PAD_X
	box.content_margin_right = BOX_PAD_X
	box.content_margin_top = BOX_PAD_Y
	box.content_margin_bottom = BOX_PAD_Y
	return box


## Primary / secondary / HUD buttons with a guaranteed 48 px touch target.
static func style_button(button: Button, variation: StringName = &"") -> void:
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, TOUCH_TARGET), maxf(button.custom_minimum_size.y, TOUCH_TARGET))
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_force_pass_scroll_events = false
	button.accessibility_name = button.text if button.accessibility_name == "" else button.accessibility_name
