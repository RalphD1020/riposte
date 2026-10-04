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

const ROTATE_TITLE := "Rotate your device"
const ROTATE_BODY := "Rotate your device for the best duel experience."
const CONTINUE_ANYWAY := "CONTINUE ANYWAY"

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

const SETTINGS_SECTIONS: PackedStringArray = ["Audio", "Display", "Gameplay", "Controls"]
const SETTING_MASTER := "Master volume"
const SETTING_MUSIC := "Music volume"
const SETTING_SFX := "Effects volume"
const SETTING_FULLSCREEN := "Fullscreen"
const SETTING_REDUCED_MOTION := "Reduced motion"
const SETTING_REDUCED_FLASH := "Reduced flash"
const SETTING_CHARGE_INDICATOR := "Show charge indicator"
const SETTING_HIGH_CONTRAST := "High contrast weapons"
const SETTING_SCREEN_SHAKE := "Screen shake"
const SETTING_CONTROL_OPACITY := "Touch control opacity"
const SETTING_HAPTICS := "Haptics"
const OPACITY_LEVELS: PackedStringArray = ["Low", "Medium", "High"]
const SETTINGS_NOT_SAVED := "Settings could not be saved on this device; they last for this visit."

const TUTORIAL_STEPS := {
	TutorialTracker.Step.MOVE: ["MOVE", "WASD or left thumb"],
	TutorialTracker.Step.QUICK_CUT: ["QUICK CUT", "Tap attack"],
	TutorialTracker.Step.CHARGE: ["CHARGE", "Hold attack"],
	TutorialTracker.Step.RELEASE: ["RELEASE", "Let go to swing"],
	TutorialTracker.Step.BLADES: ["BLADES ARE PHYSICAL", "Let their sword hit yours"],
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


static func difficulty_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for difficulty: MatchConfig.Difficulty in [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]:
		labels.append(MatchConfig.difficulty_label(difficulty))
	return labels
