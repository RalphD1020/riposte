class_name SettingsPanel
extends VBoxContainer

## Every player setting (UX §54) as drill-down sections: a list of four
## sections, each opening one short page, so every page fits a 360 px-tall
## landscape phone without scrolling. Toggles and choices save immediately;
## volume drags apply live and save once when the panel leaves the tree.
## Shared by the Settings screen and the pause overlay.
##
## See also: /docs/concepts/ux.md

signal closed

enum Section { AUDIO, DISPLAY, GAMEPLAY, CONTROLS }

const LIST := -1

var _app: RiposteApp
var _section: int = LIST
var _first: Control
var _dirty: bool = false


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
func back() -> bool:
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
	UiKit.button(self, AppCopy.BACK, _defer(_show_list.bind(index)))
	_focus_first.call_deferred()


func _apply_live() -> void:
	_dirty = true
	_app.settings.apply_audio()


## Page swaps free the pressed button, so they never run inside its signal.
func _defer(action: Callable) -> Callable:
	return func() -> void: action.call_deferred()


func _focus_first() -> void:
	if _first != null and is_instance_valid(_first) and _first.is_inside_tree() and not DisplayServer.is_touchscreen_available():
		_first.grab_focus()
