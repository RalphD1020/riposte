class_name SettingsScreen
extends ScreenBase

## Settings (UX §54) as a screen. Escape walks back out of a section before
## leaving; the panel itself saves.
##
## See also: /docs/concepts/ux.md

var panel: SettingsPanel


func build() -> void:
	UiKit.heading(lead, AppCopy.SETTINGS)
	panel = SettingsPanel.create(app)
	panel.closed.connect(app.go_to.bind(AppScreen.Id.MAIN_MENU))
	body.add_child(panel)
	set_primary(panel.first_control())


func back() -> void:
	if not panel.back():
		app.go_to(AppScreen.Id.MAIN_MENU)
