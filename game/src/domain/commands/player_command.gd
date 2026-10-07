class_name PlayerCommand
extends RefCounted

## The only input contract between a controller and the simulation
## (COMBAT §69). Human, CPU, replay, and future network sources all emit this.
##
## Movement is quantized to integer milli-units so commands serialize exactly.
## Attack fields are edges within the tick window; the simulation tracks the
## held state itself. `attack_cancel` is the deterministic input-interruption
## path (focus loss, touch cancel): it drops a charge without attacking.
## Commands are untrusted; the simulation consumes `sanitized()` values.
##
## Implements: /spec/invariants.md#cmd-001
## See also: /docs/concepts/simulation.md

const AXIS_MAX := 1000
const FLAG_PRESSED := 1
const FLAG_RELEASED := 2
const FLAG_CANCEL := 4
const FLAG_DASH := 8
const PACKED_STRIDE := 4

var tick: int = 0
var move_x: int = 0
var move_y: int = 0
var attack_pressed: bool = false
var attack_released: bool = false
var attack_cancel: bool = false
## Accessibility: Shift+direction produces the same burst as double-tap.
## The simulation consumes this identically to the gesture recognizer output.
var dash_modifier: bool = false


## Builds a command from an analog move vector; magnitude is clamped to 1.
static func create(
	tick_value: int,
	x: float,
	y: float,
	pressed: bool = false,
	released: bool = false,
	cancel: bool = false,
	dash: bool = false
) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.tick = tick_value
	var nx := x if is_finite(x) else 0.0
	var ny := y if is_finite(y) else 0.0
	var magnitude := SimMath.length(nx, ny)
	if magnitude > 1.0:
		nx /= magnitude
		ny /= magnitude
	command.move_x = clampi(roundi(nx * AXIS_MAX), -AXIS_MAX, AXIS_MAX)
	command.move_y = clampi(roundi(ny * AXIS_MAX), -AXIS_MAX, AXIS_MAX)
	command.attack_pressed = pressed
	command.attack_released = released
	command.attack_cancel = cancel
	command.dash_modifier = dash
	return command


static func idle(tick_value: int) -> PlayerCommand:
	return create(tick_value, 0.0, 0.0)


## Copy with every field forced into its legal range.
func sanitized() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.tick = tick
	command.move_x = clampi(move_x, -AXIS_MAX, AXIS_MAX)
	command.move_y = clampi(move_y, -AXIS_MAX, AXIS_MAX)
	command.attack_pressed = attack_pressed
	command.attack_released = attack_released
	command.attack_cancel = attack_cancel
	command.dash_modifier = dash_modifier
	return command


func axis_x() -> float:
	return float(move_x) / float(AXIS_MAX)


func axis_y() -> float:
	return float(move_y) / float(AXIS_MAX)


func is_idle() -> bool:
	return move_x == 0 and move_y == 0 and not attack_pressed and not attack_released and not attack_cancel and not dash_modifier


func flags() -> int:
	var bits := 0
	if attack_pressed:
		bits |= FLAG_PRESSED
	if attack_released:
		bits |= FLAG_RELEASED
	if attack_cancel:
		bits |= FLAG_CANCEL
	if dash_modifier:
		bits |= FLAG_DASH
	return bits


func append_to(packed: PackedInt32Array) -> void:
	packed.append(tick)
	packed.append(move_x)
	packed.append(move_y)
	packed.append(flags())


static func read_from(packed: PackedInt32Array, index: int) -> PlayerCommand:
	var base := index * PACKED_STRIDE
	var command := PlayerCommand.new()
	if base < 0 or base + PACKED_STRIDE > packed.size():
		return command
	command.tick = packed[base]
	command.move_x = packed[base + 1]
	command.move_y = packed[base + 2]
	var bits := packed[base + 3]
	command.attack_pressed = (bits & FLAG_PRESSED) != 0
	command.attack_released = (bits & FLAG_RELEASED) != 0
	command.attack_cancel = (bits & FLAG_CANCEL) != 0
	command.dash_modifier = (bits & FLAG_DASH) != 0
	return command
