class_name RoundStartDirector
extends Control

## The beat before every round (PRES-ROUND-START-001): "MATCH N" over the set
## score, then "FIGHT!" on the instant the round goes live. Presentation only:
## the round's own intro ticks (`DuelRules.intro_ticks`) are the window, and
## the screen tells this director when a round is being introduced and when it
## went live — it never steps, reads, or gates the simulation. Every call is
## the intro announcer's voice and is captioned.
##
## The set intro (once per set) comes first; this card comes every round,
## including the first. Driven by `advance(delta)` from the screen's frame
## loop on real time, like the intro, so it is exact in headless tests.
##
## See also: /docs/concepts/presentation.md

signal cue_announced(cue: StringName, number: int)

const CUE_MATCH := &"match"
const CUE_FIGHT := &"fight"
## How long "FIGHT!" stays after the round goes live (real seconds). Input is
## already live underneath it.
const FIGHT_HOLD_SECONDS := 0.45
## The "FIGHT!" plate lands large and settles (skipped under Reduced Motion).
const FIGHT_PUNCH_SCALE := 1.35

var reduced_motion: bool = false
var _announcer: AnnouncerKit
var _audio: AudioDirector
var _plate: PanelContainer
var _label: Label
var _score_row: HBoxContainer
var _names: Array[Label] = []
var _pips: Array[PipRow] = []
var _fight_left: float = -1.0
var _cue: StringName = &""


static func create(announcer: AnnouncerKit, audio: AudioDirector, labels: PackedStringArray) -> RoundStartDirector:
	var director := RoundStartDirector.new()
	director._announcer = announcer if announcer != null else AnnouncerKit.new()
	director._audio = audio
	director._build(labels)
	return director


## A round is being introduced: show "MATCH N" over the set score (ordered as
## the HUD orders the fighters) and make the call.
func announce_match(number: int, scores: PackedInt32Array, rounds_to_win: int) -> void:
	_cue = CUE_MATCH
	_fight_left = -1.0
	_show(HudCopy.MATCH % number)
	_score_row.visible = true
	for side in 2:
		_pips[side].show_wins(scores[side], rounds_to_win)
	if _audio != null:
		_audio.play_voice(_announcer.match_line(number), _announcer.match_caption % number)
	cue_announced.emit(CUE_MATCH, number)


## The round just went live: "FIGHT!", once, on this very frame.
func fight() -> void:
	_cue = CUE_FIGHT
	_fight_left = FIGHT_HOLD_SECONDS
	_show(HudCopy.FIGHT)
	_score_row.visible = false
	if not reduced_motion and is_inside_tree():
		_plate.pivot_offset = _plate.size * 0.5
		_plate.scale = Vector2.ONE * FIGHT_PUNCH_SCALE
		create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT).tween_property(_plate, "scale", Vector2.ONE, RiposteTheme.SNAP_SECONDS)
	if _audio != null:
		_audio.play_voice(_announcer.fight, _announcer.fight_caption)
	cue_announced.emit(CUE_FIGHT, 0)


func advance(delta: float) -> void:
	if _fight_left < 0.0:
		return
	_fight_left -= delta
	if _fight_left < 0.0:
		clear()


## Take the card down (a skip, a pause-to-menu, or the end of "FIGHT!").
func clear() -> void:
	_cue = &""
	_fight_left = -1.0
	visible = false


func is_showing() -> bool:
	return visible


## The cue on screen (`CUE_MATCH`, `CUE_FIGHT`, or empty).
func showing_cue() -> StringName:
	return _cue


func text() -> String:
	return _label.text if visible else ""


func _show(card: String) -> void:
	_label.text = card
	visible = true


func _build(labels: PackedStringArray) -> void:
	name = "RoundStart"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var stage := CenterContainer.new()
	stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"HudStack"
	column.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(column)
	_plate = PanelContainer.new()
	_plate.theme_type_variation = &"BannerPlate"
	_plate.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(_plate)
	_label = Label.new()
	_label.theme_type_variation = &"BannerLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	_plate.add_child(_label)
	_score_row = HBoxContainer.new()
	_score_row.theme_type_variation = &"HudRow"
	_score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_row.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(_score_row)
	for side in 2:
		var name_label := Label.new()
		name_label.theme_type_variation = &"HudCaptionLabel"
		name_label.text = labels[side]
		name_label.mouse_filter = MOUSE_FILTER_IGNORE
		var pips := PipRow.new()
		_names.append(name_label)
		_pips.append(pips)
		if side == 0:
			_score_row.add_child(name_label)
			_score_row.add_child(pips)
		else:
			_score_row.add_child(pips)
			_score_row.add_child(name_label)
