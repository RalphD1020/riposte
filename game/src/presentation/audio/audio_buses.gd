class_name AudioBuses
extends RefCounted

## Audio bus names from res://default_bus_layout.tres. Music, SFX, Voice, and
## Crowd send to Master; Combat and UI send to SFX. Godot loads the layout
## before any node plays, so players route by these names and the volume
## settings scale them; nothing creates buses at runtime.
##
## See also: /docs/concepts/presentation.md

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
## Children of SFX: combat contacts and swings, and menu/HUD interaction.
const COMBAT := &"Combat"
const UI := &"UI"
## Announcer and fighter vocalizations, with their own volume setting.
const VOICE := &"Voice"
## Audience bed and reactions. Not part of Music or SFX.
const CROWD := &"Crowd"
const ALL: Array[StringName] = [MASTER, MUSIC, SFX, COMBAT, UI, VOICE, CROWD]
