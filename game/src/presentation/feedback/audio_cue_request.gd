class_name AudioCueRequest
extends RefCounted

## A typed instruction to play a sound. The director classifies the event;
## AudioPresenter resolves the kit cue to a stream and plays it.
##
## See also: /docs/architecture/presentation-feedback.md

enum KitSource { WEAPON, ARENA }

## Kit cue name (e.g. PresentationKit.CUE_BLADE_LIGHT).
var cue: StringName = &""
## World-space position for spatial audio. Zero = flat (non-positional).
var world_position: Vector3 = Vector3.ZERO
## Volume adjustment in dB.
var volume_db: float = 0.0
## Pitch scale (1.0 = normal).
var pitch: float = 1.0
## Which kit to resolve the cue from.
var kit_source: KitSource = KitSource.WEAPON
## Variant key derived from the event (tick, actor): the same event always
## picks the same take, so a replay sounds identical.
var key: int = 0
## Held cues (the bind grind) loop until the presenter releases them.
var hold: bool = false
## Arena cues that are flat stingers rather than positioned sounds.
var flat: bool = false


static func create(p_cue: StringName, p_position: Vector3 = Vector3.ZERO, p_volume_db: float = 0.0, p_pitch: float = 1.0, p_source: KitSource = KitSource.WEAPON, p_key: int = 0) -> AudioCueRequest:
	var req := AudioCueRequest.new()
	req.cue = p_cue
	req.world_position = p_position
	req.volume_db = p_volume_db
	req.pitch = p_pitch
	req.kit_source = p_source
	req.key = p_key
	req.flat = p_source == KitSource.ARENA
	return req
