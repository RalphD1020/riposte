class_name PipRow
extends Control

## Round pips drawn as sword-point diamonds: filled for rounds won, outlined
## for rounds still needed. Shape (not just color) carries the state (UX §50).
##
## See also: /docs/concepts/ux.md

const RADIUS := 6.0
const SPACING := 18.0
const OUTLINE := 2.0
## Diamonds are taller than wide, like a blade's point seen head-on.
const ASPECT := 1.35

var wins: int = 0
var needed: int = 3
var mirrored: bool = false
var color: Color = RiposteTheme.GOLD_ACCENT
var outline_color: Color = RiposteTheme.ACCENT_ON_DARK


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_resize()


func show_wins(won: int, to_win: int) -> void:
	wins = clampi(won, 0, maxi(to_win, 0))
	needed = maxi(to_win, 0)
	_resize()
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = Vector2(SPACING * float(needed), RADIUS * ASPECT * 2.0 + OUTLINE * 2.0)


static func diamond(center: Vector2, radius: float) -> PackedVector2Array:
	var tall := radius * ASPECT
	return PackedVector2Array([
		center + Vector2(0.0, -tall), center + Vector2(radius, 0.0), center + Vector2(0.0, tall), center + Vector2(-radius, 0.0)
	])


func _draw() -> void:
	var y := size.y * 0.5
	for index in needed:
		var slot := needed - 1 - index if mirrored else index
		var points := diamond(Vector2(SPACING * (float(slot) + 0.5), y), RADIUS)
		if index < wins:
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), outline_color, 1.0, true)
		else:
			draw_polyline(points + PackedVector2Array([points[0]]), outline_color, OUTLINE, true)
