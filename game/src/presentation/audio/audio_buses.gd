class_name AudioBuses
extends RefCounted

## Audio bus names from res://default_bus_layout.tres (Music and SFX send to
## Master). Godot loads the layout before any node plays, so players route by
## these names and the volume settings scale them; nothing creates buses at
## runtime.
##
## See also: /docs/concepts/presentation.md

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
