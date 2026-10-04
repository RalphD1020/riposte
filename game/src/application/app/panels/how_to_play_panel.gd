class_name HowToPlayPanel
extends RefCounted

## How-to-play content shared by the How to Play screen and the pause
## overlay: the two verbs on every device, then the physical rules that make
## them deep (UX §56–§57).
##
## See also: /docs/concepts/controls.md


static func controls(host: Container) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	host.add_child(grid)
	_row(grid, AppCopy.CONTROLS_MOVE, AppCopy.CONTROLS_MOVE_HOW)
	_row(grid, AppCopy.CONTROLS_ATTACK, AppCopy.CONTROLS_ATTACK_HOW)
	return grid


static func principles(host: Container) -> void:
	UiKit.body(host, AppCopy.CONTROLS_VERBS)
	UiKit.body(host, AppCopy.CONTROLS_PHYSICS)
	UiKit.body(host, AppCopy.CONTROLS_PAUSE)


static func _row(grid: GridContainer, verb: String, how: String) -> void:
	UiKit.section(grid, verb)
	var detail := UiKit.body(grid, how)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
