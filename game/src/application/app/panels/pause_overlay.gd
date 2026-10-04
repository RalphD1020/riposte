class_name PauseOverlay
extends Control

## Modal pause sheet (UX §26): Resume, Settings, How to Play, Quit to Menu.
## The dimmed backdrop swallows pointer input so nothing reaches the duel.
## The host owns Escape and calls `back()`, so one handler decides it.
##
## See also: /docs/concepts/ux.md

signal resume_requested
signal quit_requested

enum Page { MENU, SETTINGS, HOW_TO_PLAY }

var _app: RiposteApp
var _column: VBoxContainer
var _page: Page = Page.MENU
var _primary: Control
var _settings: SettingsPanel


static func create(app: RiposteApp) -> PauseOverlay:
	var overlay := PauseOverlay.new()
	overlay._app = app
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay._column = UiKit.sheet(overlay)
	overlay.visible = false
	return overlay


func open() -> void:
	visible = true
	show_page(Page.MENU)


func close() -> void:
	visible = false
	_settings = null
	UiKit.clear(_column)


func is_open() -> bool:
	return visible


func page() -> Page:
	return _page


func primary() -> Control:
	return _primary


## Escape: settings section → section list → pause menu → resume.
func back() -> void:
	if _page == Page.SETTINGS and _settings != null and _settings.back():
		return
	if _page != Page.MENU:
		show_page(Page.MENU)
		return
	resume_requested.emit()


func show_page(target: Page) -> void:
	_page = target
	_settings = null
	UiKit.clear(_column)
	match target:
		Page.MENU:
			var title := UiKit.heading(_column, AppCopy.PAUSED)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.accessibility_live = AccessibilityServer.LIVE_POLITE
			_primary = UiKit.button(_column, AppCopy.RESUME, resume_requested.emit, &"PrimaryButton")
			var line := UiKit.row(_column)
			UiKit.button(line, AppCopy.SETTINGS, _later(show_page.bind(Page.SETTINGS)))
			UiKit.button(line, AppCopy.HOW_TO_PLAY, _later(show_page.bind(Page.HOW_TO_PLAY)))
			UiKit.button(_column, AppCopy.QUIT_TO_MENU, quit_requested.emit)
		Page.SETTINGS:
			UiKit.heading(_column, AppCopy.SETTINGS)
			_settings = SettingsPanel.create(_app)
			_settings.closed.connect(_later(show_page.bind(Page.MENU)))
			_column.add_child(_settings)
			_primary = _settings.first_control()
		Page.HOW_TO_PLAY:
			UiKit.heading(_column, AppCopy.HOW_TO_PLAY)
			HowToPlayPanel.controls(_column)
			HowToPlayPanel.principles(_column)
			_primary = UiKit.button(_column, AppCopy.BACK, _later(show_page.bind(Page.MENU)))
	_focus_primary.call_deferred()


func _later(action: Callable) -> Callable:
	return func() -> void: action.call_deferred()


func _focus_primary() -> void:
	if visible and _primary != null and is_instance_valid(_primary) and _primary.is_inside_tree():
		_primary.grab_focus()
