class_name DuelCameraRig
extends Node3D

## Persistent duel camera. The rig sits at the framing focus on the ground;
## its Camera3D child looks down at the fixed profile pitch. No player
## rotation, no swinging behind fighters, smooth predictable zoom (UX §5):
## camera stability is competitive information. Impulses are tiny, decay
## fast, and are disabled by Reduced Motion or Screen Shake off.
##
## See also: /docs/concepts/presentation.md

const IMPULSE_FLOOR := 0.001
## Cosmetic shake only; fixed so captures are repeatable.
const SHAKE_SEED := 1

var _camera: Camera3D
var _profile: CameraProfile
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 10.0
var _impulse: float = 0.0
var _shake := RandomNumberGenerator.new()


func _ready() -> void:
	_ensure_camera()


func configure(profile: CameraProfile) -> void:
	_profile = profile
	_ensure_camera()
	_camera.fov = profile.fov_degrees
	_camera.near = profile.near
	_camera.far = profile.far
	_camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_DISABLED
	_shake.seed = SHAKE_SEED
	_distance = profile.distance_for(0.0)
	_apply()


func camera() -> Camera3D:
	_ensure_camera()
	return _camera


func focus() -> Vector3:
	return _focus


func distance() -> float:
	return _distance


func impulse_strength() -> float:
	return _impulse


## Frame both fighters; `snap` jumps instantly (round reset, first frame).
func frame(a: Vector3, b: Vector3, delta: float, options: PresentationOptions, snap: bool) -> void:
	if _profile == null:
		return
	var target := (a + b) * 0.5
	if options.touch_layout:
		target.z += _profile.touch_focus_bias
	var target_distance := _profile.distance_for(a.distance_to(b))
	if snap:
		_focus = target
		_distance = target_distance
	else:
		_focus = _focus.lerp(target, 1.0 - exp(-_profile.follow_rate * delta))
		_distance = lerpf(_distance, target_distance, 1.0 - exp(-_profile.zoom_rate * delta))
	_impulse *= exp(-_profile.impulse_decay * delta)
	if _impulse < IMPULSE_FLOOR:
		_impulse = 0.0
	_fit_aspect()
	_apply()


func impulse(strength: float, options: PresentationOptions) -> void:
	if _profile == null or not options.camera_impulses_enabled():
		return
	_impulse = clampf(maxf(_impulse, strength), 0.0, _profile.max_impulse)


func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	add_child(_camera)


## Landscape keeps height; portrait keeps width so the arena never crops.
func _fit_aspect() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var size := viewport.get_visible_rect().size
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y > size.x else Camera3D.KEEP_HEIGHT


func _apply() -> void:
	var offset := Vector3.ZERO
	if _impulse > 0.0:
		offset = Vector3(_shake.randf_range(-1.0, 1.0), 0.0, _shake.randf_range(-1.0, 1.0)) * _impulse
	position = _focus + offset
	var pitch := deg_to_rad(_profile.pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch) * _distance, cos(pitch) * _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
