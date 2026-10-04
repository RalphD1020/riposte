class_name ScreenRouter
extends Control

## Holds exactly one screen. A swap removes the old screen from the tree
## first, so its _exit_tree teardown (a match disposing its presenter) runs
## before the next screen builds, then frees it.
##
## See also: /docs/concepts/ux.md

signal screen_changed(screen: AppScreen.Id)

var current_id: AppScreen.Id = AppScreen.Id.MAIN_MENU
var _app: RiposteApp
var _current: Control


func _init() -> void:
	name = "ScreenRouter"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func bind(app: RiposteApp) -> void:
	_app = app


func current() -> Control:
	return _current


func show_screen(screen: AppScreen.Id) -> Control:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = _create(screen)
	current_id = screen
	add_child(_current)
	screen_changed.emit(screen)
	return _current


func _create(screen: AppScreen.Id) -> Control:
	match screen:
		AppScreen.Id.HOW_TO_PLAY:
			return HowToPlayScreen.new().bind(_app)
		AppScreen.Id.SETTINGS:
			return SettingsScreen.new().bind(_app)
		AppScreen.Id.MATCH:
			return MatchScreen.new().bind(_app)
		AppScreen.Id.RESULTS:
			return ResultsScreen.new().bind(_app)
	return MainMenuScreen.new().bind(_app)
