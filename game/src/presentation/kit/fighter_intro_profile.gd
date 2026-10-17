class_name FighterIntroProfile
extends Resource

## How a fighter is presented in the once-per-set introduction: the card and
## the line the announcer reads. The motion is not content: it is real play,
## recorded through the simulation (`IntroTake`). A fighter is read by one
## name whichever slot it is introduced in, mirror matches included.
##
## See also: /docs/concepts/presentation.md

@export var display_name: String = ""
@export var spoken_name: String = ""


## The caption the announcer reads for this fighter.
func spoken() -> String:
	return spoken_name if spoken_name != "" else display_name


func line(voice: FighterVoiceKit) -> AudioStream:
	return voice.spoken_name if voice != null else null
