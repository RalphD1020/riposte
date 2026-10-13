class_name AppDriver
extends RefCounted

## Test-only driver for the shipped main scene: boots a fresh `main.tscn` with
## a scratch settings file and pinned seeds, finds screens and buttons, and
## feeds the human only through real input — `Input.action_press` for held
## movement and the dash modifier (what a keyboard does to the Input singleton)
## and `Viewport.push_input` key events for the attack and skips. Frames are
## driven through each screen's `advance_frame`, the same path `_process` uses.
##
## See also: /docs/reference/testing.md

const MAIN_SCENE := "res://src/main/main.tscn"
## One frame is exactly one simulation tick, so a scripted input lands on the
## tick it was meant for.
const FRAME := SimulationTimebase.TICK_SECONDS

var main: RiposteMain
var app: RiposteApp
var settings_path: String = "user://riposte_full_e2e_settings.cfg"


static func boot(seed_value: int = 7) -> AppDriver:
	var driver := AppDriver.new()
	driver._remove_scratch()
	driver.main = (load(MAIN_SCENE) as PackedScene).instantiate() as RiposteMain
	driver.main.settings_path = driver.settings_path
	driver.main.seed_override = seed_value
	(Engine.get_main_loop() as SceneTree).root.add_child(driver.main)
	driver.app = driver.main.app()
	return driver


func shutdown() -> void:
	release_all()
	main.queue_free()
	_remove_scratch()


func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The current match screen with its own `_process` off, so only the test
## drives its frames.
func match_screen() -> MatchScreen:
	var screen := app.current_screen() as MatchScreen
	if screen != null:
		screen.set_process(false)
	return screen


func results_screen() -> ResultsScreen:
	var screen := app.current_screen() as ResultsScreen
	if screen != null:
		screen.set_process(false)
	return screen


func button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := button(child, text)
		if found != null:
			return found
	return null


## Press a visible, enabled button the way a click does.
func press(root: Node, text: String) -> bool:
	var target := button(root, text)
	if target == null or target.disabled or not target.is_visible_in_tree():
		return false
	target.pressed.emit()
	return true


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	tree().root.push_input(event, true)


## A tap of the attack key: press and release before the next tick.
func tap_attack() -> void:
	key(KEY_SPACE, true)
	key(KEY_SPACE, false)


## Hold the frame-relative stick at (x, y) through the arena move actions, with
## analog strength, and the dash modifier on or off.
func hold_move(x: float, y: float, dash: bool = false) -> void:
	_axis(InputActions.MOVE_RIGHT, InputActions.MOVE_LEFT, x)
	_axis(InputActions.MOVE_UP, InputActions.MOVE_DOWN, y)
	if dash:
		Input.action_press(InputActions.DASH_MODIFIER)
	else:
		Input.action_release(InputActions.DASH_MODIFIER)


func release_all() -> void:
	for action: StringName in [InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_UP, InputActions.MOVE_DOWN, InputActions.DASH_MODIFIER]:
		Input.action_release(action)


## Run frames until `done` is true or `limit` frames pass; returns frames run.
func run_until(screen: MatchScreen, done: Callable, limit: int = 20000) -> int:
	var frames := 0
	while frames < limit and not done.call():
		screen.advance_frame(FRAME)
		frames += 1
	return frames


func _axis(positive: StringName, negative: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	elif value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _remove_scratch() -> void:
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
