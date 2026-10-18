class_name FighterVictoryProfile
extends Resource

## How a fighter is shown when they win a set (PRES-VICTORY-001): the card, the
## announcer's line, the authored cinematic, and its beats. The fighter's own
## victory call is `PresentationKit.character_call`. The match horn belongs to
## the arena. All content: a new fighter or a second victory is a new profile,
## never code.
##
## Times are seconds from the moment the showcase enters (real time — the duel
## is over). The camera framings are relative to the actor: `position` in the
## actor's local space (+Z is where the fighter faces), looking at
## `look_height` up its centre line.
##
## See also: /docs/concepts/presentation.md

@export var display_name: String = ""
@export var title: String = "VICTOR"
## What the announcer reads, and its caption. Read correctly here, whatever the
## intro read: the joke lands because the name is finally right.
@export var announcer_caption: String = ""
@export var announcer_line: AudioStream

## The one-shot cinematic and the settled loop that follows it: a quick cut,
## the quick return cut, then the gather into the same high shoulder load the
## duel's carriage uses — and HOLD. No third, released attack. The idle is a
## subtle breathing version of that held load.
@export var combo_clip: StringName = &"victory_combo"
@export var idle_clip: StringName = &"victory_idle"

## Beats (seconds from entry), keyed to the authored clip.
@export var quick_cut_1_time: float = 0.13
@export var quick_cut_2_time: float = 0.4
## The return cut is through; the last part of its streak becomes the divider.
@export var quick_cut_2_end_time: float = 0.57
@export var charge_start_time: float = 0.7
## The load is gathered and held: the fighter's howl starts here. The arena
## horn is a separate sting and does not play in this cinematic.
@export var charge_lock_time: float = 1.2
@export var camera_push_start: float = 1.2
@export var camera_push_end: float = 2.0
@export var card_time: float = 1.5
@export var announcer_time: float = 1.85
@export var interactive_time: float = 2.2

## Camera: a full-body 3/4 to start, pushed to a chest-and-head hero frame.
@export var camera_start: Vector3 = Vector3(1.6, 1.25, 3.4)
@export var camera_finish: Vector3 = Vector3(0.8, 1.55, 2.0)
@export var look_start_height: float = 1.0
@export var look_finish_height: float = 1.4
@export var fov_start: float = 42.0
@export var fov_finish: float = 36.0


## The beats in timeline order, for validation and tests.
func beat_times() -> PackedFloat64Array:
	return PackedFloat64Array([
		quick_cut_1_time, quick_cut_2_time, quick_cut_2_end_time, charge_start_time, charge_lock_time,
		camera_push_end, interactive_time,
	])


## True when every beat comes no earlier than the one before it.
func is_ordered() -> bool:
	var beats := beat_times()
	for index in range(1, beats.size()):
		if beats[index] < beats[index - 1]:
			return false
	return true
