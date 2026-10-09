class_name AnnouncerKit
extends Resource

## The caster's set-level lines. Played on the Voice bus; every line has a
## caption so the intro reads with sound off.
##
## See also: /docs/concepts/presentation.md

@export var announcer_id: StringName = &""
@export var versus: AudioStream
@export var duel: AudioStream
## Short musical/metal sting under the wide shot.
@export var sting: AudioStream
@export var versus_caption: String = "VERSUS"
@export var duel_caption: String = "DUEL!"
