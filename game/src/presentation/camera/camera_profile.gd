class_name CameraProfile
extends RefCounted

## Authored duel camera (UX §4–§5): elevated 3/4 view, fixed orientation, mild
## perspective, midpoint framing that breathes with separation. Values are
## content (RiposteKits.camera_profile); the rig only reads them.
##
## See also: /docs/concepts/presentation.md

var pitch_degrees: float = 0.0
var fov_degrees: float = 0.0
var base_distance: float = 0.0
var separation_gain: float = 0.0
var min_distance: float = 0.0
var max_distance: float = 0.0
## Exponential smoothing rates (1/s) for focus and zoom.
var follow_rate: float = 0.0
var zoom_rate: float = 0.0
## Touch layouts move the focus toward the camera so the duel sits higher.
var touch_focus_bias: float = 0.0
var impulse_decay: float = 0.0
var max_impulse: float = 0.0
var near: float = 0.05
var far: float = 200.0


func is_valid() -> bool:
	return (
		pitch_degrees > 0.0
		and pitch_degrees < 90.0
		and fov_degrees > 0.0
		and min_distance > 0.0
		and min_distance <= max_distance
		and follow_rate > 0.0
		and zoom_rate > 0.0
	)


func distance_for(separation: float) -> float:
	return clampf(base_distance + separation * separation_gain, min_distance, max_distance)
