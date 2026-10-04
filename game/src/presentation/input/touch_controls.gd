class_name TouchControls
extends Control

## Mobile duel controls (UX §31–§35): a floating joystick that appears where
## the left thumb lands and an attack zone on the right. Fingers are tracked
## by index so moving and attacking never steal from each other, and a
## canceled touch (OS gesture, incoming call) cancels instead of attacking.
## Emits intents only; the application maps them onto HumanInputState.
##
## Move vectors are in arena axes: x right, y up (screen up is arena +y
## because the duel camera never rotates).
##
## See also: /docs/concepts/controls.md

signal move_changed(vector: Vector2, active: bool)
signal attack_pressed
signal attack_released
signal canceled

const JOYSTICK_RADIUS := 64.0
const KNOB_RADIUS := 26.0
const DEAD_ZONE := 0.12
const ZONE_TOP := 0.25
const MOVE_ZONE_RIGHT := 0.45
const ATTACK_ZONE_LEFT := 0.55
## Drawing: resting hints are fainter than active controls; hints sit
## HINT_INSET from the zone's outer corner; the attack ring is a large knob.
const HINT_ALPHA := 0.45
const FILL_ALPHA := 0.35
const RING_WIDTH := 3.0
const RING_SEGMENTS := 48
const HINT_INSET := JOYSTICK_RADIUS * 1.6
const ATTACK_RING_RADIUS := KNOB_RADIUS * 1.6

var opacity: float = 0.5
## Controls (e.g. the pause button) whose touches belong to the GUI.
var exclusions: Array[Control] = []
var _enabled: bool = true
var _revealed: bool = false
var _insets: Vector4 = Vector4.ZERO
var _move_index: int = -1
var _move_origin: Vector2 = Vector2.ZERO
var _move_vector: Vector2 = Vector2.ZERO
var _attack_index: int = -1
var _attack_point: Vector2 = Vector2.ZERO


func _init() -> void:
	name = "TouchControls"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


## Shown up front on touch devices, and on the first touch anywhere else
## (some browsers under-report touch support).
func reveal() -> void:
	_revealed = true
	visible = _enabled


## Disabled while a modal (pause, rotate prompt) owns the screen.
func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on and _revealed
	if not on:
		reset()


func _input(event: InputEvent) -> void:
	if not _enabled or not is_inside_tree():
		return
	if not _revealed and event is InputEventScreenTouch:
		reveal()
	if handle(event):
		get_viewport().set_input_as_handled()


## Returns true when the event belonged to a duel control.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _touch(event as InputEventScreenTouch)
	if event is InputEventScreenDrag:
		return _drag(event as InputEventScreenDrag)
	return false


func set_insets(insets: Vector4) -> void:
	_insets = insets
	queue_redraw()


## Pause, focus loss, or teardown: forget every finger without attacking.
func reset() -> void:
	var was_moving := _move_index != -1
	_move_index = -1
	_attack_index = -1
	if was_moving:
		_set_move(Vector2.ZERO, false)
	queue_redraw()


func is_moving() -> bool:
	return _move_index != -1


func move_zone() -> Rect2:
	var area := _area()
	var top := area.position.y + area.size.y * ZONE_TOP
	return Rect2(area.position.x, top, area.size.x * MOVE_ZONE_RIGHT, area.end.y - top)


func attack_zone() -> Rect2:
	var area := _area()
	var top := area.position.y + area.size.y * ZONE_TOP
	var left := area.position.x + area.size.x * ATTACK_ZONE_LEFT
	return Rect2(left, top, area.end.x - left, area.end.y - top)


func _touch(touch: InputEventScreenTouch) -> bool:
	if touch.pressed:
		if _excluded(touch.position):
			return false
		if _move_index == -1 and move_zone().has_point(touch.position):
			_move_index = touch.index
			_move_origin = touch.position
			_set_move(Vector2.ZERO, true)
			return true
		if _attack_index == -1 and attack_zone().has_point(touch.position):
			_attack_index = touch.index
			_attack_point = touch.position
			attack_pressed.emit()
			queue_redraw()
			return true
		return false
	if touch.index == _move_index:
		_move_index = -1
		_set_move(Vector2.ZERO, false)
		return true
	if touch.index == _attack_index:
		_attack_index = -1
		queue_redraw()
		if touch.canceled:
			canceled.emit()
		else:
			attack_released.emit()
		return true
	return false


func _drag(drag: InputEventScreenDrag) -> bool:
	if drag.index != _move_index:
		return drag.index == _attack_index
	var offset := drag.position - _move_origin
	var reach := offset.length()
	if reach > JOYSTICK_RADIUS:
		## Floating stick: the base trails the thumb instead of capping it.
		_move_origin += offset / reach * (reach - JOYSTICK_RADIUS)
		offset = drag.position - _move_origin
	var stick := offset / JOYSTICK_RADIUS
	if stick.length() < DEAD_ZONE:
		stick = Vector2.ZERO
	_set_move(Vector2(stick.x, -stick.y), true)
	return true


func _set_move(vector: Vector2, active: bool) -> void:
	_move_vector = vector
	move_changed.emit(vector, active)
	queue_redraw()


func _excluded(point: Vector2) -> bool:
	for control in exclusions:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return false


func _area() -> Rect2:
	var rect := get_global_rect()
	var position_inset := Vector2(_insets.x, _insets.y)
	return Rect2(rect.position + position_inset, rect.size - position_inset - Vector2(_insets.z, _insets.w))


func _draw() -> void:
	var fill := Color(RiposteTheme.SURFACE, opacity * FILL_ALPHA)
	var rim := Color(RiposteTheme.STEEL_900, opacity)
	var hint_rim := Color(RiposteTheme.STEEL_900, opacity * HINT_ALPHA)
	var knob := Color(RiposteTheme.SURFACE, opacity)
	var origin_offset := get_global_rect().position
	if _move_index != -1:
		var base := _move_origin - origin_offset
		draw_circle(base, JOYSTICK_RADIUS, fill)
		draw_arc(base, JOYSTICK_RADIUS, 0.0, TAU, RING_SEGMENTS, rim, RING_WIDTH, true)
		draw_circle(base + Vector2(_move_vector.x, -_move_vector.y) * JOYSTICK_RADIUS, KNOB_RADIUS, knob)
	else:
		var hint := move_zone()
		var anchor := Vector2(hint.position.x + HINT_INSET, hint.end.y - HINT_INSET) - origin_offset
		draw_arc(anchor, JOYSTICK_RADIUS, 0.0, TAU, RING_SEGMENTS, hint_rim, RING_WIDTH, true)
	var attack := attack_zone()
	if _attack_index != -1:
		var held := _attack_point - origin_offset
		draw_circle(held, ATTACK_RING_RADIUS, fill)
		draw_arc(held, ATTACK_RING_RADIUS, 0.0, TAU, RING_SEGMENTS, rim, RING_WIDTH, true)
	else:
		var resting := Vector2(attack.end.x - HINT_INSET, attack.end.y - HINT_INSET) - origin_offset
		draw_arc(resting, ATTACK_RING_RADIUS, 0.0, TAU, RING_SEGMENTS, hint_rim, RING_WIDTH, true)
