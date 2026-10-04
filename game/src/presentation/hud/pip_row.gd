class_name PipRow
extends Control

## Round pips drawn as shapes: filled for rounds won, outlined for rounds
## still needed. Shape (not just color) carries the state (UX §50).
##
## See also: /docs/concepts/ux.md

const RADIUS := 5.0
const SPACING := 16.0
const OUTLINE := 2.0

var wins: int = 0
var needed: int = 3
var mirrored: bool = false
var color: Color = RiposteTheme.ACCENT_ON_DARK


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_resize()


func show_wins(won: int, to_win: int) -> void:
	wins = clampi(won, 0, maxi(to_win, 0))
	needed = maxi(to_win, 0)
	_resize()
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = Vector2(SPACING * float(needed), RADIUS * 2.0 + OUTLINE * 2.0)


func _draw() -> void:
	var y := size.y * 0.5
	for index in needed:
		var slot := needed - 1 - index if mirrored else index
		var center := Vector2(SPACING * (float(slot) + 0.5), y)
		if index < wins:
			draw_circle(center, RADIUS, color)
		else:
			draw_arc(center, RADIUS, 0.0, TAU, 20, color, OUTLINE, true)
