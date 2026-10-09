class_name DuelHud
extends Control

## In-match status (UX §23–§24): two mirrored ornamental name plates with
## restrained health and stamina rules, sword-point round pips, the round and
## low-time clock in a centre plate, one slashing banner, announcer captions,
## an optional coaching prompt, and the pause button. The human is always on
## the left. Condition reads first from the fighter's body in the world; the
## plate repeats it as a shape icon and a word, never as colour alone.
##
## A pure view of PresentationSnapshot that writes a Label only when its value
## changes, so a tick costs a few comparisons.
##
## See also: /docs/concepts/ux.md

signal pause_pressed

const LOW_TIME_TICKS := 600

var human_slot: int = 0
var _human_side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var _labels: PackedStringArray = PackedStringArray(["", ""])
var _frame: MarginContainer
var _bars: Array[ProgressBar] = []
var _stamina_bars: Array[ProgressBar] = []
var _condition_labels: Array[Label] = []
var _condition_icons: Array[TextureRect] = []
var _pips: Array[PipRow] = []
var _caption_plate: PanelContainer
var _caption: Label
var _caption_left: float = 0.0
var _banner_tween: Tween
var _card: String = ""
var _card_active: bool = false
## Banner and menu motion honour Reduced Motion: the text still changes, it
## simply does not slash in.
var reduced_motion: bool = false
var _round: Label
var _clock: Label
var _banner_plate: PanelContainer
var _banner: Label
var _prompt_plate: PanelContainer
var _prompt_title: Label
var _prompt_detail: Label
var _pause: Button
var _shown_health: PackedFloat64Array = PackedFloat64Array([-1.0, -1.0])
var _shown_stamina: PackedFloat64Array = PackedFloat64Array([-1.0, -1.0])
var _shown_condition: PackedInt32Array = PackedInt32Array([-1, -1])
var _shown_wins: PackedInt32Array = PackedInt32Array([-1, -1])
var _shown_round: int = -1
var _shown_banner: String = ""
var _shown_clock: String = ""


static func create(player_label: String, opponent_label: String, slot: int, human_side: DuelSide.Id) -> DuelHud:
	var hud := DuelHud.new()
	hud.human_slot = slot
	hud._human_side = human_side
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
		if fighter.stamina != _shown_stamina[side]:
			_shown_stamina[side] = fighter.stamina
			var sbar := _stamina_bars[side]
			sbar.max_value = maxf(fighter.stamina_max, 1.0)
			sbar.value = fighter.stamina
			sbar.accessibility_description = HudCopy.STAMINA_VALUE % [ceili(fighter.stamina), ceili(fighter.stamina_max)]
		var cond_int := int(fighter.condition)
		if cond_int != _shown_condition[side]:
			_shown_condition[side] = cond_int
			_condition_labels[side].text = FighterCondition.label(fighter.condition)
			_condition_icons[side].texture = HudIcons.condition(fighter.condition)
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
	var banner := _card if _card_active else HudCopy.banner(snapshot, human_slot)
	if banner != _shown_banner:
		_shown_banner = banner
		_banner.text = banner
		_banner_plate.visible = banner != ""
		if banner != "":
			_slash_in()


## Slash in from the side, hold, snap out: a banner arrives with a short
## horizontal strike and leaves instantly, never drifting.
func _slash_in() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_plate.modulate.a = 1.0
	if reduced_motion or not is_inside_tree():
		return
	_banner_plate.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner_plate, "modulate:a", 1.0, RiposteTheme.SNAP_SECONDS)
	_banner_tween.tween_method(_banner_offset, -RiposteTheme.BANNER_SLASH_DISTANCE, 0.0, RiposteTheme.SNAP_SECONDS)


## The centring container settles the plate at x = 0 relative to its slot,
## so the slash is an offset from where the layout put it.
func _banner_offset(offset: float) -> void:
	_banner_plate.position.x = (_banner_plate.get_parent_area_size().x - _banner_plate.size.x) * 0.5 + offset


## Intro cards borrow the banner plate. An empty card ends the intro and
## hands the plate back to the snapshot's banner on the next update.
func show_card(text: String) -> void:
	_card_active = text != ""
	_card = text
	if _card_active and text != _shown_banner:
		_shown_banner = text
		_banner.text = text
		_banner_plate.visible = true
		_slash_in()
	elif not _card_active:
		_shown_banner = ""
		_banner.text = ""
		_banner_plate.visible = false


