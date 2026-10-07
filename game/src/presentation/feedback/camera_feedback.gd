class_name CameraFeedback
extends RefCounted

## Trauma-based camera shake. Consumes CameraShakeRequests, produces a camera
## offset that CameraController combines with its base framing. Pure math —
## no SceneTree dependency.
##
## Model: trauma = clamp(trauma + input, 0, 1); amplitude = trauma²;
## decay is exponential per wall-clock delta. Multiple clashes accumulate;
## lethal impacts are exceptional. No per-frame random teleport: uses
## deterministic coherent noise with an initial directional kick.
##
## See also: /docs/architecture/presentation-feedback.md

## How quickly trauma decays (per second). Higher = faster recovery.
const DECAY_RATE := 3.0
## Maximum camera offset in world units at trauma = 1.
const MAX_OFFSET := 0.14
## How much of the offset comes from the initial directional kick vs noise.
const KICK_SHARE := 0.6
## Frequency of the noise oscillation (Hz).
const NOISE_FREQUENCY := 18.0
## Seed for deterministic noise phase.
const NOISE_SEED_X := 1.618
const NOISE_SEED_Y := 3.141

var _trauma: float = 0.0
var _kick_direction: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _settings_scale: float = 1.0


func apply_requests(requests: Array[CameraShakeRequest], settings_scale: float) -> void:
	_settings_scale = settings_scale
	for request in requests:
		var normalized := clampf(request.intensity / 100.0, 0.0, 1.0) * _settings_scale
		_trauma = clampf(_trauma + normalized, 0.0, 1.0)
		if request.direction.length_squared() > 0.0:
			_kick_direction = request.direction.normalized() * normalized


func advance(delta: float) -> Vector3:
	if _trauma <= 0.0:
		_kick_direction = Vector3.ZERO
		return Vector3.ZERO
	_time += delta
	var amplitude := _trauma * _trauma
	var kick := _kick_direction * KICK_SHARE * amplitude
	var noise_x := sin(_time * NOISE_FREQUENCY * TAU + NOISE_SEED_X) * (1.0 - KICK_SHARE) * amplitude
	var noise_y := sin(_time * NOISE_FREQUENCY * TAU * 0.7 + NOISE_SEED_Y) * (1.0 - KICK_SHARE) * amplitude
	var offset := kick + Vector3(noise_x, noise_y, 0.0)
	_trauma = maxf(_trauma - DECAY_RATE * delta, 0.0)
	_kick_direction = _kick_direction * maxf(1.0 - DECAY_RATE * 2.0 * delta, 0.0)
	return offset * MAX_OFFSET


func reset() -> void:
	_trauma = 0.0
	_kick_direction = Vector3.ZERO
	_time = 0.0


func trauma() -> float:
	return _trauma
