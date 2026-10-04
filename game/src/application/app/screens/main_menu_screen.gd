class_name MainMenuScreen
extends ScreenBase

## Main menu (UX §55, §60): one primary action (Quick Play) with the
## remembered difficulty beside it, then How to Play, Settings, and the
## community destinations ("Soon" until real URLs exist, WEB-006).
##
## See also: /docs/concepts/ux.md


func build() -> void:
	UiKit.title(lead, AppCopy.TITLE)
	UiKit.body(lead, AppCopy.TAGLINE, true)
	set_primary(UiKit.button(body, AppCopy.QUICK_PLAY, app.start_quick_play, &"PrimaryButton"))
	UiKit.caption(body, AppCopy.DIFFICULTY)
	UiKit.segmented(body, AppCopy.difficulty_labels(), app.settings.difficulty, app.set_difficulty, AppCopy.DIFFICULTY)
	var line := UiKit.row(body)
	UiKit.button(line, AppCopy.HOW_TO_PLAY, app.go_to.bind(AppScreen.Id.HOW_TO_PLAY))
	UiKit.button(line, AppCopy.SETTINGS, app.open_settings)
	var community := UiKit.row(body)
	_community(community, AppCopy.DISCORD, CommunityLinks.COMMUNITY)
	_community(community, AppCopy.PATREON, CommunityLinks.SUPPORT)


## The main menu is the root: Escape has nowhere to go back to.
func back() -> void:
	pass


func _community(host: Container, label: String, url: String) -> void:
	if CommunityLinks.is_configured(url):
		UiKit.button(host, label, app.open_community.bind(label, url))
	else:
		UiKit.stub_button(host, label, AppCopy.SOON, AppCopy.COMING_SOON)
