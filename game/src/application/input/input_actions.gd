class_name InputActions
extends RefCounted

## InputMap action names. Project actions are defined in project.godot
## `[input]` (physical keys, so layouts stay put); `ui_*` are Godot's
## built-in GUI actions. APP-SHELL proves every name here exists.
##
## See also: /docs/concepts/controls.md

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const ATTACK := &"attack"
const PAUSE := &"pause"
const TOGGLE_DEBUG := &"toggle_debug"

const UI_CANCEL := &"ui_cancel"
## Keys that move GUI focus; the first one claims focus when none is set.
const UI_NAVIGATION: Array[StringName] = [&"ui_focus_next", &"ui_focus_prev", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]

const PROJECT_ACTIONS: Array[StringName] = [MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN, ATTACK, PAUSE, TOGGLE_DEBUG]


## Arena-axis move vector from held keys (x right, y up).
static func move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_DOWN, MOVE_UP)
