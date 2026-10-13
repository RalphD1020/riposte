class_name AppCopy
extends RefCounted

## Every menu and coaching string in the game, in one place (the game's
## equivalent of the website's SiteCopy). Plain language, no flavor names
## that hide meaning (UX §83). In-duel HUD strings live in HudCopy. Only use
## glyphs the shipped font renders (PRES-THEME proves it).
##
## See also: /docs/concepts/ux.md

const TITLE := "RIPOSTE"
const TAGLINE := "Steel, timing, and the space between."
const QUICK_PLAY := "QUICK PLAY"
const DIFFICULTY := "Difficulty"
const HOW_TO_PLAY := "HOW TO PLAY"
const SETTINGS := "SETTINGS"
const START_TRAINING := "START TRAINING"
const BACK := "BACK"
const COMING_SOON := "Coming soon"
const SOON := "Soon"
const DISCORD := "Discord"
const PATREON := "Patreon"

const REMATCH := "REMATCH"
const RETURN_TO_MENU := "RETURN TO MENU"
const RESUME := "RESUME"
const QUIT_TO_MENU := "QUIT TO MENU"
const PAUSED := "PAUSED"

const YOU := "YOU"
const CPU := "CPU · %s"
const DUMMY := "DUMMY"
const SCORE := "%d — %d"

const RESULT_ROUNDS := "Rounds played: %d"
const RESULT_BEST := "Most damaging strike: %d"
const RESULT_PARRIES := "Parries: %d"
const RESULT_CHARGE := "Average charge: %d%%"

const HOW_TO_PLAY_LEAD := "Two verbs. That is the whole game."
const CONTROLS_MOVE := "MOVE"
const CONTROLS_MOVE_HOW := "WASD or arrow keys · Left thumb"
const CONTROLS_ATTACK := "ATTACK"
const CONTROLS_ATTACK_HOW := "Left mouse or Space · Right side of the screen"
const CONTROLS_VERBS := "Tap for a quick cut. Hold to wind back and charge. Release to swing."
const CONTROLS_PHYSICS := "Your sword stays where it stops; the next cut starts there. Put your blade in their path to parry, then strike before they recover."
const CONTROLS_PAUSE := "Esc pauses. You always face your opponent."

const SETTINGS_SECTIONS: PackedStringArray = ["Audio", "Display", "Gameplay", "Controls", "Move keys", "Action keys"]
const SETTING_SOUND_CAPTIONS := "Sound captions"
const SETTING_CONTACT_HIGHLIGHT := "Show where blades touch"
const BINDING_ACTIONS := {
	InputActions.MOVE_UP: "Move up",
	InputActions.MOVE_DOWN: "Move down",
	InputActions.MOVE_LEFT: "Move left",
	InputActions.MOVE_RIGHT: "Move right",
	InputActions.ATTACK: "Attack",
	InputActions.DASH_MODIFIER: "Dash",
	InputActions.PAUSE: "Pause",
}
const BINDING_PRESS := "Press a key"
const BINDING_NONE := "None"
## Accessible name of one binding button: action, slot number, current input.
const BINDING_SLOT := "%s, binding %d: %s"
const BINDING_RESET := "Reset keys"
const BINDING_HINT := "Choose a binding, then press the new key or mouse button. Esc cancels."
const BINDING_REFUSED := "%s is the only binding for %s."
const MOUSE_BUTTON_LABELS := {
	MOUSE_BUTTON_LEFT: "Left mouse",
	MOUSE_BUTTON_RIGHT: "Right mouse",
	MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_XBUTTON1: "Mouse back",
	MOUSE_BUTTON_XBUTTON2: "Mouse forward",
}
const SETTING_MASTER := "Master volume"
const SETTING_MUSIC := "Music volume"
const SETTING_SFX := "Effects volume"
const SETTING_VOICE := "Announcer volume"
const SETTING_CAPTIONS := "Announcer captions"
const SETTING_FULLSCREEN := "Fullscreen"
const SETTING_REDUCED_MOTION := "Reduced motion"
const SETTING_REDUCED_FLASH := "Reduced flash"
const SETTING_CHARGE_INDICATOR := "Show charge indicator"
const SETTING_HIGH_CONTRAST := "High contrast weapons"
const SETTING_SCREEN_SHAKE := "Screen shake"
const SETTING_TRAIL := "Blade trail"
const SETTING_SWEET_SPOT := "Sweet spot emphasis"
const TRAIL_LEVELS: PackedStringArray = ["Off", "Subtle", "Full"]
const SWEET_SPOT_LEVELS: PackedStringArray = ["Off", "Standard", "Strong"]
const SETTING_CONTROL_OPACITY := "Touch control opacity"
const SETTING_HAPTICS := "Haptics"
const SETTING_CHARGE_TOGGLE := "Toggle charge (tap to start, tap to swing)"
const SETTING_TRAINING_GEAR := "Training gear (cosmetic)"
const OPACITY_LEVELS: PackedStringArray = ["Low", "Medium", "High"]
const SETTINGS_NOT_SAVED := "Settings could not be saved on this device; they last for this visit."

const TUTORIAL_STEPS := {
	TutorialTracker.Step.MOVE: ["MOVE", "WASD or left thumb"],
	TutorialTracker.Step.QUICK_CUT: ["QUICK CUT", "Tap attack"],
	TutorialTracker.Step.CHARGE: ["CHARGE", "Hold attack"],
	TutorialTracker.Step.RELEASE: ["RELEASE", "Let go to swing"],
	TutorialTracker.Step.BLADES: ["BLADES ARE PHYSICAL", "Let their sword hit yours"],
	## Both of these name the thing to do and the thing to notice, and neither
	## names a number. A player who is told the mechanism stops watching the
	## fight; a player who is told where to hit learns the mechanism from the
	## hits (UX §57).
	TutorialTracker.Step.SWEET_SPOT: ["SWEET SPOT", "Stay clear of their swing, then cut with the middle of your blade"],
	TutorialTracker.Step.MOMENTUM: ["MOMENTUM", "Cut them as they walk in, then again as they walk away"],
	TutorialTracker.Step.COMPLETE: ["TRAINING COMPLETE", "Keep sparring, or press Esc for the menu"],
}


static func tutorial_title(step: TutorialTracker.Step) -> String:
	return str((TUTORIAL_STEPS[step] as Array)[0])


static func tutorial_detail(step: TutorialTracker.Step) -> String:
	return str((TUTORIAL_STEPS[step] as Array)[1])


static func opponent_label(config: MatchConfig) -> String:
	if config.mode == MatchConfig.Mode.TRAINING:
		return DUMMY
	return CPU % MatchConfig.difficulty_label(config.cpu_difficulty)


## The input a binding names: the engine's own key name (it follows the
## physical key, as the binding does), a mouse button, or none.
static func binding_label(binding: int) -> String:
	if binding > 0:
		return OS.get_keycode_string(binding as Key)
	if binding < 0:
		return str(MOUSE_BUTTON_LABELS.get(-binding, BINDING_NONE))
	return BINDING_NONE


static func binding_action(action: StringName) -> String:
	return str(BINDING_ACTIONS.get(action, String(action)))


static func difficulty_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for difficulty: MatchConfig.Difficulty in [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]:
		labels.append(MatchConfig.difficulty_label(difficulty))
	return labels
