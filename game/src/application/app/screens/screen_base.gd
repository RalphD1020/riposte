class_name ScreenBase
extends Control

## Mobile-first frame for every menu screen: a light surface, safe-area
## margins, and two columns: `lead` (title, context) and `body` (actions).
## They stack on tall screens and sit side by side on short landscape phones,
## so no menu needs touch scrolling at 360 px tall; the ScrollContainer is a
## wheel/keyboard fallback. Escape (`ui_cancel`) calls `back()`. Keyboard
## devices focus the primary action on open; touch devices get focus on the
## first navigation key, so no ring appears under a thumb (UX §41–§42).
##
## See also: /docs/concepts/ux.md

const SIDE_BY_SIDE_MAX_HEIGHT := 560.0
const SIDE_BY_SIDE_MIN_WIDTH := 600.0

var app: RiposteApp
var lead: VBoxContainer
var body: VBoxContainer
var _layout: BoxContainer
var _margin: MarginContainer
var _page: VBoxContainer
var _primary: Control


func bind(riposte_app: RiposteApp) -> ScreenBase:
	app = riposte_app
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build_frame()
	build()
	resized.connect(relayout)
	relayout()
	if not DisplayServer.is_touchscreen_available():
		focus_primary.call_deferred()


## Subclasses fill `lead` and `body`.
func build() -> void:
	pass


## Escape / back. Default: return to the main menu.
func back() -> void:
	app.go_to(AppScreen.Id.MAIN_MENU)


func set_primary(control: Control) -> void:
	_primary = control


func primary() -> Control:
	return _primary


func focus_primary() -> void:
	if _primary != null and is_instance_valid(_primary) and _primary.is_inside_tree() and _primary.is_visible_in_tree():
		_primary.grab_focus()


func is_side_by_side() -> bool:
	return not _layout.vertical


func relayout() -> void:
	var insets := app.safe_insets() if app != null else Vector4.ZERO
	var edge := RiposteTheme.MARGIN
	RiposteTheme.apply_insets(_margin, edge, insets)
	var available := size - Vector2(2.0 * edge + insets.x + insets.z, 2.0 * edge + insets.y + insets.w)
	var both := lead.get_child_count() > 0 and body.get_child_count() > 0
	var side_by_side := both and available.y < SIDE_BY_SIDE_MAX_HEIGHT and available.x >= SIDE_BY_SIDE_MIN_WIDTH
	_layout.vertical = not side_by_side
	var width := (available.x - RiposteTheme.COLUMN_GAP) * 0.5 if side_by_side else available.x
	width = clampf(floorf(width), 0.0, RiposteTheme.COLUMN_MAX_WIDTH)
	lead.custom_minimum_size.x = width
	body.custom_minimum_size.x = width
	## Whole pixels: a fractional UI scale plus pixel-snapped controls can
	## leave the scroll area a fraction shorter than the page, which would
	## show a scrollbar for content that fits.
	_page.custom_minimum_size.y = maxf(floorf(available.y), 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.UI_CANCEL):
		get_viewport().set_input_as_handled()
		back()
		return
	if get_viewport().gui_get_focus_owner() == null:
		for action in InputActions.UI_NAVIGATION:
			if event.is_action_pressed(action):
				get_viewport().set_input_as_handled()
				focus_primary()
				return


func _build_frame() -> void:
	var surface := ColorRect.new()
	surface.color = RiposteTheme.SURFACE
	surface.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	surface.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(surface)
	var band := ColorRect.new()
	band.color = RiposteTheme.MAUVE_300
	band.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	band.offset_top = -RiposteTheme.BAND_HEIGHT
	band.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(band)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_margin.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_margin.add_child(scroll)
	_page = VBoxContainer.new()
	_page.theme_type_variation = &"PageStack"
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	scroll.add_child(_page)
	_page.add_child(_spring())
	_layout = BoxContainer.new()
	_layout.theme_type_variation = &"PageColumns"
	_layout.vertical = true
	_layout.size_flags_horizontal = SIZE_SHRINK_CENTER
	_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	_layout.mouse_filter = MOUSE_FILTER_IGNORE
	_page.add_child(_layout)
	lead = _column()
	body = _column()
	_page.add_child(_spring())


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = MOUSE_FILTER_IGNORE
	_layout.add_child(column)
	return column


func _spring() -> Control:
	var spring := Control.new()
	spring.size_flags_vertical = SIZE_EXPAND_FILL
	spring.mouse_filter = MOUSE_FILTER_IGNORE
	return spring
