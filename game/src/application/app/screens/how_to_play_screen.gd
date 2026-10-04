class_name HowToPlayScreen
extends ScreenBase

## How to Play (UX §56): the two verbs, the physical rules, and a direct
## path into Training, where the lesson is demonstrated rather than read.
##
## See also: /docs/concepts/controls.md


func build() -> void:
	UiKit.heading(lead, AppCopy.HOW_TO_PLAY)
	UiKit.body(lead, AppCopy.HOW_TO_PLAY_LEAD)
	HowToPlayPanel.controls(lead)
	HowToPlayPanel.principles(body)
	set_primary(UiKit.button(body, AppCopy.START_TRAINING, app.start_training, &"PrimaryButton"))
	UiKit.button(body, AppCopy.BACK, back)
