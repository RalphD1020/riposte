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
## How much cross-jitter a directional impulse keeps. Enough that the nudge
## does not look mechanical, little enough that the direction still reads.
const DIRECTIONAL_JITTER := 0.35
## Cosmetic shake only; fixed so captures are repeatable.
const SHAKE_SEED := 1

var _camera: Camera3D
var _profile: CameraProfile
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 10.0
## Whole-rig yaw, used only to put the local player at the bottom of the
## screen (SIDE-001). This is the one thing in the duel that is allowed to
## differ between two people watching the same match, which is exactly why it
## lives here and never in authoritative state: the world has one orientation,
## and only the viewer turns.
var _yaw: float = 0.0
var _impulse: float = 0.0
## World direction of the impact currently being reinforced, if it had one.
var _direction: Vector3 = Vector3.ZERO
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


## Orient the view for whoever is playing locally. A Light player is already
## at the bottom of the screen, so their yaw is zero; a Dark player's view is
## turned half a revolution so they are too.
##
## Nothing downstream of this needs to know: footwork is expressed in duel
## axes (MOVE-001), whose "right" is the forward axis turned a quarter turn
## clockwise, so local D projects right on screen for both sides once the rig
## has turned.
func look_from(side: DuelSide.Id) -> void:
	_yaw = PI if side == DuelSide.Id.DARK_NORTH else 0.0
	if _profile != null:
		_apply()


func yaw() -> float:
	return _yaw


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
		## The bias lifts the action clear of the thumbs, so it is relative to
		## the screen, not the world: it has to turn with the view or a Dark
		## player's fighters would be pushed *under* their own controls.
		target += Vector3(0.0, 0.0, _profile.touch_focus_bias).rotated(Vector3.UP, _yaw)
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


## Nudge the rig. `direction` is the world direction the impact pushed in, so
## a strike shifts the view *the way the blow went* instead of rattling the
## frame at random. A zero direction keeps the old untargeted shake, which is
## what a contact with no meaningful direction deserves.
func impulse(strength: float, options: PresentationOptions, direction: Vector3 = Vector3.ZERO) -> void:
	if _profile == null or not options.camera_impulses_enabled():
		return
	if strength > _impulse:
		_direction = direction.normalized() if direction.length_squared() > 0.0 else Vector3.ZERO
	_impulse = clampf(maxf(_impulse, strength), 0.0, _profile.max_impulse)


func impulse_direction() -> Vector3:
	return _direction


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
		## A directional impact leans the view along the blow with only a
		## little jitter across it. An undirected one still just rattles.
		var jitter := Vector3(_shake.randf_range(-1.0, 1.0), 0.0, _shake.randf_range(-1.0, 1.0))
		offset = jitter * _impulse
		if _direction != Vector3.ZERO:
			offset = (_direction + jitter * DIRECTIONAL_JITTER).normalized() * _impulse
	position = _focus + offset
	## The rig carries the yaw and the camera hangs off it at the profile
	## pitch, so the touch focus bias and every impulse stay in world axes and
	## need no separate handling per side.
	rotation = Vector3(0.0, _yaw, 0.0)
	var pitch := deg_to_rad(_profile.pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch) * _distance, cos(pitch) * _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
