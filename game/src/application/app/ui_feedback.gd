class_name UiFeedback
extends Node

## Menu responsiveness: a fast scale pulse when a control is hovered or
## focused, and short UI sounds on hover and press, on the UI bus. Snaps in
## 60–100 ms and never floats. Reduced Motion keeps the sound and drops the
## pulse. Sounds come from the UiThemeKit; a kit without them is silent.
##
## See also: /docs/concepts/ux.md

const VOICES := 2

var kit: UiThemeKit = UiThemeKit.new()
var reduced_motion: bool = false
var last_sound: StringName = &""
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _counter: int = 0


func _init() -> void:
	name = "UiFeedback"
	for _i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = AudioBuses.UI
		add_child(player)
		_players.append(player)


## Give a control the shared feel. Idempotent per control.
func attach(control: BaseButton) -> void:
	if control.has_meta(&"ui_feedback"):
		return
	control.set_meta(&"ui_feedback", true)
	control.mouse_entered.connect(_hovered.bind(control))
	control.focus_entered.connect(_hovered.bind(control))
	control.pressed.connect(func() -> void: play(PresentationKit.CUE_UI_CONFIRM))


func play(cue: StringName) -> bool:
	var takes: Array[AudioStream] = kit.confirm
	if cue == PresentationKit.CUE_UI_BACK:
		takes = kit.back
	elif cue == PresentationKit.CUE_UI_HOVER:
		takes = kit.hover
	last_sound = cue
	if takes.is_empty() or not is_inside_tree():
		return false
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = takes[_counter % takes.size()]
	_counter += 1
	player.play()
	return true


func _hovered(control: Control) -> void:
	if control is BaseButton and (control as BaseButton).disabled:
		return
	play(PresentationKit.CUE_UI_HOVER)
	if reduced_motion or not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * RiposteTheme.PULSE_SCALE, RiposteTheme.SNAP_SECONDS * 0.5)
	tween.tween_property(control, "scale", Vector2.ONE, RiposteTheme.SNAP_SECONDS)
