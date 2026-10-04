class_name DuelHud
extends Control

## In-match status (UX §23–§24): both health bars, round pips, the round
## number and low-time clock, one banner, an optional coaching prompt, and
## the pause button. The human is always on the left. A pure view of
## PresentationSnapshot that writes a Label only when its value changes, so a
## tick costs a few comparisons.
##
## See also: /docs/concepts/ux.md

signal pause_pressed

const LOW_TIME_TICKS := 600

var human_slot: int = 0
var _labels: PackedStringArray = PackedStringArray(["", ""])
var _frame: MarginContainer
var _bars: Array[ProgressBar] = []
var _pips: Array[PipRow] = []
var _round: Label
var _clock: Label
var _banner_plate: PanelContainer
var _banner: Label
var _prompt_plate: PanelContainer
var _prompt_title: Label
var _prompt_detail: Label
var _pause: Button
var _shown_health: PackedFloat64Array = PackedFloat64Array([-1.0, -1.0])
var _shown_wins: PackedInt32Array = PackedInt32Array([-1, -1])
var _shown_round: int = -1
var _shown_banner: String = ""
var _shown_clock: String = ""


static func create(player_label: String, opponent_label: String, slot: int) -> DuelHud:
	var hud := DuelHud.new()
	hud.human_slot = slot
	hud._labels = PackedStringArray([player_label, opponent_label])
	hud._build()
	return hud


## Safe-area insets keep plates clear of notches (UX §38).
func layout_insets(insets: Vector4) -> void:
	RiposteTheme.apply_insets(_frame, RiposteTheme.HUD_EDGE, insets)


func update(snapshot: PresentationSnapshot) -> void:
	for side in 2:
		var fighter := snapshot.fighter(_slot_on(side))
		if fighter.health != _shown_health[side]:
			_shown_health[side] = fighter.health
			var bar := _bars[side]
			bar.max_value = fighter.max_health
			bar.value = fighter.health
			bar.accessibility_description = HudCopy.HEALTH_VALUE % [ceili(fighter.health), ceili(fighter.max_health)]
		var wins := snapshot.scores[_slot_on(side)]
		if wins != _shown_wins[side]:
			_shown_wins[side] = wins
			_pips[side].show_wins(wins, snapshot.rounds_to_win)
			_pips[side].accessibility_name = HudCopy.ROUNDS_WON % [_labels[side], wins, snapshot.rounds_to_win]
	if snapshot.round_number != _shown_round:
		_shown_round = snapshot.round_number
		_round.text = HudCopy.ROUND % snapshot.round_number
	var low_time := snapshot.phase == MatchPhase.Id.ROUND_ACTIVE and snapshot.time_left_ticks <= LOW_TIME_TICKS
	var remaining := HudCopy.clock(snapshot.time_left_ticks) if low_time else ""
	if remaining != _shown_clock:
		_shown_clock = remaining
		_clock.text = remaining
		_clock.visible = remaining != ""
	var banner := HudCopy.banner(snapshot, human_slot)
	if banner != _shown_banner:
		_shown_banner = banner
		_banner.text = banner
		_banner_plate.visible = banner != ""


func show_prompt(title: String, detail: String) -> void:
	_prompt_title.text = title
	_prompt_detail.text = detail
	_prompt_plate.visible = true


func hide_prompt() -> void:
	_prompt_plate.visible = false


func pause_button() -> Button:
	return _pause


func banner_text() -> String:
	return _shown_banner


func prompt_title() -> String:
	return _prompt_title.text if _prompt_plate.visible else ""


func clock_text() -> String:
	return _shown_clock


func health_bar(side: int) -> ProgressBar:
	return _bars[side]


func pips(side: int) -> PipRow:
	return _pips[side]


func _slot_on(side: int) -> int:
	return human_slot if side == 0 else 1 - human_slot


func _build() -> void:
	name = "DuelHud"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_frame.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_frame)
	layout_insets(Vector4.ZERO)
	var column := _vbox(_frame)
	var top := HBoxContainer.new()
	top.theme_type_variation = &"HudRow"
	top.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(top)
	_fighter_plate(top, 0)
	_center_plate(top)
	_fighter_plate(top, 1)
	_pause = Button.new()
	_pause.icon = HudIcons.pause()
	_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.accessibility_name = HudCopy.PAUSE
	_pause.tooltip_text = HudCopy.PAUSE
	RiposteTheme.style_button(_pause, &"HudButton")
	_pause.custom_minimum_size = Vector2(RiposteTheme.TOUCH_TARGET, RiposteTheme.TOUCH_TARGET)
	## Never keyboard-focusable mid-duel: Space must attack, not press Pause.
	_pause.focus_mode = FOCUS_NONE
	_pause.pressed.connect(pause_pressed.emit)
	top.add_child(_pause)
	_prompt_plate = _plate(column)
	_prompt_plate.size_flags_horizontal = SIZE_SHRINK_CENTER
	var prompt := _vbox(_prompt_plate)
	_prompt_title = _hud_label(prompt, "", &"HudTitleLabel")
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_title.accessibility_live = AccessibilityServer.LIVE_POLITE
	_prompt_detail = _hud_label(prompt, "")
	_prompt_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_plate.visible = false
	var stage := CenterContainer.new()
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(stage)
	_banner_plate = _plate(stage)
	_banner = Label.new()
	_banner.theme_type_variation = &"BannerLabel"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.accessibility_live = AccessibilityServer.LIVE_POLITE
	_banner_plate.add_child(_banner)
	_banner_plate.visible = false


func _fighter_plate(row: HBoxContainer, side: int) -> void:
	var plate := _plate(row)
	plate.size_flags_horizontal = SIZE_EXPAND_FILL
	var stack := _vbox(plate)
	var heading := HBoxContainer.new()
	heading.mouse_filter = MOUSE_FILTER_IGNORE
	stack.add_child(heading)
	## Mirrored plates: name then pips on the left, pips then name on the right.
	var wins := PipRow.new()
	wins.mirrored = side == 1
	wins.size_flags_vertical = SIZE_SHRINK_CENTER
	_pips.append(wins)
	if side == 1:
		heading.add_child(wins)
	var name_label := _hud_label(heading, _labels[side])
	name_label.clip_text = true
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == 1 else HORIZONTAL_ALIGNMENT_LEFT
	if side == 0:
		heading.add_child(wins)
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"OpponentHealthBar" if side == 1 else &"PlayerHealthBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(0.0, RiposteTheme.HEALTH_BAR_HEIGHT)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.accessibility_name = HudCopy.HEALTH % _labels[side]
	## Bars drain toward the outer edges.
	bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN if side == 1 else ProgressBar.FILL_BEGIN_TO_END
	stack.add_child(bar)
	_bars.append(bar)


func _center_plate(row: HBoxContainer) -> void:
	var plate := _plate(row)
	var stack := _vbox(plate)
	_round = _hud_label(stack, "")
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock = _hud_label(stack, "", &"HudAccentLabel")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.visible = false


func _plate(host: Container) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"HudPlate"
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	host.add_child(plate)
	return plate


func _vbox(host: Container) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.theme_type_variation = &"HudStack"
	box.mouse_filter = MOUSE_FILTER_IGNORE
	host.add_child(box)
	return box


func _hud_label(host: Container, text: String, variation: StringName = &"HudLabel") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	host.add_child(label)
	return label
