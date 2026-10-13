class_name SettingsPanel
extends VBoxContainer

## Every player setting (UX §54) as drill-down sections: a list of
## sections, each opening one short page, so every page fits a 360 px-tall
## landscape phone without scrolling. Toggles and choices save immediately;
## volume drags apply live and save once when the panel leaves the tree.
## Key bindings are two pages (movement, then the other actions): choose a
## binding, press the new key or mouse button, Esc cancels (`KeyBindings`).
## Shared by the Settings screen and the pause overlay.
##
## See also: /docs/concepts/ux.md

signal closed

enum Section { AUDIO, DISPLAY, GAMEPLAY, CONTROLS, MOVE_KEYS, ACTION_KEYS }

const LIST := -1
## Split across two pages so each fits a short landscape phone.
const MOVE_ACTIONS: Array[StringName] = [InputActions.MOVE_UP, InputActions.MOVE_DOWN, InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT]
const OTHER_ACTIONS: Array[StringName] = [InputActions.ATTACK, InputActions.DASH_MODIFIER, InputActions.PAUSE]

var _app: RiposteApp
var _section: int = LIST
var _first: Control
var _dirty: bool = false
## The binding waiting for its new input; empty when none is.
var _capture_action: StringName = &""
var _capture_slot: int = -1
## The binding to focus when its page is rebuilt after a change.
var _refocus_action: StringName = &""
var _refocus_slot: int = 0
var _status: String = ""
var _binding_buttons: Dictionary[StringName, Array] = {}


static func create(app: RiposteApp) -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel._app = app
	panel.name = "SettingsPanel"
	panel._show_list(0)
	return panel


func first_control() -> Control:
	return _first


func section() -> int:
	return _section


## Returns false when already at the section list (the host should close).
## Waiting for a key, back only stops waiting.
func back() -> bool:
	if is_capturing():
		cancel_capture()
		return true
	if _section == LIST:
		return false
	_show_list(_section)
	return true


func _exit_tree() -> void:
	if _dirty:
		_dirty = false
		_app.save_settings()


func _show_list(focus_index: int) -> void:
	_section = LIST
	UiKit.clear(self)
	for index in AppCopy.SETTINGS_SECTIONS.size():
		var entry := UiKit.button(self, AppCopy.SETTINGS_SECTIONS[index], _defer(_show_section.bind(index)))
		if index == focus_index:
			_first = entry
	if not _app.settings.persistence_available:
		UiKit.caption(self, AppCopy.SETTINGS_NOT_SAVED)
	UiKit.button(self, AppCopy.BACK, _defer(closed.emit))
	_focus_first.call_deferred()


func _show_section(index: int) -> void:
	_section = index
	UiKit.clear(self)
	UiKit.section(self, AppCopy.SETTINGS_SECTIONS[index])
	var settings := _app.settings
	match index:
		Section.AUDIO:
			_first = UiKit.slider_row(self, AppCopy.SETTING_MASTER, settings.master_volume, func(value: float) -> void:
				settings.master_volume = value
				_apply_live()
			)
			UiKit.slider_row(self, AppCopy.SETTING_MUSIC, settings.music_volume, func(value: float) -> void:
				settings.music_volume = value
				_apply_live()
			)
			UiKit.slider_row(self, AppCopy.SETTING_SFX, settings.sfx_volume, func(value: float) -> void:
				settings.sfx_volume = value
				_apply_live()
			)
			UiKit.slider_row(self, AppCopy.SETTING_VOICE, settings.voice_volume, func(value: float) -> void:
				settings.voice_volume = value
				_apply_live()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_CAPTIONS, settings.captions, func(on: bool) -> void:
				settings.captions = on
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_SOUND_CAPTIONS, settings.sound_captions, func(on: bool) -> void:
				settings.sound_captions = on
				_app.save_settings()
			)
		Section.DISPLAY:
			_first = UiKit.toggle_row(self, AppCopy.SETTING_FULLSCREEN, settings.fullscreen, func(on: bool) -> void:
				_app.set_fullscreen(on)
			)
			UiKit.toggle_row(self, AppCopy.SETTING_REDUCED_MOTION, settings.reduced_motion, func(on: bool) -> void:
				settings.reduced_motion = on
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_REDUCED_FLASH, settings.reduced_flash, func(on: bool) -> void:
				settings.reduced_flash = on
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_CONTACT_HIGHLIGHT, settings.contact_highlight, func(on: bool) -> void:
				settings.contact_highlight = on
				_app.save_settings()
			)
		Section.GAMEPLAY:
			_first = UiKit.toggle_row(self, AppCopy.SETTING_CHARGE_INDICATOR, settings.show_charge_indicator, func(on: bool) -> void:
				settings.show_charge_indicator = on
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_TRAINING_GEAR, settings.fighter_skin == String(RiposteKits.SKIN_DUELIST_TRAINING), func(on: bool) -> void:
				settings.fighter_skin = String(RiposteKits.SKIN_DUELIST_TRAINING) if on else ""
				settings.weapon_skin = String(RiposteKits.SKIN_BASTARD_SWORD_TRAINING) if on else ""
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_HIGH_CONTRAST, settings.high_contrast_weapons, func(on: bool) -> void:
				settings.high_contrast_weapons = on
				_app.save_settings()
			)
			UiKit.toggle_row(self, AppCopy.SETTING_SCREEN_SHAKE, settings.screen_shake, func(on: bool) -> void:
				settings.screen_shake = on
				_app.save_settings()
			)
			## Both of these change how loudly a cue is drawn and nothing
			## else. Off is a supported way to play, not a handicap: the
			## sweet region is still where it was, and combat stays readable
			## from blade position, wind-back, and recovery alone (UX §54).
			UiKit.caption(self, AppCopy.SETTING_TRAIL)
			UiKit.segmented(self, AppCopy.TRAIL_LEVELS, settings.trail_strength, func(level: int) -> void:
				settings.trail_strength = level as PlayerSettings.TrailStrength
				_app.save_settings()
			, AppCopy.SETTING_TRAIL)
			UiKit.caption(self, AppCopy.SETTING_SWEET_SPOT)
			UiKit.segmented(self, AppCopy.SWEET_SPOT_LEVELS, settings.sweet_spot, func(level: int) -> void:
				settings.sweet_spot = level as PlayerSettings.SweetSpot
				_app.save_settings()
			, AppCopy.SETTING_SWEET_SPOT)
		Section.CONTROLS:
			UiKit.caption(self, AppCopy.SETTING_CONTROL_OPACITY)
			var choose_level := func(level: int) -> void:
				settings.control_opacity = level as PlayerSettings.ControlOpacity
				_app.save_settings()
			_first = UiKit.segmented(self, AppCopy.OPACITY_LEVELS, settings.control_opacity, choose_level, AppCopy.SETTING_CONTROL_OPACITY)[0]
			UiKit.toggle_row(self, AppCopy.SETTING_HAPTICS, settings.haptics, func(on: bool) -> void:
				settings.haptics = on
				_app.save_settings()
			)
			## No hold required: press to begin a charge, press again to
			## swing. The same commands reach the simulation either way.
			UiKit.toggle_row(self, AppCopy.SETTING_CHARGE_TOGGLE, settings.charge_toggle, func(on: bool) -> void:
				settings.charge_toggle = on
				_app.save_settings()
			)
		Section.MOVE_KEYS:
			_binding_page(MOVE_ACTIONS)
		Section.ACTION_KEYS:
			_binding_page(OTHER_ACTIONS)
	UiKit.button(self, AppCopy.BACK, _defer(_show_list.bind(index)))
	_focus_first.call_deferred()


