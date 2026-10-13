class_name AnnouncerKit
extends Resource

## The caster's set- and round-level lines, all one voice: the intro's
## "versus", and before every round "Match N." then "FIGHT!"
## (PRES-ROUND-START-001). Played on the Voice bus; every line has a caption
## so the moment reads with sound off. Pre-generated takes, never synthesized
## at runtime.
##
## See also: /docs/concepts/presentation.md

@export var announcer_id: StringName = &""
@export var versus: AudioStream
## Short musical/metal sting as the intro hands back to the arena.
@export var sting: AudioStream
@export var versus_caption: String = "VERSUS"
## "Match one." … one take per match number, first entry = match 1. A match
## past the last take is announced by its card alone.
@export var match_numbers: Array[AudioStream] = []
@export var match_caption: String = "MATCH %d"
## The call that opens every round, on the beat the round goes live.
@export var fight: AudioStream
@export var fight_caption: String = "FIGHT!"


## The take for match `number` (1-based), or null past the last one.
func match_line(number: int) -> AudioStream:
	return match_numbers[number - 1] if number >= 1 and number <= match_numbers.size() else null
