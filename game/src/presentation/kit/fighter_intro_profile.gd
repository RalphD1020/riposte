class_name FighterIntroProfile
extends Resource

## How a fighter is presented in the once-per-set introduction: the card,
## the line the announcer reads, and the flourish the showcase plays.
##
## `spoken_override_first_slot` exists for one deliberate bit: when this
## fighter is introduced first, the announcer may read a different line
## (and caption) than the name. It is content, never code.
##
## See also: /docs/concepts/presentation.md

@export var display_name: String = ""
@export var spoken_name: String = ""
@export var spoken_override_first_slot: String = ""
@export var spoken_override_first_slot_line: AudioStream
## Animation semantic or clip the showcase plays (default: the idle guard).
@export var intro_clip: StringName = &""


## The caption the announcer reads for this fighter in `slot`.
func spoken_for(slot: int) -> String:
	if slot == 0 and spoken_override_first_slot != "":
		return spoken_override_first_slot
	return spoken_name if spoken_name != "" else display_name


func line_for(slot: int, voice: FighterVoiceKit) -> AudioStream:
	if slot == 0 and spoken_override_first_slot != "" and spoken_override_first_slot_line != null:
		return spoken_override_first_slot_line
	return voice.spoken_name if voice != null else null