func is_capturing() -> bool:
	return _capture_action != &""


## The button showing `action`'s `slot` on the open page, or null.
func binding_button(action: StringName, slot: int) -> Button:
	var buttons: Array = _binding_buttons.get(action, [])
	return buttons[slot] as Button if slot < buttons.size() else null


func status_text() -> String:
	return _status


## Wait for the next key or mouse button for `action`'s `slot`.
func begin_capture(action: StringName, slot: int) -> void:
	cancel_capture()
	var target := binding_button(action, slot)
	if target == null:
		return
	_capture_action = action
	_capture_slot = slot
	target.text = AppCopy.BINDING_PRESS


func cancel_capture() -> void:
	if not is_capturing():
		return
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = &""
	_capture_slot = -1
	var target := binding_button(action, slot)
	if target != null:
		target.text = AppCopy.binding_label(_app.settings.bindings.code(action, slot))


## While waiting, every key and button press is the answer (or Esc, which
## cancels), and none of them reaches focus navigation or the game.
func _input(event: InputEvent) -> void:
	if not is_capturing():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		cancel_capture()
		return
	var binding := KeyBindings.code_of(event)
	if binding == 0:
		cancel_capture()
		return
	_finish_capture(binding)


func _finish_capture(binding: int) -> void:
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = &""
	_capture_slot = -1
	var bindings := _app.settings.bindings
	if bindings.bind(action, slot, binding):
		_status = ""
		_app.save_settings()
	else:
		var holder := bindings.owner_of(binding)
		_status = AppCopy.BINDING_REFUSED % [AppCopy.binding_label(binding), AppCopy.binding_action(KeyBindings.ACTIONS[holder.x])] if holder.x >= 0 else ""
	_refocus_action = action
	_refocus_slot = slot
	_show_section.call_deferred(_section)


func _binding_page(actions: Array[StringName]) -> void:
	var bindings := _app.settings.bindings
	_binding_buttons.clear()
	UiKit.caption(self, _status if _status != "" else AppCopy.BINDING_HINT)
	for action in actions:
		var labels := PackedStringArray()
		for slot in KeyBindings.SLOTS:
			labels.append(AppCopy.binding_label(bindings.code(action, slot)))
		var buttons := UiKit.binding_row(self, AppCopy.binding_action(action), labels, func(slot: int) -> void: begin_capture(action, slot))
		_binding_buttons[action] = buttons
		if action == actions[0]:
			_first = buttons[0]
		if action == _refocus_action:
			_first = buttons[_refocus_slot]
	UiKit.button(self, AppCopy.BINDING_RESET, func() -> void:
		bindings.reset()
		_status = ""
		_app.save_settings()
		_refocus_action = &""
		_show_section.call_deferred(_section)
	)


func _apply_live() -> void:
	_dirty = true
	_app.settings.apply_audio()


## Page swaps free the pressed button, so they never run inside its signal.
func _defer(action: Callable) -> Callable:
	return func() -> void: action.call_deferred()


func _focus_first() -> void:
	if _first != null and is_instance_valid(_first) and _first.is_inside_tree() and not DisplayServer.is_touchscreen_available():
		_first.grab_focus()
