class_name HumanInputState
extends RefCounted

## Device-agnostic human input between ticks. Keyboard, mouse, and touch
## merge into one logical attack button (held while any source holds it) and
## one move vector (touch overrides keys while a thumb is down). Edges
## accumulate until the next tick consumes them, so a tap shorter than a frame
## still reaches the simulation.
##
## See also: /docs/concepts/controls.md

const SOURCE_POINTER := &"pointer"
const SOURCE_KEY := &"key"
const SOURCE_TOUCH := &"touch"

var _key_x: float = 0.0
var _key_y: float = 0.0
var _touch_x: float = 0.0
var _touch_y: float = 0.0
var _touch_active: bool = false
var _held_sources: Dictionary = {}
var _pressed: bool = false
var _released: bool = false
var _canceled: bool = false


func set_key_axis(x: float, y: float) -> void:
	_key_x = x
	_key_y = y


func set_touch_axis(x: float, y: float, active: bool) -> void:
	_touch_x = x if active else 0.0
	_touch_y = y if active else 0.0
	_touch_active = active


func attack_down(source: StringName) -> void:
	if _held_sources.has(source):
		return
	if _held_sources.is_empty():
		_pressed = true
	_held_sources[source] = true


func attack_up(source: StringName) -> void:
	if not _held_sources.has(source):
		return
	_held_sources.erase(source)
	if _held_sources.is_empty():
		_released = true


func is_attack_held() -> bool:
	return not _held_sources.is_empty()


## Focus loss, touch cancel, or pause: drop everything without attacking.
func cancel_all() -> void:
	if not _held_sources.is_empty():
		_canceled = true
	_held_sources.clear()
	_pressed = false
	_released = false
	_key_x = 0.0
	_key_y = 0.0
	set_touch_axis(0.0, 0.0, false)


func consume(tick: int) -> PlayerCommand:
	var x := _touch_x if _touch_active else _key_x
	var y := _touch_y if _touch_active else _key_y
	var command := PlayerCommand.create(tick, x, y, _pressed, _released, _canceled)
	_pressed = false
	_released = false
	_canceled = false
	return command
