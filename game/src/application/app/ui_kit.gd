class_name UiKit
extends RefCounted

## Static builders for menu chrome. Every control gets a visible label or an
## accessible name, a 48 px target, keyboard focus, and a RiposteTheme type
## variation; nothing styles itself ad hoc (UX §36, §41–§48, §69–§70).
##
## See also: /docs/concepts/ux.md

## Slider granularity: 20 steps across the range. Coarse enough that a thumb
## on a phone lands where it meant to, and it is what an arrow key moves by.
const SLIDER_STEP := 0.05

## The app's shared menu feel (pulse + UI sounds), attached to every button
## this kit builds. Null in isolated tests; controls work without it.
static var feedback: UiFeedback


static func title(host: Container, text: String) -> Label:
	var label := _label(host, text, &"TitleLabel")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func heading(host: Container, text: String) -> Label:
	return _label(host, text, &"HeadingLabel")


static func section(host: Container, text: String) -> Label:
	return _label(host, text, &"SectionLabel")


static func body(host: Container, text: String, centered: bool = false) -> Label:
	var label := _label(host, text, &"")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1.0
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func caption(host: Container, text: String) -> Label:
	var label := body(host, text, true)
	label.theme_type_variation = &"CaptionLabel"
	return label


static func button(host: Container, text: String, handler: Callable, variation: StringName = &"") -> Button:
	var control := Button.new()
	control.text = text
	RiposteTheme.style_button(control, variation)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if handler.is_valid():
		control.pressed.connect(handler)
	host.add_child(control)
	if feedback != null and is_instance_valid(feedback):
		feedback.attach(control)
	return control


## A disabled stub whose accessible name still says why it does nothing.
static func stub_button(host: Container, text: String, note: String, accessible_note: String) -> Button:
	var control := button(host, "%s · %s" % [text, note], Callable())
	control.disabled = true
	control.accessibility_name = "%s. %s" % [text, accessible_note]
	return control


static func row(host: Container) -> HBoxContainer:
	var line := HBoxContainer.new()
	host.add_child(line)
	return line


## Mutually exclusive choice. The selected option is filled AND carries a
## drawn marker, never color alone (UX §50, §84).
static func segmented(host: Container, labels: PackedStringArray, selected: int, on_select: Callable, accessible_prefix: String) -> Array[Button]:
	var line := row(host)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for index in labels.size():
		var option := Button.new()
		option.text = labels[index]
		option.toggle_mode = true
		option.button_group = group
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.accessibility_name = "%s: %s" % [accessible_prefix, labels[index]]
		RiposteTheme.style_button(option)
		line.add_child(option)
		buttons.append(option)
		if feedback != null and is_instance_valid(feedback):
			feedback.attach(option)
	var marker := HudIcons.marker(RiposteTheme.TEXT_ON_DARK)
	var refresh := func(chosen: int) -> void:
		for index in buttons.size():
			var option := buttons[index]
			option.set_pressed_no_signal(index == chosen)
			option.icon = marker if index == chosen else null
			option.theme_type_variation = &"PrimaryButton" if index == chosen else &""
	for index in buttons.size():
		buttons[index].pressed.connect(func() -> void:
			refresh.call(index)
			on_select.call(index)
		)
	refresh.call(clampi(selected, 0, buttons.size() - 1))
	return buttons


static func toggle_row(host: Container, text: String, value: bool, on_toggle: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = value
	toggle.accessibility_name = text
	toggle.custom_minimum_size = Vector2(0.0, RiposteTheme.TOUCH_TARGET)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.toggled.connect(on_toggle)
	host.add_child(toggle)
	return toggle


## Label and slider share one 48 px row so a section fits a short phone.
static func slider_row(host: Container, text: String, value: float, on_change: Callable) -> HSlider:
	var line := row(host)
	var label := _label(line, text, &"FieldLabel")
	label.custom_minimum_size = Vector2(RiposteTheme.FIELD_LABEL_WIDTH, RiposteTheme.TOUCH_TARGET)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = SLIDER_STEP
	slider.value = value
	slider.accessibility_name = text
	slider.custom_minimum_size = Vector2(0.0, RiposteTheme.TOUCH_TARGET)
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	line.add_child(slider)
	return slider


## A modal sheet: dimmed backdrop that swallows input, centered column.
static func sheet(parent: Control) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = RiposteTheme.OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Sheet"
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"SheetMargin"
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(RiposteTheme.SHEET_WIDTH, 0.0)
	margin.add_child(column)
	return column


static func clear(host: Container) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()


static func _label(host: Container, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	host.add_child(label)
	return label
