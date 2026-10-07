class_name CameraShakeRequest
extends RefCounted

## A typed instruction to shake the camera. The director decides intensity and
## shape from physics; CameraFeedback converts it to trauma and offset.
##
## See also: /docs/architecture/presentation-feedback.md

## Semantic intensity 0–100. Normal hit: severity01 × 50. Kill: 100 override.
var intensity: float = 0.0
## Initial kick direction (world space, normalized). Zero = omnidirectional.
var direction: Vector3 = Vector3.ZERO
## Shape hint: how the shake decays. Different contact types have different
## frequency/duration characteristics.
var profile: Profile = Profile.BODY


enum Profile {
	## Blade clash: short, high-frequency.
	BLADE,
	## Body hit: heavier, lower-frequency.
	BODY,
	## Poke: small directional jab.
	POKE,
	## Thrust: strong axial kick.
	THRUST,
	## Lethal override: exceptional.
	KILL,
}


static func create(p_intensity: float, p_direction: Vector3 = Vector3.ZERO, p_profile: Profile = Profile.BODY) -> CameraShakeRequest:
	var req := CameraShakeRequest.new()
	req.intensity = p_intensity
	req.direction = p_direction
	req.profile = p_profile
	return req
