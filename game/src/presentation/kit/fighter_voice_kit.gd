class_name FighterVoiceKit
extends Resource

## How a fighter is announced and how they sound under effort. Lines are
## optional; a missing line is silent and its caption still shows (UX-001:
## nothing is conveyed by sound alone).
##
## See also: /docs/concepts/presentation.md

@export var voice_id: StringName = &""
## The announcer reading this fighter's name.
@export var spoken_name: AudioStream
## Effort and hurt vocalizations; selected deterministically like SFX variants.
@export var grunts: Array[AudioStream] = []
@export var hurt: Array[AudioStream] = []