## An announcer line as on-screen text, so the moment reads with sound off.
func show_caption(text: String, seconds: float) -> void:
	_caption.text = text
	_caption_plate.visible = text != ""
	_caption_left = seconds


func caption_text() -> String:
	return _caption.text if _caption_plate.visible else ""


func _process(delta: float) -> void:
	if _caption_left <= 0.0:
		return
	_caption_left -= delta
	if _caption_left <= 0.0:
		_caption_plate.visible = false


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


func stamina_bar(side: int) -> ProgressBar:
	return _stamina_bars[side]


func condition_label(side: int) -> Label:
	return _condition_labels[side]


func condition_icon(side: int) -> TextureRect:
	return _condition_icons[side]


func pips(side: int) -> PipRow:
	return _pips[side]


func _slot_on(side: int) -> int:
	return human_slot if side == 0 else 1 - human_slot


func _side_of(display_side: int) -> DuelSide.Id:
	return _human_side if display_side == 0 else DuelSide.other(_human_side)


func _health_variation(display_side: int) -> StringName:
	var duel_side := _side_of(display_side)
	return &"LightHealthBar" if duel_side == DuelSide.Id.LIGHT_SOUTH else &"DarkHealthBar"


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
	_banner_plate = _plate(stage, &"BannerPlate")
	_banner = Label.new()
	_banner.theme_type_variation = &"BannerLabel"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.accessibility_live = AccessibilityServer.LIVE_POLITE
	_banner_plate.add_child(_banner)
	_banner_plate.visible = false
	_caption_plate = _plate(column, &"CaptionPlate")
	_caption_plate.size_flags_horizontal = SIZE_SHRINK_CENTER
	_caption = _hud_label(_caption_plate, "", &"AnnouncerCaption")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.accessibility_live = AccessibilityServer.LIVE_POLITE
	_caption_plate.visible = false


func _fighter_plate(row: HBoxContainer, side: int) -> void:
	var plate := _plate(row, &"HudPlateMirrored" if side == 1 else &"HudPlate")
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
	var name_label := _hud_label(heading, _labels[side], &"HudNameLabel")
	name_label.clip_text = true
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == 1 else HORIZONTAL_ALIGNMENT_LEFT
	if side == 0:
		heading.add_child(wins)
	var rule := TextureRect.new()
	rule.texture = HudIcons.divider()
	rule.flip_h = side == 1
	rule.stretch_mode = TextureRect.STRETCH_KEEP
	rule.size_flags_horizontal = SIZE_SHRINK_END if side == 1 else SIZE_SHRINK_BEGIN
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	stack.add_child(rule)
	var bar := ProgressBar.new()
	bar.theme_type_variation = _health_variation(side)
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
	var sbar := ProgressBar.new()
	sbar.theme_type_variation = &"StaminaBar"
	sbar.show_percentage = false
	sbar.min_value = 0.0
	sbar.max_value = 100.0
	sbar.value = 100.0
	sbar.custom_minimum_size = Vector2(0.0, RiposteTheme.STAMINA_BAR_HEIGHT)
	sbar.mouse_filter = MOUSE_FILTER_IGNORE
	sbar.accessibility_name = HudCopy.STAMINA % _labels[side]
	sbar.fill_mode = ProgressBar.FILL_END_TO_BEGIN if side == 1 else ProgressBar.FILL_BEGIN_TO_END
	stack.add_child(sbar)
	_stamina_bars.append(sbar)
	var condition_row := HBoxContainer.new()
	condition_row.mouse_filter = MOUSE_FILTER_IGNORE
	condition_row.alignment = BoxContainer.ALIGNMENT_END if side == 1 else BoxContainer.ALIGNMENT_BEGIN
	stack.add_child(condition_row)
	var icon := TextureRect.new()
	icon.texture = HudIcons.condition(FighterCondition.Id.HEALTHY)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	_condition_icons.append(icon)
	var cond := Label.new()
	cond.theme_type_variation = &"HudCaptionLabel"
	cond.text = FighterCondition.label(FighterCondition.Id.HEALTHY)
	_condition_labels.append(cond)
	for part: Control in ([cond, icon] if side == 1 else [icon, cond]):
		condition_row.add_child(part)


func _center_plate(row: HBoxContainer) -> void:
	var plate := _plate(row, &"HudCenterPlate")
	var stack := _vbox(plate)
	_round = _hud_label(stack, "")
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock = _hud_label(stack, "", &"HudAccentLabel")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.visible = false


func _plate(host: Container, variation: StringName = &"HudPlate") -> PanelContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = variation
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
